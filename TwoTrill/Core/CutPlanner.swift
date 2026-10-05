import Foundation

/// How busy the auto edit should feel.
enum CutStyle: String, Codable, CaseIterable, Identifiable {
    case chill, balanced, hype

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chill: "Chill"
        case .balanced: "Balanced"
        case .hype: "Hype"
        }
    }

    /// Candidate shot lengths, in half-beats, with their base odds.
    var lengthWeights: [(halfBeats: Int, weight: Double)] {
        switch self {
        case .chill: [(2, 0.10), (4, 0.30), (8, 0.40), (16, 0.20)]
        case .balanced: [(1, 0.04), (2, 0.22), (4, 0.38), (8, 0.28), (16, 0.08)]
        case .hype: [(1, 0.14), (2, 0.36), (4, 0.32), (8, 0.18)]
        }
    }

    /// Odds of a burst of rapid-fire cuts when the music is busy.
    var stutterChance: Double {
        switch self {
        case .chill: 0
        case .balanced: 0.06
        case .hype: 0.14
        }
    }

    /// Odds of a zoomed "punch-in" shot when a loud bar starts.
    var punchChance: Double {
        switch self {
        case .chill: 0
        case .balanced: 0.15
        case .hype: 0.35
        }
    }
}

/// The part of the song clip a take can supply footage for, in clip time (0 = clip start).
struct TakeCoverage: Hashable {
    var id: UUID
    var start: Double
    var end: Double
}

struct EditSegment: Hashable {
    var start: Double
    var end: Double
    var takeID: UUID
    var zoom: Double = 1

    var duration: Double { end - start }
}

struct EditPlan: Hashable {
    var segments: [EditSegment]
    var duration: Double
}

/// Decides where to cut and which take to show for each shot.
///
/// Every take was filmed against the same song, so any take can be shown at any moment and
/// the lip-sync still lines up. The planner walks the clip on a half-beat grid and picks a shot
/// length for each cut: mostly 1–4 beats, shorter when the music is busy, longer when it's
/// calm, with longer shots landing on strong beats (beats 1 and 3, ideally the bar start).
/// Occasional stutter bursts and zoom punch-ins give it the Triller feel. The same seed always
/// gives the same edit; "Remix" just picks a new seed.
struct CutPlanner {
    var grid: BeatGrid
    var clipStart: Double
    var clipLength: Double
    var envelope: OnsetEnvelope?
    var style: CutStyle

    func plan(takes: [TakeCoverage], seed: UInt64) -> EditPlan {
        guard !takes.isEmpty, clipLength > 0, grid.bpm > 0 else {
            return EditPlan(segments: [], duration: max(0, clipLength))
        }
        var rng = SplitMix64(seed: seed)
        let half = grid.period / 2
        let intensity = IntensityMap(envelope: envelope, grid: grid, clipStart: clipStart, clipLength: clipLength)
        let minTail = max(grid.period, 0.35)

        // Half-beat index of the grid point at (or just before) the clip start.
        var cursorH = Int(((clipStart - grid.firstBeat) / half + 1e-6).rounded(.down))
        var segmentStart = 0.0
        var segments: [EditSegment] = []
        var uses: [UUID: Int] = [:]
        var previous: UUID?
        var stutterLeft = 0
        var stutterUnit = 1

        while segmentStart < clipLength - 1e-6 {
            let level = intensity.level(atClipTime: segmentStart)

            var length: Int
            var aligned = true
            if stutterLeft > 0 {
                stutterLeft -= 1
                length = stutterUnit
                aligned = false
            } else if rng.chance(style.stutterChance * (level > 0.6 ? 1 : 0.25)) {
                stutterUnit = style == .hype ? 1 : 2
                stutterLeft = Int.random(in: 2...3, using: &rng)
                length = stutterUnit
                aligned = false
            } else {
                length = pickLength(level: level, rng: &rng)
            }
            // Keep shots watchable at extreme tempos.
            while Double(length) * half < 0.2 { length *= 2 }
            while length > 1, Double(length) * half > 6 { length /= 2 }

            var endH = cursorH + length
            if aligned { endH = align(endH, length: length) }
            var end = grid.firstBeat + Double(endH) * half - clipStart
            if end < segmentStart + 0.1 {
                // Clip start sits between grid points; skip ahead so the first shot isn't a sliver.
                endH += max(length, 2)
                end = grid.firstBeat + Double(endH) * half - clipStart
            }
            if end > clipLength - minTail {
                end = clipLength
                stutterLeft = 0
            }

            let take = chooseTake(from: takes, start: segmentStart, end: end,
                                  previous: previous, uses: uses, rng: &rng)
            var zoom = 1.0
            if strength(cursorH) == 3, level > 0.55, segments.last?.zoom ?? 1 == 1,
               rng.chance(style.punchChance) {
                zoom = 1.18
            }

            segments.append(EditSegment(start: segmentStart, end: end, takeID: take, zoom: zoom))
            uses[take, default: 0] += 1
            previous = take
            segmentStart = end
            cursorH = endH
        }
        return EditPlan(segments: merged(segments), duration: clipLength)
    }

    // MARK: - Shot length

    private func pickLength(level: Double, rng: inout SplitMix64) -> Int {
        let options = style.lengthWeights
        // Busy music favors short shots, calm music long ones. Two beats (4 half-beats) is neutral.
        let weights = options.map { option in
            option.weight * pow(2, -1.3 * (level - 0.5) * log2(Double(option.halfBeats) / 4))
        }
        return options[rng.weightedIndex(weights)].halfBeats
    }

    /// 0 = off-beat, 1 = beat, 2 = beat 1 or 3 of the bar, 3 = bar start.
    func strength(_ h: Int) -> Int {
        guard positiveModulo(h, 2) == 0 else { return 0 }
        let beat = h / 2
        if grid.isDownbeat(beat) { return 3 }
        if positiveModulo(beat - grid.downbeatIndex, 2) == 0 { return 2 }
        return 1
    }

    /// Nudges a cut later so longer shots end on stronger beats.
    private func align(_ h: Int, length: Int) -> Int {
        let required: Int
        switch length {
        case ..<2: return h
        case 2..<4: required = 1
        case 4..<8: required = 2
        default: required = 3
        }
        let reach = required == 3 ? 4 : 3
        if let shift = (0...reach).first(where: { strength(h + $0) >= required }) { return h + shift }
        if let shift = (0...3).first(where: { strength(h + $0) >= min(required, 2) }) { return h + shift }
        return h
    }

    // MARK: - Take choice

    private func chooseTake(from takes: [TakeCoverage], start: Double, end: Double,
                            previous: UUID?, uses: [UUID: Int], rng: inout SplitMix64) -> UUID {
        let tolerance = 0.05
        var candidates = takes.filter { $0.start <= start + tolerance && $0.end >= end - tolerance }
        if candidates.isEmpty {
            // Nobody covers the whole shot; use whoever covers the most of it.
            func overlap(_ t: TakeCoverage) -> Double { min(t.end, end) - max(t.start, start) }
            return takes.max { overlap($0) < overlap($1) }!.id
        }
        if candidates.count > 1, let previous {
            candidates.removeAll { $0.id == previous }
        }
        // Spread screen time across takes, but keep it random.
        let weights = candidates.map { 1 / pow(1 + Double(uses[$0.id, default: 0]), 1.5) }
        return candidates[rng.weightedIndex(weights)].id
    }

    private func merged(_ segments: [EditSegment]) -> [EditSegment] {
        var result: [EditSegment] = []
        for segment in segments {
            if let last = result.last, last.takeID == segment.takeID, last.zoom == segment.zoom {
                result[result.count - 1].end = segment.end
            } else {
                result.append(segment)
            }
        }
        return result
    }
}

/// How busy the music is around a point in the clip, from 0 (calmest bar) to 1 (busiest),
/// ranked relative to the rest of the clip.
struct IntensityMap {
    private var levels: [Double] = []
    private var step: Double = 1

    init(envelope: OnsetEnvelope?, grid: BeatGrid, clipStart: Double, clipLength: Double) {
        guard let envelope, grid.period > 0 else { return }
        step = grid.period
        var raw: [Double] = []
        var t = 0.0
        while t < clipLength {
            raw.append(Double(envelope.mean(from: clipStart + t, to: clipStart + t + grid.barLength)))
            t += step
        }
        guard raw.count > 1 else { return }
        let sorted = raw.sorted()
        levels = raw.map { value in
            let rank = sorted.firstIndex { $0 >= value } ?? 0
            return Double(rank) / Double(sorted.count - 1)
        }
    }

    func level(atClipTime t: Double) -> Double {
        guard !levels.isEmpty else { return 0.5 }
        let i = min(levels.count - 1, max(0, Int(t / step)))
        return levels[i]
    }
}
