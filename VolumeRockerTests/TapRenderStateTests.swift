import CoreAudio
import Testing
@testable import VolumeRocker

struct TapRenderStateTests {
    @Test func appliesSteadyGainToInterleavedStereo() {
        let state = TapRenderState(gain: 0.5)
        let input = TestBufferList([(2, 64)]) { _ in 0.8 }
        let output = TestBufferList([(2, 64)])
        render(state, input: input, output: output)
        #expect(output.samples(0).allSatisfy { abs($0 - 0.4) < 0.0001 })
    }

    @Test func rampsSmoothlyToNewGainWithoutJumps() throws {
        let state = TapRenderState(gain: 1)
        state.setTargetGain(0)
        let input = TestBufferList([(2, 128)]) { _ in 0.5 }
        let output = TestBufferList([(2, 128)])
        render(state, input: input, output: output)

        let left = stride(from: 0, to: 256, by: 2).map { output.samples(0)[$0] }
        #expect(try abs(#require(left.first) - 0.5) < 0.0001)
        #expect(try #require(left.last) < 0.01)
        // Monotonic, with no step bigger than one ramp increment.
        for (previous, next) in zip(left, left.dropFirst()) {
            #expect(next <= previous)
            #expect(previous - next < 0.005)
        }

        // Next buffer: fully at the new gain.
        let output2 = TestBufferList([(2, 128)])
        render(state, input: input, output: output2)
        #expect(output2.samples(0).allSatisfy { $0 == 0 })
    }

    @Test func mutedStateWritesSilence() {
        let state = TapRenderState(gain: 0)
        let input = TestBufferList([(2, 32)]) { _ in 0.9 }
        let output = TestBufferList([(2, 32)]) { _ in 0.123 } // stale data must be cleared
        render(state, input: input, output: output)
        #expect(output.samples(0).allSatisfy { $0 == 0 })
    }

    @Test func writesLeftAndRightToNonInterleavedOutputs() {
        let state = TapRenderState(gain: 1)
        // Interleaved stereo input: L = 0.25, R = 0.75
        let input = TestBufferList([(2, 16)]) { $0.isMultiple(of: 2) ? 0.25 : 0.75 }
        let output = TestBufferList([(1, 16), (1, 16), (1, 16)])
        render(state, input: input, output: output)
        #expect(output.samples(0).allSatisfy { abs($0 - 0.25) < 0.0001 })
        #expect(output.samples(1).allSatisfy { abs($0 - 0.75) < 0.0001 })
        #expect(output.samples(2).allSatisfy { $0 == 0 })
    }

    @Test func fillsOnlyFirstTwoChannelsOfMultichannelDevice() {
        let state = TapRenderState(gain: 1)
        let input = TestBufferList([(2, 8)]) { $0.isMultiple(of: 2) ? 0.1 : 0.2 }
        let output = TestBufferList([(6, 8)])
        render(state, input: input, output: output)
        let samples = output.samples(0)
        for frame in 0 ..< 8 {
            #expect(abs(samples[frame * 6] - 0.1) < 0.0001)
            #expect(abs(samples[frame * 6 + 1] - 0.2) < 0.0001)
            #expect(samples[frame * 6 + 2 ..< frame * 6 + 6].allSatisfy { $0 == 0 })
        }
    }

    @Test func usesLastInputBufferAsTheTap() {
        let state = TapRenderState(gain: 1)
        // First buffer simulates a device microphone that must be ignored.
        let input = TestBufferList([(1, 16), (2, 16)]) { _ in 0.5 }
        let output = TestBufferList([(2, 16)])
        render(state, input: input, output: output)
        #expect(output.samples(0).allSatisfy { abs($0 - 0.5) < 0.0001 })
    }

    @Test func reportsPeakScaledByGainAndResetsAfterReading() {
        let state = TapRenderState(gain: 0.5)
        let input = TestBufferList([(2, 32)]) { $0 == 10 ? -0.8 : 0.1 }
        let output = TestBufferList([(2, 32)])
        render(state, input: input, output: output)
        #expect(abs(state.takePeak() - 0.4) < 0.0001)
        #expect(state.takePeak() == 0)
    }

    @Test func negativeGainIsClampedToZero() {
        let state = TapRenderState(gain: 1)
        state.setTargetGain(-3)
        #expect(state.targetGain == 0)
    }
}
