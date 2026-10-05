import Foundation

/// A "how much is happening right now" curve for a song, sampled at `rate` frames per second.
/// `values` is full-band spectral flux; `low` is flux from the kick-drum range only.
struct OnsetEnvelope: Codable {
    var values: [Float]
    var low: [Float]
    var rate: Double
    /// Song time of frame 0.
    var timeOffset: Double

    var count: Int { values.count }
    var duration: Double { Double(count) / rate }

    func time(ofFrame frame: Double) -> Double { timeOffset + frame / rate }
    func frame(at time: Double) -> Double { (time - timeOffset) * rate }

    /// Average of `values` over a song-time window.
    func mean(from start: Double, to end: Double) -> Float {
        let lo = max(0, Int(frame(at: start)))
        let hi = min(count, Int(frame(at: end).rounded(.up)))
        guard hi > lo else { return 0 }
        var sum: Float = 0
        for i in lo..<hi { sum += values[i] }
        return sum / Float(hi - lo)
    }
}
