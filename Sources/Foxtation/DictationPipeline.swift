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

    /// The cleanup request, or nil when cloud cleanup is off, this Mac isn't
    /// activated, or (with "skip when clean" on) there's nothing to fix.
    static func request(for raw: Transcript, target: DictationTarget,
                        settings: Settings, library: Library) -> CleanupRequest? {
        guard settings.cloudCleanup, !settings.activationID.isEmpty, !raw.text.isEmpty else { return nil }
        let style = library.style(forBundleID: target.bundleID)
        if settings.skipCleanWhenNothingToFix, !needsCloud(raw.text, style: style) { return nil }
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

    /// The local steps that run on every path, cloud or not: the style's simple
    /// rules when the cloud didn't apply it, dictionary spelling, replacements
    /// for the target's group, then snippet expansion.
    static func finish(_ text: String, target: DictationTarget, library: Library, cloudStyled: Bool = false) -> String {
        var result = text
        if !cloudStyled { result = applyStyleLocally(result, style: library.style(forBundleID: target.bundleID)) }
        result = fixSpelling(result, terms: library.vocabulary)
        let group = library.group(forBundleID: target.bundleID)
        return library.expandSnippets(library.applyReplacements(result, group: group))
    }

    // MARK: - Dictionary spelling

    /// Replaces words that are almost a dictionary term with its exact spelling:
    /// "jakmal" or "jack mall" → "Jakmall", "Haisa Studio" → "Khaisa Studio".
    /// Short terms (under 5 letters) must match exactly apart from case.
    static func fixSpelling(_ text: String, terms: [String]) -> String {
        guard !terms.isEmpty else { return text }
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let target = squash(term)
            guard !target.isEmpty else { continue }
            let allowed = target.count < 5 ? 0 : target.count < 8 ? 1 : 2
            let span = term.split(separator: " ").count
            var index = 0
            while index < words.count {
                // Try the term's own word count, then one more or one fewer ("jack mall" for "Jakmall").
                for length in Set([span, span + 1, max(1, span - 1)]).sorted(by: >) where index + length <= words.count {
                    let window = words[index..<index + length]
                    let candidate = squash(window.joined())
                    guard !candidate.isEmpty, abs(candidate.count - target.count) <= allowed,
                          distance(candidate, target) <= allowed else { continue }
                    // Keep punctuation that was attached to the last word.
                    let trailing = String(window.last!.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
                    let leading = String(window.first!.prefix { !$0.isLetter && !$0.isNumber })
                    words.replaceSubrange(index..<index + length, with: [leading + term + trailing])
                    break
                }
                index += 1
            }
        }
        return words.joined(separator: " ")
    }

    /// Lowercased letters and digits only.
    private static func squash(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Levenshtein distance.
    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Skipping the cloud

    // What only cloud cleanup can fix. Whisper already punctuates and capitalizes.
    static let fillers = ["eh", "ehm", "em", "emm", "hmm", "anu", "apa ya", "uh", "uhm", "um", "umm", "erm", "you know"]
    static let corrections = ["maksudnya", "maksud saya", "maksud aku", "eh bukan", "bukan bukan",
                              "no wait", "i mean", "scratch that", "sorry"]
    static let listCues = ["pertama", "kedua", "ketiga", "first", "second", "third"]

    /// Whether cloud cleanup would change anything Foxtation can't do itself.
    /// A misheard word ("batch kent" for "backend") can't be spotted here, so
    /// only a short phrase with nothing else to fix stays local.
    static func needsCloud(_ text: String, style: CleanupStyle?) -> Bool {
        if style == .formal { return true }  // rewording needs the model
        let phrases = fillers + corrections + listCues + ["emoji"]
        if phrases.contains(where: { Library.replacingPhrase($0, with: "", in: text).count > 0 }) { return true }
        return Dictation.wordCount(text) > 4
    }

    /// The parts of a style simple enough to apply here.
    static func applyStyleLocally(_ text: String, style: CleanupStyle?) -> String {
        switch style {
        case .casual:
            return text.hasSuffix(".") && !text.hasSuffix("..") ? String(text.dropLast()) : text
        case .literal:
            var result = text.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            if let first = result.first, first.isUppercase, result.dropFirst().first?.isLowercase == true {
                result = first.lowercased() + result.dropFirst()
            }
            return result
        case .neutral, .formal, nil:
            return text
        }
    }
}
