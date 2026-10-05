import Foundation

/// Small deterministic RNG so the same seed always produces the same edit.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension RandomNumberGenerator {
    mutating func chance(_ probability: Double) -> Bool {
        probability > 0 && Double.random(in: 0..<1, using: &self) < probability
    }

    /// Index picked with probability proportional to its weight.
    mutating func weightedIndex(_ weights: [Double]) -> Int {
        precondition(!weights.isEmpty)
        let total = weights.reduce(0, +)
        guard total > 0 else { return Int.random(in: 0..<weights.count, using: &self) }
        var r = Double.random(in: 0..<total, using: &self)
        for (i, w) in weights.enumerated() {
            if r < w { return i }
            r -= w
        }
        return weights.count - 1
    }
}
