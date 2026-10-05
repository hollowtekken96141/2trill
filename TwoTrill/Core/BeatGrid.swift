import Foundation

/// A constant-tempo beat grid for a song, in song time (seconds).
struct BeatGrid: Codable, Hashable {
    var bpm: Double
    /// Time of the first beat at or after 0 s. Beat `k` is at `firstBeat + k * period`.
    var firstBeat: Double
    /// Which beat index (mod `beatsPerBar`) starts a bar.
    var downbeatIndex: Int
    var beatsPerBar: Int = 4

    var period: Double { 60.0 / bpm }
    var barLength: Double { period * Double(beatsPerBar) }

    func time(ofBeat index: Int) -> Double {
        firstBeat + Double(index) * period
    }

    func isDownbeat(_ index: Int) -> Bool {
        positiveModulo(index - downbeatIndex, beatsPerBar) == 0
    }

    /// The bar start closest to `t`, never earlier than 0.
    func nearestDownbeat(to t: Double) -> Double {
        let first = time(ofBeat: downbeatIndex)
        var result = first + ((t - first) / barLength).rounded() * barLength
        while result < 0 { result += barLength }
        return result
    }
}

@inline(__always)
func positiveModulo(_ a: Int, _ n: Int) -> Int {
    let r = a % n
    return r < 0 ? r + n : r
}
