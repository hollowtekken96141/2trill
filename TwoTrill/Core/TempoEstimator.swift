import Foundation

/// Finds BPM, beat phase and bar starts from an onset envelope.
///
/// 1. Autocorrelate the envelope to find the strongest periodicity between 60 and 200 BPM,
///    weighted toward ~120 BPM so we don't lock onto half or double time.
/// 2. Fine-tune tempo and phase together by sliding a beat "comb" over the envelope and
///    keeping the one that lands on the most energy.
/// 3. Pick the bar start as the beat (of every 4) with the most kick-drum energy.
enum TempoEstimator {
    static func estimateGrid(_ env: OnsetEnvelope, minBPM: Double = 60, maxBPM: Double = 200) -> BeatGrid? {
        guard env.count > Int(env.rate * 4), let coarse = coarseTempo(env, minBPM: minBPM, maxBPM: maxBPM) else {
            return nil
        }
        let smooth = phaseSignal(env)

        var best = (bpm: coarse, phase: 0.0, score: -Double.infinity)
        var bpm = coarse * 0.97
        while bpm <= coarse * 1.03 {
            let fit = bestPhase(smooth, rate: env.rate, bpm: bpm)
            if fit.score > best.score { best = (bpm, fit.phase, fit.score) }
            bpm += 0.05
        }

        // Most produced music sits on a whole-number tempo; snap when we're close.
        var finalBPM = best.bpm
        var phase = best.phase
        let rounded = finalBPM.rounded()
        if abs(finalBPM - rounded) <= 0.15 {
            finalBPM = rounded
            phase = bestPhase(smooth, rate: env.rate, bpm: finalBPM).phase
        }
        return makeGrid(env, bpm: finalBPM, phaseFrame: phase)
    }

    /// Keeps a user-chosen tempo and re-fits only the beat phase and bar start.
    static func fitGrid(_ env: OnsetEnvelope, bpm: Double) -> BeatGrid {
        let smooth = phaseSignal(env)
        let phase = bestPhase(smooth, rate: env.rate, bpm: bpm).phase
        return makeGrid(env, bpm: bpm, phaseFrame: phase)
    }

    /// What the beat comb is matched against: all onsets plus the kick-drum range again, so the
    /// beats land on kicks and snares rather than on off-beat hi-hats, which are broadband and
    /// would otherwise score just as high.
    static func phaseSignal(_ env: OnsetEnvelope) -> [Float] {
        let all = smoothed(env.values, radius: 2)
        guard env.low.count == env.values.count else { return all }
        let low = smoothed(env.low, radius: 2)
        return zip(all, low).map { $0 + $1 }
    }

    static func coarseTempo(_ env: OnsetEnvelope, minBPM: Double, maxBPM: Double) -> Double? {
        let count = env.count
        let mean = env.values.reduce(0, +) / Float(max(count, 1))
        let x = env.values.map { Double($0 - mean) }

        let minLag = max(1, Int((env.rate * 60 / maxBPM).rounded(.down)))
        let maxLag = Int((env.rate * 60 / minBPM).rounded(.up))
        let acLimit = min(2 * maxLag + 2, count - 1)
        guard acLimit > maxLag + 1 else { return nil }

        var ac = [Double](repeating: 0, count: acLimit + 1)
        x.withUnsafeBufferPointer { p in
            for lag in minLag...acLimit {
                let n = count - lag
                var s = 0.0
                for i in 0..<n { s += p[i] * p[i + lag] }
                ac[lag] = s / Double(n)
            }
        }

        func score(_ lag: Int) -> Double {
            let bpm = 60 * env.rate / Double(lag)
            let octaves = log2(bpm / 120) / 0.9
            let prior = exp(-0.5 * octaves * octaves)
            let harmonic = 2 * lag <= acLimit ? ac[2 * lag] : 0
            return (ac[lag] + 0.5 * harmonic) * prior
        }

        var bestLag = minLag
        var bestScore = -Double.infinity
        for lag in minLag...maxLag {
            let s = score(lag)
            if s > bestScore { bestScore = s; bestLag = lag }
        }

        // Parabolic interpolation for a sub-frame period.
        var lag = Double(bestLag)
        if bestLag > minLag && bestLag < maxLag {
            let a = score(bestLag - 1), b = bestScore, c = score(bestLag + 1)
            let denom = a - 2 * b + c
            if denom < 0 { lag += 0.5 * (a - c) / denom }
        }
        return 60 * env.rate / lag
    }

    /// Slides a beat comb with the given tempo across the envelope; returns the offset
    /// (in frames) where the comb collects the most onset energy on average.
    static func bestPhase(_ v: [Float], rate: Double, bpm: Double) -> (phase: Double, score: Double) {
        let period = rate * 60 / bpm
        let last = Double(v.count - 1)
        var best = (phase: 0.0, score: -Double.infinity)
        v.withUnsafeBufferPointer { p in
            var phase = 0.0
            while phase < period {
                var sum = 0.0
                var n = 0
                var f = phase
                while f < last {
                    let i = Int(f)
                    let frac = Float(f - Double(i))
                    sum += Double(p[i] * (1 - frac) + p[i + 1] * frac)
                    n += 1
                    f += period
                }
                if n > 0, sum / Double(n) > best.score { best = (phase, sum / Double(n)) }
                phase += 0.5
            }
        }
        return best
    }

    static func makeGrid(_ env: OnsetEnvelope, bpm: Double, phaseFrame: Double) -> BeatGrid {
        let period = 60 / bpm
        let t0 = env.time(ofFrame: phaseFrame)
        let first = t0 - (t0 / period).rounded(.down) * period

        // Bar start = the beat position (out of 4) that carries the most low-end energy.
        let source = env.low.count == env.count ? env.low : env.values
        var sums = [Double](repeating: 0, count: 4)
        var k = 0
        while true {
            let f = Int(env.frame(at: first + Double(k) * period).rounded())
            if f >= source.count { break }
            if f >= 0 {
                let window = max(0, f - 2)...min(source.count - 1, f + 2)
                sums[k % 4] += Double(source[window].max() ?? 0)
            }
            k += 1
        }
        let down = sums.indices.max { sums[$0] < sums[$1] } ?? 0
        return BeatGrid(bpm: bpm, firstBeat: first, downbeatIndex: down)
    }

    static func smoothed(_ v: [Float], radius: Int) -> [Float] {
        guard radius > 0, v.count > 1 else { return v }
        var prefix = [Float](repeating: 0, count: v.count + 1)
        for i in 0..<v.count { prefix[i + 1] = prefix[i] + v[i] }
        return (0..<v.count).map { i in
            let lo = max(0, i - radius), hi = min(v.count, i + radius + 1)
            return (prefix[hi] - prefix[lo]) / Float(hi - lo)
        }
    }
}
