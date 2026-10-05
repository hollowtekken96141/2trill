import Accelerate
import Foundation

/// Turns raw audio into an onset envelope using log-magnitude spectral flux:
/// for each ~11 ms step, how much louder each frequency got compared with the step before.
/// Drum hits and note starts show up as peaks.
enum OnsetDetector {
    static func envelope(samples: [Float], sampleRate: Double) -> OnsetEnvelope {
        let n = sampleRate > 32_000 ? 2048 : 1024
        let hop = n / 4
        let half = n / 2
        let log2n = vDSP_Length(log2(Double(n)))
        let rate = sampleRate / Double(hop)
        let empty = OnsetEnvelope(values: [], low: [], rate: rate, timeOffset: 0)

        guard samples.count >= n,
              let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return empty }
        defer { vDSP_destroy_fftsetup(setup) }

        // Kick drum range: everything under ~150 Hz.
        let lowBins = max(2, min(half, Int(150 / (sampleRate / Double(n))) + 1))

        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        var frame = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        var scaled = [Float](repeating: 0, count: half)
        var logMags = [Float](repeating: 0, count: half)
        var previous = [Float](repeating: 0, count: half)
        var diff = [Float](repeating: 0, count: half)
        var rising = [Float](repeating: 0, count: half)
        var gain: Float = 100 / Float(n)
        var zero: Float = 0
        var halfCount = Int32(half)

        let frameCount = (samples.count - n) / hop + 1
        var flux = [Float](repeating: 0, count: frameCount)
        var lowFlux = [Float](repeating: 0, count: frameCount)

        samples.withUnsafeBufferPointer { input in
            for f in 0..<frameCount {
                vDSP_vmul(input.baseAddress! + f * hop, 1, window, 1, &frame, 1, vDSP_Length(n))

                real.withUnsafeMutableBufferPointer { rp in
                    imag.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        frame.withUnsafeBufferPointer { fp in
                            fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                                vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        ip[0] = 0 // Nyquist is packed here; drop it.
                        vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
                    }
                }

                // log(1 + gain * |X|) compresses loudness so quiet hi-hats still count.
                vDSP_vsmul(mags, 1, &gain, &scaled, 1, vDSP_Length(half))
                vvlog1pf(&logMags, scaled, &halfCount)

                if f > 0 {
                    vDSP_vsub(previous, 1, logMags, 1, &diff, 1, vDSP_Length(half)) // diff = log - previous
                    vDSP_vthr(diff, 1, &zero, &rising, 1, vDSP_Length(half))        // keep increases only
                    var total: Float = 0
                    var low: Float = 0
                    vDSP_sve(rising, 1, &total, vDSP_Length(half))
                    vDSP_sve(rising, 1, &low, vDSP_Length(lowBins))
                    flux[f] = total
                    lowFlux[f] = low
                }
                swap(&previous, &logMags)
            }
        }

        return OnsetEnvelope(
            values: normalize(detrend(flux, radius: 8)),
            low: normalize(detrend(lowFlux, radius: 8)),
            rate: rate,
            timeOffset: Double(half) / sampleRate
        )
    }

    /// Subtracts a moving average and clips at zero, leaving just the peaks.
    private static func detrend(_ v: [Float], radius: Int) -> [Float] {
        let avg = TempoEstimator.smoothed(v, radius: radius)
        return zip(v, avg).map { max(0, $0 - $1) }
    }

    /// Scales so the 99th percentile is 1.
    private static func normalize(_ v: [Float]) -> [Float] {
        guard !v.isEmpty else { return v }
        let sorted = v.sorted()
        let ref = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.99))]
        guard ref > 0 else { return v }
        return v.map { min(1.5, $0 / ref) }
    }
}
