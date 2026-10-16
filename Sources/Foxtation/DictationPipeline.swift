import Foundation

/// The app being dictated into.
struct DictationTarget {
    var name: String
    var bundleID: String
}

/// Everything between "Whisper heard this" and "this gets pasted". The
/// menu-bar app and `--transcribe … --cleanup` both run it.
enum DictationPipeline {

    struct Cleaned {
        var text: String
        var cloud = false
        var changes: CloudChanges?
        /// Set when the raw transcript was used instead; short, for the pill.
        var fallback: String?
        var usage: CloudUsage?
    }

    /// The cleanup request, or nil when cloud cleanup is off or this Mac isn't activated.
    static func request(for raw: Transcript, target: DictationTarget,
                        settings: Settings, library: Library) -> CleanupRequest? {
        guard settings.cloudCleanup, !settings.activationID.isEmpty, !raw.text.isEmpty else { return nil }
        return CleanupRequest(text: raw.text,
                              language: raw.language,
                              app: settings.shareAppName ? target.name : nil,
                              vocabulary: library.vocabulary,
                              snippetCues: library.snippetCues,
                              style: library.style(forBundleID: target.bundleID),
                              spokenEmoji: library.spokenEmoji)
    }

    /// Foxtation Cloud cleanup. Any failure falls back to the raw transcript.
    static func cleanUp(_ raw: Transcript, request: CleanupRequest?,
                        licenseKey: String, activationID: String) async -> Cleaned {
        guard let request else { return Cleaned(text: raw.text) }
        do {
            let reply = try await CloudCleanup.clean(request, licenseKey: licenseKey, activationID: activationID)
            return Cleaned(text: reply.text, cloud: true, changes: reply.changes, usage: reply.usage)
        } catch let error as CloudError {
            NSLog("Foxtation: cloud cleanup failed: %@", error.localizedDescription)
            var usage: CloudUsage?
            if case .dailyLimit(let limited) = error { usage = limited }
            return Cleaned(text: raw.text, fallback: error.fallbackLabel, usage: usage)
        } catch {
            return Cleaned(text: raw.text, fallback: CloudError.server("").fallbackLabel)
        }
    }

    /// The local steps that run on every path, cloud or not: replacements for
    /// the target's group, then snippet expansion.
    static func finish(_ text: String, target: DictationTarget, library: Library) -> String {
        let group = library.group(forBundleID: target.bundleID)
        return library.expandSnippets(library.applyReplacements(text, group: group))
    }
}
