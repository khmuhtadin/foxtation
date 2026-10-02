import Foundation

/// Minimal 16-bit PCM mono WAV writer — whisper.cpp wants plain RIFF/WAVE.
enum WavWriter {

    static func write(samples: [Float], sampleRate: Double, to url: URL) throws {
        let rate = Int(sampleRate.rounded())
        let byteRate = rate * 2
        let dataSize = samples.count * 2

        var out = Data(capacity: 44 + dataSize)
        func ascii(_ s: String) { out.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }

        ascii("RIFF"); u32(UInt32(36 + dataSize)); ascii("WAVE")
        ascii("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(byteRate)); u16(2); u16(16)
        ascii("data"); u32(UInt32(dataSize))

        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices {
            let clamped = max(-1.0, min(1.0, samples[i]))
            pcm[i] = Int16((clamped * 32767.0).rounded())
        }
        pcm.withUnsafeBufferPointer { out.append(Data(buffer: $0)) }

        try out.write(to: url, options: .atomic)
    }
}
