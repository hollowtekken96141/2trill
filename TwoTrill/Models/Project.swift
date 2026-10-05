import Foundation

struct Song: Codable, Hashable {
    var fileName: String
    var title: String
    var artist: String?
    var duration: Double
    var grid: BeatGrid?
}

struct Take: Identifiable, Codable, Hashable {
    enum Source: String, Codable {
        case camera, imported
    }

    var id = UUID()
    var fileName: String
    var createdAt = Date()
    /// Seconds into the video file at which the start of the song clip is heard.
    var syncOffset: Double
    var duration: Double
    var isEnabled = true
    var source: Source = .camera
    /// How fast the song played while filming. 2 = half-speed take: the song ran at 2x, so the
    /// footage gets stretched to twice its length in the edit (slow motion, still in sync).
    var songRate: Double = 1

    /// Video time (seconds into the file) showing the given clip time.
    func videoTime(atClipTime clipTime: Double) -> Double {
        syncOffset + clipTime / songRate
    }

    /// The part of the song clip this take has footage for, in clip time.
    var coverage: TakeCoverage {
        TakeCoverage(id: id, start: -syncOffset * songRate, end: (duration - syncOffset) * songRate)
    }
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var song: Song?
    /// Start of the song section the video is cut to, in song seconds.
    var clipStart: Double = 0
    var clipLength: Double = 30
    var takes: [Take] = []
    var style: CutStyle = .balanced
    var seed: UInt64 = 1

    /// Clip length, trimmed if the song ends sooner.
    var effectiveClipLength: Double {
        guard let song else { return clipLength }
        return max(0, min(clipLength, song.duration - clipStart))
    }

    var enabledTakes: [Take] { takes.filter(\.isEnabled) }
}

extension Project {
    /// Keeps the clip inside the song and moves its start to the nearest bar line.
    mutating func snapClipStart() {
        guard let song else { return }
        let latest = max(0, song.duration - min(clipLength, song.duration))
        var start = min(clipStart, latest)
        if let grid = song.grid {
            start = grid.nearestDownbeat(to: start)
            while start > latest, start - grid.barLength >= 0 { start -= grid.barLength }
        }
        clipStart = min(max(0, start), latest)
    }
}
