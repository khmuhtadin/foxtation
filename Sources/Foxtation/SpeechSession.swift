import Foundation

/// Gets the recorder's 16 kHz samples as they arrive. At each pause after a few
/// seconds of audio it hands that stretch to `transcribe` in the background (one
/// at a time, in order); `finish()` transcribes the tail and joins everything.
/// Stretches of 6 s or more, cut at real pauses, give Whisper whole phrases.
/// `transcribe` runs on this Mac (WhisperKit) or in Foxtation Cloud.
final class SpeechSession {
    static let sampleRate = 16_000
    private static let frame = 1_600                 // 100 ms
    private static let minChunk = 6.0                // seconds before a cut is allowed
    private static let pauseToCut = 0.4              // seconds of silence that end a chunk
    private static let maxChunk = 25.0               // Whisper sees 30 s at a time

    private let transcribe: ([Float]) async throws -> (text: String, language: String)
    private let queue = DispatchQueue(label: "foxtation.speech-session")
    private var incoming: [Float] = []               // not yet a whole frame
    private var pending: [Float] = []                // since the last cut
    private var silence = 0.0
    private var levels: [Float] = []                 // dB of every frame so far
    private var detected: String?                   // the first chunk's, for the transcript
    /// The chain of chunk transcriptions; each waits for the one before.
    private var last: Task<[String], Error>?

    init(transcribe: @escaping ([Float]) async throws -> (text: String, language: String)) {
        self.transcribe = transcribe
    }

    /// Any thread (the recorder calls it from the audio thread).
    func append(_ samples: [Float]) {
        queue.async { self.consume(samples) }
    }

    /// Transcribes what's left and returns the whole transcript.
    func finish() async throws -> Transcript {
        let started = Date()
        let tail: [Float]? = queue.sync {
            pending += incoming
            incoming = []
            return hasSpeech(pending) ? pending : nil
        }
        if let tail { enqueue(tail) }
        let parts = try await last?.value ?? []
        let text = parts.filter { !$0.isEmpty }.joined(separator: " ")
        let language = queue.sync { detected } ?? "auto"
        return Transcript(text: text, language: language, duration: Date().timeIntervalSince(started))
    }

    private func consume(_ samples: [Float]) {
        incoming += samples
        while incoming.count >= Self.frame {
            let frame = Array(incoming.prefix(Self.frame))
            incoming.removeFirst(Self.frame)
            pending += frame
            let level = Self.decibels(frame)
            levels.append(level)
            silence = level < speechLevel() ? silence + 0.1 : 0
            let seconds = Double(pending.count) / Double(Self.sampleRate)
            if (silence >= Self.pauseToCut && seconds >= Self.minChunk) || seconds >= Self.maxChunk {
                // Cut in the middle of the pause.
                let cut = pending.count - Int(silence / 2 * Double(Self.sampleRate))
                let chunk = Array(pending.prefix(cut))
                pending.removeFirst(cut)
                if hasSpeech(chunk) { enqueue(chunk) }
            }
        }
    }

    private func enqueue(_ chunk: [Float]) {
        let previous = last
        last = Task {
            var parts = try await previous?.value ?? []
            let result = try await transcribe(chunk)
            queue.sync { if detected == nil { detected = result.language } }
            parts.append(result.text)
            return parts
        }
    }

    private static func decibels(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return -160 }
        let power = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
        return 10 * log10(max(power, 1e-16))
    }

    /// Louder than this is speech: 8 dB over the quietest tenth of what the
    /// mic has heard (the room), kept between -75 and -35 dB. A fixed line
    /// either cuts a quiet voice into "silence" or hears a noisy room as speech.
    private func speechLevel() -> Float {
        let heard = levels.filter { $0 > -100 }      // digital silence isn't the room
        guard heard.count >= 5 else { return -50 }
        let floor = heard.sorted()[heard.count / 10]
        return min(max(floor + 8, -75), -35)
    }

    /// At least 0.2 s above the speech level. Whisper makes up words
    /// ("Terima kasih.", "Thank you.") for a stretch of room noise.
    private func hasSpeech(_ samples: [Float]) -> Bool {
        let level = speechLevel()
        let loud = stride(from: 0, to: max(0, samples.count - Self.frame + 1), by: Self.frame).filter { start in
            Self.decibels(Array(samples[start..<start + Self.frame])) > level
        }
        return loud.count >= 2
    }
}
