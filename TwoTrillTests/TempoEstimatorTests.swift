import XCTest
@testable import TwoTrill

final class TempoEstimatorTests: XCTestCase {
    /// A fake envelope with a spike on every beat and a bigger low-end spike on every bar start.
    private func clickEnvelope(bpm: Double, firstBeat: Double, duration: Double = 60, rate: Double = 86) -> OnsetEnvelope {
        let count = Int(duration * rate)
        var values = [Float](repeating: 0, count: count)
        var low = [Float](repeating: 0, count: count)
        var k = 0
        while true {
            let t = firstBeat + Double(k) * 60 / bpm
            let f = Int((t * rate).rounded())
            if f >= count { break }
            values[f] = 1
            if f + 1 < count { values[f + 1] = 0.5 }
            if k % 4 == 0 { low[f] = 1 }
            // Off-beat hi-hat.
            let h = Int(((t + 30 / bpm) * rate).rounded())
            if h < count { values[h] = max(values[h], 0.3) }
            k += 1
        }
        return OnsetEnvelope(values: values, low: low, rate: rate, timeOffset: 0)
    }

    func testFindsTempoAndPhase() throws {
        for (bpm, first) in [(100.0, 0.25), (128.0, 0.1), (92.0, 0.4), (140.0, 0.05)] {
            let grid = try XCTUnwrap(TempoEstimator.estimateGrid(clickEnvelope(bpm: bpm, firstBeat: first)))
            XCTAssertEqual(grid.bpm, bpm, accuracy: 0.5, "tempo for \(bpm)")
            XCTAssertEqual(grid.firstBeat, first, accuracy: 0.03, "phase for \(bpm)")
            XCTAssertEqual(grid.downbeatIndex, 0, "bar start for \(bpm)")
        }
    }

    func testFitGridKeepsRequestedTempo() {
        let env = clickEnvelope(bpm: 100, firstBeat: 0.25)
        let grid = TempoEstimator.fitGrid(env, bpm: 50)
        XCTAssertEqual(grid.bpm, 50)
        XCTAssertEqual(grid.firstBeat.truncatingRemainder(dividingBy: 0.6), 0.25, accuracy: 0.03)
    }

    func testDetectsBeatInRealAudio() throws {
        // Synthesized kick + hi-hat loop at 120 BPM, first kick at 0.3 s.
        let sampleRate = 22_050.0
        var samples = [Float](repeating: 0, count: Int(sampleRate * 30))
        let period = 0.5
        var t = 0.3
        var beat = 0
        while t < 29.5 {
            let start = Int(t * sampleRate)
            for i in 0..<Int(0.15 * sampleRate) where start + i < samples.count {
                let x = Double(i) / sampleRate
                let kick = sin(2 * .pi * (55 + 90 * exp(-x * 30)) * x) * exp(-x * 14)
                samples[start + i] += Float(beat % 2 == 0 ? kick : kick * 0.4)
            }
            let hat = Int((t + period / 2) * sampleRate)
            for i in 0..<Int(0.03 * sampleRate) where hat + i < samples.count {
                samples[hat + i] += Float.random(in: -0.2...0.2) * Float(exp(-Double(i) / sampleRate * 120))
            }
            t += period
            beat += 1
        }
        let env = OnsetDetector.envelope(samples: samples, sampleRate: sampleRate)
        let grid = try XCTUnwrap(TempoEstimator.estimateGrid(env))
        XCTAssertEqual(grid.bpm, 120, accuracy: 1)
        XCTAssertEqual(grid.firstBeat, 0.3, accuracy: 0.04)
    }
}
