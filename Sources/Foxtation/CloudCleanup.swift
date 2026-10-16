import Foundation

enum CloudError: LocalizedError {
    case invalidLicense
    case activationLimit
    case dailyLimit(CloudUsage?)
    case offline
    /// The server doesn't know this endpoint yet (404).
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

    /// First half of the fallback pill: "<reason> · raw text pasted".
    var pillReason: String {
        switch self {
        case .dailyLimit: return "Daily limit reached"
        case .offline: return "Offline"
        case .invalidLicense, .activationLimit: return "License problem"
        case .notAvailable, .server: return "Cleanup unavailable"
        }
    }
}

struct CleanupChanges: Codable {
    var fillers_removed: Int
    var self_corrections: Int
    var formatting_fixes: Int
}

struct CloudUsage: Codable {
    var used: Int
    var limit: Int
    var resets_at: String?

    var resetsAt: Date? { resets_at.flatMap { ISO8601DateFormatter.cloud.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } }
}

struct LicenseInfo: Decodable {
    struct Activations: Decodable { var used: Int?; var limit: Int? }
    struct Device: Decodable { var activation_id: String?; var label: String?; var created_at: String? }

    var status: String?
    var display_key: String?
    var expires_at: String?
    var activations: Activations?
    var this_device: Device?
    var portal_url: String?
}

struct CleanupRequest: Encodable {
    struct Options: Encodable { var spoken_emoji: Bool }

    var text: String
    var language: String
    var app: String?
    var vocabulary: [String]?
    var snippet_cues: [String]?
    var style: String?
    var options: Options?
}

/// Error bodies: `{error}`, plus `usage` on 429.
struct ErrorReply: Decodable {
    var error: String?
    var usage: CloudUsage?
}

struct CleanupReply: Decodable {
    var text: String
    var changes: CleanupChanges?
    var usage: CloudUsage?
}

extension ISO8601DateFormatter {
    /// Accepts the fractional seconds JavaScript's toISOString() writes.
    static let cloud: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Foxtation Cloud tidies a raw transcript: drops filler words, applies
/// self-corrections, fixes punctuation. Only the text is sent, never audio.
/// The service runs on the Foxtation server and needs a paid license key.
/// Every field added after the first release is optional, so the app keeps
/// working against an older server.
enum CloudCleanup {

    static let server = URL(string: "https://foxtation.khaisa.studio")!
    static let buyURL = URL(string: "https://buy.polar.sh/polar_cl_pGAbwRd3v6HXPARELwKUmTJlleM9LQDteqWRq41Bn7C")!

    static func clean(_ request: CleanupRequest, licenseKey: String, activationID: String) async throws -> CleanupReply {
        let data = try await post("v1/cleanup", body: request, licenseKey: licenseKey, activationID: activationID)
        guard let reply = try? JSONDecoder().decode(CleanupReply.self, from: data) else {
            throw CloudError.server("unexpected reply")
        }
        return reply
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
        let data = try await post("v1/usage", body: [String: String](), licenseKey: licenseKey, activationID: activationID)
        guard let usage = try? JSONDecoder().decode(CloudUsage.self, from: data) else { throw CloudError.server("unexpected reply") }
        return usage
    }

    static func license(licenseKey: String, activationID: String) async throws -> LicenseInfo {
        let data = try await post("v1/license", body: [String: String](), licenseKey: licenseKey, activationID: activationID)
        guard let info = try? JSONDecoder().decode(LicenseInfo.self, from: data) else { throw CloudError.server("unexpected reply") }
        return info
    }

    static func deactivate(licenseKey: String, activationID: String) async throws {
        _ = try await post("v1/deactivate", body: [String: String](), licenseKey: licenseKey, activationID: activationID)
    }

    private static func post<Body: Encodable>(_ path: String, body: Body,
                                              licenseKey: String, activationID: String) async throws -> Data {
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        if !activationID.isEmpty { request.setValue(activationID, forHTTPHeaderField: "X-Foxtation-Activation") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CloudError.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) { return data }

        let reply = try? JSONDecoder().decode(ErrorReply.self, from: data)
        switch status {
        case 401: throw CloudError.invalidLicense
        case 403: throw CloudError.activationLimit
        case 404: throw CloudError.notAvailable
        case 429: throw CloudError.dailyLimit(reply?.usage)
        default: throw CloudError.server(reply?.error ?? "HTTP \(status)")
        }
    }
}
