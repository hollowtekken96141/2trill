import AVFoundation

enum AudioDecoder {
    struct Output {
        var samples: [Float]
        var sampleRate: Double
    }

    /// Decodes any file AVFoundation can read (mp3, m4a, wav, …) to mono floats,
    /// downsampled to at most ~24 kHz, which is plenty for beat tracking.
    static func decodeMono(url: URL, maxSampleRate: Double = 24_000) throws -> Output {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        let decimation = max(1, Int((format.sampleRate / maxSampleRate).rounded(.up)))
        let chunk: AVAudioFrameCount = 65_536
        guard channels > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var out: [Float] = []
        out.reserveCapacity(Int(file.length) / decimation + 1)
        var acc: Float = 0
        var accCount = 0
        let scale = 1 / Float(channels * decimation)

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            let n = Int(buffer.frameLength)
            guard n > 0, let data = buffer.floatChannelData else { break }
            for i in 0..<n {
                for c in 0..<channels { acc += data[c][i] }
                accCount += 1
                if accCount == decimation {
                    out.append(acc * scale)
                    acc = 0
                    accCount = 0
                }
            }
        }
        return Output(samples: out, sampleRate: format.sampleRate / Double(decimation))
    }
}
