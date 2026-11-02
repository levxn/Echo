import Accelerate
import Foundation

/// Spectral features of speech, frame by frame: MFCCs and a pitch estimate. Plain Swift (a small FFT, no frameworks).
nonisolated enum MFCC {
    struct Frame {
        let mfcc: [Float]      // coefficients 1...12
        let pitch: Float?      // Hz, when the frame is clearly voiced
    }

    static let frameLength = 400      // 25 ms at 16 kHz
    static let hop = 160              // 10 ms
    static let fftSize = 512
    static let melBands = 26

    // MARK: Precomputed tables

    private static let window: [Float] = (0..<frameLength).map { 0.54 - 0.46 * cos(2 * .pi * Float($0) / Float(frameLength - 1)) }

    private static let melFilters: [[(bin: Int, weight: Float)]] = {
        func mel(_ hz: Float) -> Float { 2595 * log10(1 + hz / 700) }
        func hz(_ mel: Float) -> Float { 700 * (pow(10, mel / 2595) - 1) }
        let low = mel(100), high = mel(7_000)
        let points = (0..<(melBands + 2)).map { hz(low + (high - low) * Float($0) / Float(melBands + 1)) }
        let binHz = Float(VoicePrint.rate) / Float(fftSize)
        return (0..<melBands).map { m in
            let lo = points[m], mid = points[m + 1], hi = points[m + 2]
            var out: [(Int, Float)] = []
            for bin in 0...(fftSize / 2) {
                let f = Float(bin) * binHz
                if f > lo && f < mid { out.append((bin, (f - lo) / (mid - lo))) }
                else if f >= mid && f < hi { out.append((bin, (hi - f) / (hi - mid))) }
            }
            return out
        }
    }()

    private static let dct: [[Float]] = (1...VoicePrint.coefficients).map { k in
        (0..<melBands).map { m in cos(.pi * Float(k) * (Float(m) + 0.5) / Float(melBands)) }
    }

    // MARK: Frames

    /// The voiced frames of `samples` (16 kHz mono). Quiet frames (gaps, breaths, noise) are left out.
    static func frames(_ samples: [Int16]) -> [Frame] {
        guard samples.count >= frameLength else { return [] }
        var x = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count { x[i] = Float(samples[i]) / 32768 }

        struct Raw { let db: Float; let mfcc: [Float]; let pitch: Float? }
        var raw: [Raw] = []
        var start = 0
        while start + frameLength <= x.count {
            let frame = Array(x[start..<start + frameLength])
            // pre-emphasis lifts the high frequencies, where voices differ most
            var emphasized = frame
            for i in stride(from: frameLength - 1, to: 0, by: -1) { emphasized[i] = frame[i] - 0.97 * frame[i - 1] }
            var re = [Float](repeating: 0, count: fftSize), im = [Float](repeating: 0, count: fftSize)
            for i in 0..<frameLength { re[i] = emphasized[i] * window[i] }
            fft(&re, &im)
            var power = [Float](repeating: 0, count: fftSize / 2 + 1)
            var total: Float = 0
            for k in 0...(fftSize / 2) { power[k] = (re[k] * re[k] + im[k] * im[k]) / Float(fftSize); total += power[k] }
            let db = 10 * log10(total + 1e-12)
            let logMel = melFilters.map { filter -> Float in
                var e: Float = 0
                for (bin, w) in filter { e += w * power[bin] }
                return log(max(e, 1e-10))
            }
            let coefficients = dct.map { row -> Float in zip(row, logMel).reduce(0) { $0 + $1.0 * $1.1 } }
            raw.append(Raw(db: db, mfcc: coefficients, pitch: pitchOf(frame)))
            start += hop
        }
        guard let loudest = raw.map(\.db).max() else { return [] }
        return raw.filter { $0.db >= loudest - 30 && $0.db > -70 }.map { Frame(mfcc: $0.mfcc, pitch: $0.pitch) }
    }

    // MARK: Pitch

    /// Fundamental frequency by autocorrelation, 70...400 Hz; nil when the frame isn't clearly voiced.
    private static func pitchOf(_ frame: [Float]) -> Float? {
        let minLag = VoicePrint.rate / 400, maxLag = min(frame.count - 1, VoicePrint.rate / 70)
        var r0: Float = 0
        for v in frame { r0 += v * v }
        guard r0 > 1e-6 else { return nil }
        var best: Float = 0, bestLag = 0
        frame.withUnsafeBufferPointer { p in
            guard let base = p.baseAddress else { return }
            for lag in minLag...maxLag {
                var r: Float = 0
                vDSP_dotpr(base, 1, base + lag, 1, &r, vDSP_Length(frame.count - lag))
                if r > best { best = r; bestLag = lag }
            }
        }
        guard bestLag > 0, best / r0 > 0.4 else { return nil }
        return Float(VoicePrint.rate) / Float(bestLag)
    }

    // MARK: FFT

    private static let fftSetup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2))!   // 2^9 = 512

    /// In-place complex FFT of length 512 (Accelerate).
    private static func fft(_ re: inout [Float], _ im: inout [Float]) {
        re.withUnsafeMutableBufferPointer { rp in
            im.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                vDSP_fft_zip(fftSetup, &split, 1, 9, FFTDirection(kFFTDirection_Forward))
            }
        }
    }
}
