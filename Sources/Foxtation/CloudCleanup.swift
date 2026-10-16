import Foundation

enum CloudError: LocalizedError {
    case invalidLicense
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidLicense: return "Foxtation Cloud license is not valid"
        case .server(let message): return "Foxtation Cloud: \(message)"
        }
    }
}

/// Foxtation Cloud tidies a raw transcript: drops filler words, applies
/// self-corrections, fixes punctuation. Only the text is sent, never audio.
/// The service runs on the Foxtation server and needs a paid license key.
enum CloudCleanup {

    static let server = URL(string: "https://foxtation.khaisa.studio")!
    static let buyURL = URL(string: "https://buy.polar.sh/polar_cl_pGAbwRd3v6HXPARELwKUmTJlleM9LQDteqWRq41Bn7C")!

    static func clean(_ text: String, language: String, app: String?, licenseKey: String) async throws -> String {
        let body: [String: String] = ["text": text, "language": language, "app": app ?? ""]
        let data = try await post("v1/cleanup", body: body, licenseKey: licenseKey)
        guard let reply = try? JSONDecoder().decode([String: String].self, from: data),
              let cleaned = reply["text"] else {
            throw CloudError.server("unexpected reply")
        }
        return cleaned
    }

    static func checkLicense(_ licenseKey: String) async throws {
        _ = try await post("v1/license", body: [:], licenseKey: licenseKey)
    }

    private static func post(_ path: String, body: [String: String], licenseKey: String) async throws -> Data {
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(licenseKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw CloudError.invalidLicense }
        guard status == 200 else {
            let reply = try? JSONDecoder().decode([String: String].self, from: data)
            throw CloudError.server(reply?["error"] ?? "HTTP \(status)")
        }
        return data
    }
}
