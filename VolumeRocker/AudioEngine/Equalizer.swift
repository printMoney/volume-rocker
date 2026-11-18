import Foundation

/// The 10-band graphic equalizer: band layout, presets and filter math.
enum Equalizer {
    /// ISO octave band centers, in Hz.
    static let frequencies: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let bandCount = frequencies.count
    static let gainRange: ClosedRange<Float> = -12 ... 12
    /// About one octave wide, so neighboring bands blend smoothly.
    static let bandwidthQ = 1.41

    static let flat = [Float](repeating: 0, count: bandCount)

    static func isFlat(_ gains: [Float]?) -> Bool {
        guard let gains else { return true }
        return gains.allSatisfy { abs($0) < 0.05 }
    }

    /// Short label for a band, e.g. "125" or "2k".
    static func label(for frequency: Double) -> String {
        frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))"
    }

    // MARK: Presets

    struct Preset: Identifiable, Equatable, Sendable {
        let id: String
        let name: LocalizedStringResource
        let gains: [Float]

        static func == (lhs: Preset, rhs: Preset) -> Bool {
            lhs.id == rhs.id
        }
    }

    static let presets: [Preset] = [
        Preset(id: "flat", name: "Flat", gains: flat),
        Preset(id: "bassBoost", name: "Bass Boost", gains: [6, 5.5, 4.5, 3, 1, 0, 0, 0, 0, 0]),
        Preset(id: "bassReducer", name: "Bass Reducer", gains: [-6, -5.5, -4.5, -3, -1, 0, 0, 0, 0, 0]),
        Preset(id: "trebleBoost", name: "Treble Boost", gains: [0, 0, 0, 0, 0, 1, 2.5, 4, 5, 6]),
        Preset(id: "vocal", name: "Vocal", gains: [-2, -2, -1, 1, 3, 4, 3.5, 2, 0, -1]),
        Preset(id: "spokenWord", name: "Spoken Word", gains: [-6, -4, -1, 1, 3, 4, 4, 3, 1, -2]),
        Preset(id: "loudness", name: "Loudness", gains: [5, 4, 2, 0, -1, 0, 0, 1, 3, 4]),
        Preset(id: "rock", name: "Rock", gains: [4.5, 3.5, 2, 0.5, -1, -0.5, 1, 2.5, 3.5, 4]),
        Preset(id: "electronic", name: "Electronic", gains: [4.5, 4, 1.5, 0, -2, 1.5, 0.5, 1.5, 4, 5]),
        Preset(id: "classical", name: "Classical", gains: [4, 3, 2.5, 2, -1, -1, 0, 2, 3, 3.5]),
        Preset(id: "night", name: "Late Night", gains: [-3, -2, -1, 0, 1, 2, 2, 1, 0, -1]),
    ]

    static func preset(matching gains: [Float]?) -> Preset? {
        let gains = gains ?? flat
        return presets.first { preset in
            zip(preset.gains, gains).allSatisfy { abs($0 - $1) < 0.05 }
        }
    }

    // MARK: Filter math

    /// Biquad coefficients for all bands, in vDSP order: b0, b1, b2, a1, a2 per band (normalized by a0).
    static func coefficients(gains: [Float], sampleRate: Double) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(bandCount * 5)
        for (index, frequency) in frequencies.enumerated() {
            let gain = index < gains.count ? Double(gains[index]) : 0
            result += peakingCoefficients(frequency: frequency, gainDB: gain, q: bandwidthQ, sampleRate: sampleRate)
        }
        return result
    }

    /// RBJ Audio EQ Cookbook peaking filter. Returns a pass-through filter for 0 dB or unusable frequencies.
    static func peakingCoefficients(frequency: Double, gainDB: Double, q quality: Double, sampleRate: Double) -> [Double] {
        guard abs(gainDB) > 0.001, sampleRate > 0, frequency < sampleRate * 0.45 else {
            return [1, 0, 0, 0, 0]
        }
        let amplitude = pow(10, gainDB / 40)
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * quality)
        let cosine = cos(omega)
        let a0 = 1 + alpha / amplitude
        return [
            (1 + alpha * amplitude) / a0,
            (-2 * cosine) / a0,
            (1 - alpha * amplitude) / a0,
            (-2 * cosine) / a0,
            (1 - alpha / amplitude) / a0,
        ]
    }

    /// The filter cascade's gain in dB at `frequency`. Used by tests to check the filters do what they should.
    static func responseDB(coefficients: [Double], at frequency: Double, sampleRate: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        var magnitude = 1.0
        for band in stride(from: 0, to: coefficients.count, by: 5) {
            let (b0, b1, b2, a1, a2) = (
                coefficients[band], coefficients[band + 1], coefficients[band + 2],
                coefficients[band + 3], coefficients[band + 4]
            )
            // H(z) at z = e^{jω}
            let numReal = b0 + b1 * cos(-omega) + b2 * cos(-2 * omega)
            let numImag = b1 * sin(-omega) + b2 * sin(-2 * omega)
            let denReal = 1 + a1 * cos(-omega) + a2 * cos(-2 * omega)
            let denImag = a1 * sin(-omega) + a2 * sin(-2 * omega)
            magnitude *= sqrt(numReal * numReal + numImag * numImag) / sqrt(denReal * denReal + denImag * denImag)
        }
        return 20 * log10(magnitude)
    }
}
