import Combine
import Foundation

enum CloudError: LocalizedError {
    case invalidLicense
    case activationLimit
    case dailyLimit(CloudUsage?)
    case offline
    /// 404: the server doesn't have this endpoint yet (older deployment), or
    /// for deactivate, the activation is already gone.
    case notAvailable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidLicense: return "Foxtation Cloud license is not valid"
        case .activationLimit: return "License is already active on the maximum number of Macs"
        case .dailyLimit: return "Daily Foxtation Cloud limit reached"
        case .offline: return "Foxtation Cloud is unreachable"
        case .notAvailable: return "Not available on this server yet"
        case .server(let message): return "Foxtation Cloud: \(message)"
        }
    }

    /// One line for the pill when dictation falls back to the raw transcript.
    var fallbackLabel: String {
        switch self {
        case .dailyLimit: return "Daily limit reached"
        case .offline: return "Offline"
        case .invalidLicense, .activationLimit: return "License problem"
        case .notAvailable, .server: return "Cleanup failed"
        }
    }
}

/// What Foxtation Cloud changed, as counted by the model. Display only.
struct CloudChanges: Codable, Hashable {
    var fillersRemoved = 0
    var selfCorrections = 0
    var formattingFixes = 0

    var total: Int { fillersRemoved + selfCorrections + formattingFixes }
}

struct CloudUsage: Codable, Hashable {
    var used: Int
    var limit: Int
    /// ISO 8601, the next 00:00 UTC.
    var resetsAt: String

    var resetDate: Date? { parseISODate(resetsAt) }
}

struct CloudLicense: Codable, Hashable {
    struct Activations: Codable, Hashable { var used: Int?; var limit: Int? }
    struct Device: Codable, Hashable { var activationId: String; var label: String?; var createdAt: String? }

    var status: String
    var displayKey: String?
    var expiresAt: String?
    var activations: Activations
    var thisDevice: Device
    var portalUrl: String
}

/// The cleanup styles the server understands.
enum CleanupStyle: String, Codable, CaseIterable {
    case casual, neutral, formal, literal
}

struct CleanupRequest {
    var text: String
    var language: String
    var app: String?
    var vocabulary: [String] = []
    var snippetCues: [String] = []
    var style: CleanupStyle?
    var spokenEmoji = false
}

struct CleanupReply: Decodable {
    var text: String
    var changes: CloudChanges?
    var usage: CloudUsage?
}

/// Foxtation Cloud tidies a raw transcript: drops filler words, applies
/// self-corrections, fixes punctuation. Only the text is sent, never audio.
/// The service runs on the Foxtation server and needs a paid license key.
/// Every reply field newer than `text` is optional, so an older server still works.
enum CloudCleanup {

    static let server = URL(string: "https://foxtation.khaisa.studio")!
    /// The plans (monthly or yearly) are on the website, so prices can change without an update.
    static let buyURL = URL(string: "https://foxtation.khaisa.studio/#pro")!
    static let portalURL = URL(string: "https://polar.sh/khaisa-studios/portal")!

    // Server-side caps; the app trims to them before sending.
    static let maxVocabulary = 300
    static let maxSnippetCues = 100
    static let maxTermLength = 64

    static func clean(_ request: CleanupRequest, licenseKey: String, activationID: String) async throws -> CleanupReply {
        var body: [String: Any] = ["text": request.text, "language": request.language, "app": request.app ?? ""]
        let vocabulary = terms(request.vocabulary, max: maxVocabulary)
        let cues = terms(request.snippetCues, max: maxSnippetCues)
        if !vocabulary.isEmpty { body["vocabulary"] = vocabulary }
        if !cues.isEmpty { body["snippet_cues"] = cues }
        if let style = request.style { body["style"] = style.rawValue }
        if request.spokenEmoji { body["options"] = ["spoken_emoji": true] }

        let data = try await post("v1/cleanup", body: body, licenseKey: licenseKey, activationID: activationID)
        guard let reply = try? decoder.decode(CleanupReply.self, from: data), !reply.text.isEmpty else {
            throw CloudError.server("unexpected reply")
        }
        return reply
    }

    // MARK: Transcription

    /// A dictation transcribed in Foxtation Cloud (Pro): each stretch of speech
    /// goes to ElevenLabs Scribe, or Whisper large-v3 after an hour a day. Nothing
    /// to download. `language` "auto" picks among `languages`.
    static func session(language: String, among languages: [String],
                        licenseKey: String, activationID: String) -> SpeechSession {
        SpeechSession { chunk in
            try await transcribe(chunk, language: language, among: languages,
                                 licenseKey: licenseKey, activationID: activationID)
        }
    }

    static func transcribe(_ samples: [Float], language: String, among languages: [String],
                           licenseKey: String, activationID: String) async throws -> (text: String, language: String) {
        let data = try await send("v1/transcribe",
                                  query: [URLQueryItem(name: "language", value: language),
                                          URLQueryItem(name: "languages", value: languages.joined(separator: ","))],
                                  data: WavWriter.data(samples: samples, sampleRate: Double(SpeechSession.sampleRate)),
                                  type: "audio/wav", licenseKey: licenseKey, activationID: activationID)
        struct Heard: Decodable { var text: String; var language: String }
        guard let heard = try? JSONDecoder().decode(Heard.self, from: data) else { throw CloudError.server("unexpected reply") }
        return (heard.text, heard.language)
    }

    /// Opens (or refreshes) the HTTPS connection so the next request skips the
    /// TLS handshake. Fire and forget; the server answers 404.
    static func warmUp() {
        var request = URLRequest(url: server)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request).resume()
    }

    /// Registers this Mac against the license and returns its activation ID.
    static func activate(_ licenseKey: String) async throws -> String {
        let label = Host.current().localizedName ?? "Mac"
        let data = try await post("v1/activate", body: ["label": label], licenseKey: licenseKey, activationID: "")
        guard let reply = try? JSONDecoder().decode([String: String].self, from: data),
              let id = reply["activation_id"] else {
            throw CloudError.server("unexpected reply")
        }
        return id
    }

    static func usage(licenseKey: String, activationID: String) async throws -> CloudUsage {
        let data = try await post("v1/usage", body: [:], licenseKey: licenseKey, activationID: activationID)
        return try decoder.decode(CloudUsage.self, from: data)
    }

    static func license(licenseKey: String, activationID: String) async throws -> CloudLicense {
        let data = try await post("v1/license", body: [:], licenseKey: licenseKey, activationID: activationID)
        return try decoder.decode(CloudLicense.self, from: data)
    }

    static func deactivate(licenseKey: String, activationID: String) async throws {
        _ = try await post("v1/deactivate", body: [:], licenseKey: licenseKey, activationID: activationID)
    }

    // MARK: - Plumbing

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Trimmed, 1–64 characters, one line, case-insensitively unique, at most `max`.
    static func terms(_ values: [String], max: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, term.count <= maxTermLength, !term.contains(where: \.isNewline),
                  seen.insert(term.lowercased()).inserted else { continue }
            result.append(term)
            if result.count == max { break }
        }
        return result
    }

    private static func post(_ path: String, body: [String: Any],
                             licenseKey: String, activationID: String) async throws -> Data {
        try await send(path, data: try JSONSerialization.data(withJSONObject: body), type: "application/json",
                       licenseKey: licenseKey, activationID: activationID)
    }

    private static func send(_ path: String, query: [URLQueryItem] = [], data body: Data, type: String,
                             licenseKey: String, activationID: String) async throws -> Data {
        var url = URLComponents(url: server.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { url.queryItems = query }
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue(activationID, forHTTPHeaderField: "X-Foxtation-Activation")
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CloudError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200, 204: return data
        case 401: throw CloudError.invalidLicense
        case 403: throw CloudError.activationLimit
        case 404: throw CloudError.notAvailable
        case 429:
            struct Limited: Decodable { var usage: CloudUsage? }
            throw CloudError.dailyLimit((try? decoder.decode(Limited.self, from: data))?.usage)
        default:
            let reply = try? JSONDecoder().decode([String: String].self, from: data)
            throw CloudError.server(reply?["error"] ?? "HTTP \(status)")
        }
    }
}

/// Usage and license details the window shows, refreshed after each cleanup
/// and when a screen asks.
final class CloudStatus: ObservableObject {
    static let shared = CloudStatus(settings: .shared)

    @Published var usage: CloudUsage?
    @Published var license: CloudLicense?
    /// Set when the last license refresh failed (offline, revoked, older server).
    @Published var licenseError: String?

    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    var isActivated: Bool { !settings.activationID.isEmpty }

    @MainActor
    func refresh() async {
        guard isActivated else {
            usage = nil
            license = nil
            return
        }
        let key = settings.licenseKey, id = settings.activationID
        if let usage = try? await CloudCleanup.usage(licenseKey: key, activationID: id) { self.usage = usage }
        do {
            license = try await CloudCleanup.license(licenseKey: key, activationID: id)
            licenseError = nil
        } catch {
            licenseError = error.localizedDescription
        }
    }

    /// Frees this Mac's activation. It's forgotten locally only once the server
    /// confirms (or says it's already gone); offline or a server error keeps it,
    /// so the slot isn't lost while still counted.
    @MainActor
    func deactivate() async throws {
        do {
            try await CloudCleanup.deactivate(licenseKey: settings.licenseKey, activationID: settings.activationID)
        } catch CloudError.notAvailable {
            // Already gone on the server.
        }
        settings.activationID = ""
        if settings.engine == .cloud { settings.engine = .whisperKit }
        license = nil
        usage = nil
    }
}

/// Parses the server's and Polar's ISO 8601 timestamps, with or without fractions.
func parseISODate(_ value: String?) -> Date? {
    guard var value else { return nil }
    // Polar sends microseconds; the formatter only reads up to milliseconds.
    if let range = value.range(of: #"\.\d{4,}"#, options: .regularExpression) {
        value.replaceSubrange(range, with: String(value[range].prefix(4)))
    }
    let withFractions = ISO8601DateFormatter()
    withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractions.date(from: value) { return date }
    return ISO8601DateFormatter().date(from: value)
}
