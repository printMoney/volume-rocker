import Foundation
import Testing
@testable import VolumeRocker

private func sineBlock(_ block: Int, frequency: Float, amplitude: Float, frames: Int = 512) -> TestBufferList {
    TestBufferList([(2, frames)]) { sample in
        let frame = Float(block * frames + sample / 2)
        return amplitude * sinf(2 * .pi * frequency * frame / 48000)
    }
}

private func loudest(_ output: TestBufferList) -> Float {
    output.samples(0).map(abs).max() ?? 0
}

struct BoostAndLimiterTests {
    @Test func boostDoublesQuietAudio() {
        let state = TapRenderState(gain: 2)
        let input = TestBufferList([(2, 64)]) { _ in 0.2 }
        let output = TestBufferList([(2, 64)])
        render(state, input: input, output: output)
        #expect(output.samples(0).allSatisfy { abs($0 - 0.4) < 0.0001 })
    }

    @Test func gainIsCappedAt200Percent() {
        let state = TapRenderState(gain: 5)
        #expect(state.targetGain == 2)
    }

    @Test func boostedLoudAudioNeverExceedsCeiling() {
        let state = TapRenderState(gain: 2)
        let output = TestBufferList([(2, 512)])
        for block in 0 ..< 20 {
            render(state, input: sineBlock(block, frequency: 440, amplitude: 0.9), output: output)
            #expect(loudest(output) <= TapRenderState.limiterCeiling + 0.0001)
        }
    }

    @Test func limiterRecoversAfterLoudPassage() throws {
        let state = TapRenderState(gain: 2)
        let loud = TestBufferList([(2, 512)]) { _ in 0.9 }
        let quiet = TestBufferList([(2, 512)]) { _ in 0.1 }
        let output = TestBufferList([(2, 512)])
        render(state, input: loud, output: output)
        render(state, input: quiet, output: output)
        #expect(try #require(output.samples(0).last) < 0.2) // still reducing just after the peak
        for _ in 0 ..< 100 { // about one second later
            render(state, input: quiet, output: output)
        }
        #expect(try abs(#require(output.samples(0).last) - 0.2) < 0.002)
    }
}

struct EqualizerProcessingTests {
    @Test func boostsItsBand() {
        let state = TapRenderState(gain: 1)
        state.setSampleRate(48000)
        var gains = Equalizer.flat
        gains[5] = 6 // 1 kHz
        state.setEqualizer(gains)
        let output = TestBufferList([(2, 512)])
        for block in 0 ..< 40 {
            render(state, input: sineBlock(block, frequency: 1000, amplitude: 0.1), output: output)
        }
        #expect(abs(loudest(output) - 0.1995) < 0.01) // +6 dB ≈ ×1.995
    }

    @Test func leavesOtherBandsAlone() {
        let state = TapRenderState(gain: 1)
        state.setSampleRate(48000)
        var gains = Equalizer.flat
        gains[0] = 12 // 31 Hz
        state.setEqualizer(gains)
        let output = TestBufferList([(2, 512)])
        for block in 0 ..< 40 {
            render(state, input: sineBlock(block, frequency: 4000, amplitude: 0.1), output: output)
        }
        #expect(abs(loudest(output) - 0.1) < 0.005)
    }

    @Test func returningToFlatRestoresOriginalSound() {
        let state = TapRenderState(gain: 1)
        state.setSampleRate(48000)
        state.setEqualizer([6, 6, 6, 6, 6, 6, 6, 6, 6, 6])
        let output = TestBufferList([(2, 512)])
        render(state, input: sineBlock(0, frequency: 1000, amplitude: 0.1), output: output)
        state.setEqualizer(nil)
        for block in 1 ..< 40 {
            render(state, input: sineBlock(block, frequency: 1000, amplitude: 0.1), output: output)
        }
        #expect(abs(loudest(output) - 0.1) < 0.003)
    }
}

struct EqualizerMathTests {
    @Test func flatHasNoEffect() {
        let coefficients = Equalizer.coefficients(gains: Equalizer.flat, sampleRate: 48000)
        for frequency in [50.0, 1000, 10000] {
            #expect(abs(Equalizer.responseDB(coefficients: coefficients, at: frequency, sampleRate: 48000)) < 0.001)
        }
    }

    @Test func bandGainAppearsAtItsCenter() {
        for (index, frequency) in Equalizer.frequencies.enumerated() {
            var gains = Equalizer.flat
            gains[index] = 9
            let coefficients = Equalizer.coefficients(gains: gains, sampleRate: 44100)
            let response = Equalizer.responseDB(coefficients: coefficients, at: frequency, sampleRate: 44100)
            #expect(abs(response - 9) < 0.5, "band \(frequency) Hz gave \(response) dB")
        }
    }

    @Test func cutsWork() {
        var gains = Equalizer.flat
        gains[3] = -12
        let coefficients = Equalizer.coefficients(gains: gains, sampleRate: 48000)
        #expect(abs(Equalizer.responseDB(coefficients: coefficients, at: 250, sampleRate: 48000) + 12) < 0.5)
    }

    @Test func presetsHaveTenBandsWithinRange() {
        for preset in Equalizer.presets {
            #expect(preset.gains.count == Equalizer.bandCount)
            #expect(preset.gains.allSatisfy { Equalizer.gainRange.contains($0) })
        }
        #expect(Equalizer.preset(matching: nil)?.id == "flat")
        #expect(Equalizer.preset(matching: Equalizer.presets[1].gains)?.id == "bassBoost")
    }

    @Test func labelsAreShort() {
        #expect(Equalizer.label(for: 125) == "125")
        #expect(Equalizer.label(for: 16000) == "16k")
    }
}
