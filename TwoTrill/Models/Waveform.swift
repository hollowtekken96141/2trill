import Foundation

/// Peak loudness of the song, `rate` values per second, scaled so the loudest is 1.
struct Waveform: Codable {
    var peaks: [Float]
    var rate: Double

    var duration: Double { Double(peaks.count) / rate }

    init(peaks: [Float], rate: Double) {
        self.peaks = peaks
        self.rate = rate
    }

    init(samples: [Float], sampleRate: Double, rate: Double = 50) {
        let size = max(1, Int(sampleRate / rate))
        var peaks: [Float] = []
        peaks.reserveCapacity(samples.count / size + 1)
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + size)
            var peak: Float = 0
            for j in i..<end { peak = max(peak, abs(samples[j])) }
            peaks.append(peak)
            i = end
        }
        let loudest = peaks.max() ?? 0
        self.peaks = loudest > 0 ? peaks.map { $0 / loudest } : peaks
        self.rate = Double(sampleRate) / Double(size)
    }

    /// `count` bars covering song time `start..<end`, each the loudest peak in its slice.
    func bars(count: Int, from start: Double, to end: Double) -> [Float] {
        guard count > 0, end > start, !peaks.isEmpty else { return [] }
        let step = (end - start) / Double(count)
        return (0..<count).map { k in
            let lo = max(0, Int((start + Double(k) * step) * rate))
            let hi = min(peaks.count, max(lo + 1, Int((start + Double(k + 1) * step) * rate)))
            guard lo < hi else { return 0 }
            return peaks[lo..<hi].max() ?? 0
        }
    }
}
