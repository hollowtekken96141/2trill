import AVFoundation

enum SongAnalyzer {
    struct Analysis {
        var envelope: OnsetEnvelope
        var waveform: Waveform
        var grid: BeatGrid?
    }

    struct Metadata {
        var title: String?
        var artist: String?
        var duration: Double
    }

    /// Decodes the song and detects its tempo. Runs off the main thread.
    static func analyze(url: URL) async throws -> Analysis {
        try await Task.detached(priority: .userInitiated) {
            let audio = try AudioDecoder.decodeMono(url: url)
            let envelope = OnsetDetector.envelope(samples: audio.samples, sampleRate: audio.sampleRate)
            let waveform = Waveform(samples: audio.samples, sampleRate: audio.sampleRate)
            return Analysis(envelope: envelope, waveform: waveform, grid: TempoEstimator.estimateGrid(envelope))
        }.value
    }

    static func metadata(url: URL) async -> Metadata {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        let items = (try? await asset.load(.commonMetadata)) ?? []
        func string(_ id: AVMetadataIdentifier) async -> String? {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first else { return nil }
            let value = try? await item.load(.stringValue)
            return value?.isEmpty == false ? value : nil
        }
        return Metadata(
            title: await string(.commonIdentifierTitle),
            artist: await string(.commonIdentifierArtist),
            duration: duration.isFinite ? duration : 0
        )
    }

    /// Picks the busiest stretch of the song (usually the hook) as the default clip,
    /// starting on a bar line.
    static func suggestedClipStart(envelope: OnsetEnvelope, grid: BeatGrid, length: Double, songDuration: Double) -> Double {
        let latest = max(0, songDuration - length)
        var best = (start: 0.0, score: -Float.infinity)
        var t = grid.time(ofBeat: grid.downbeatIndex)
        while t <= latest {
            if t >= 0 {
                let score = envelope.mean(from: t, to: t + length)
                if score > best.score { best = (t, score) }
            }
            t += grid.barLength
        }
        return best.start
    }
}
