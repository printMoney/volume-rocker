import Accelerate
import CoreAudio
import Synchronization

/// State shared between the main thread and one app's real-time IOProc, plus the render code itself.
///
/// Each buffer goes through: tap → EQ → gain ramp (0–200%) → limiter → meter → device channels.
///
/// `@unchecked Sendable` is deliberate and safe here:
/// - values written by other threads reach the audio thread only through `Atomic`s;
/// - EQ coefficients use a lock-free triple buffer (one writer, one reader), so the audio thread never waits;
/// - the writer side of the EQ is serialized by a `Mutex` that the audio thread never touches;
/// - everything marked "audio thread only" is touched only inside `render`.
final class TapRenderState: @unchecked Sendable {
    /// Largest buffer processed per call. Core Audio buffers are normally 512 frames or fewer.
    static let maxFrames = 8192
    /// Highest output level, just below full scale (−0.1 dB), so boosted audio never clips.
    static let limiterCeiling: Float = 0.989
    /// How fast the limiter lets go after a loud peak.
    static let limiterReleaseSeconds: Float = 0.25
    static let maxGain: Float = 2

    // MARK: Shared values

    private let targetGainBits: Atomic<UInt32>
    private let peakBits = Atomic<UInt32>(0)
    private let sampleRateBits = Atomic<UInt32>(Float(48000).bitPattern)
    /// Becomes true the first time a non-flat EQ is set; from then on the filters always run, so returning
    /// to flat fades smoothly instead of switching off abruptly.
    private let eqEnabled = Atomic<Bool>(false)

    // MARK: EQ triple buffer

    private static let coefficientCount = Equalizer.bandCount * 5
    private static let dirtyFlag = 4
    /// Three coefficient sets. The writer fills one, the reader uses another, the third is handed over.
    private let eqBuffers: UnsafeMutablePointer<Double>
    /// Index of the handed-over buffer, plus `dirtyFlag` when it holds newer coefficients than the reader has.
    private let eqMiddle = Atomic<Int>(1)

    private struct EQWriter {
        var gains = Equalizer.flat
        var sampleRate: Double = 48000
        var backIndex = 2
    }

    private let eqWriter = Mutex(EQWriter())

    // MARK: Audio thread only

    private var currentGain: Float
    private var limiterGain: Float = 1
    private var eqFrontIndex = 0
    private let eqSetup: vDSP_biquadm_Setup?
    private let scratch: UnsafeMutablePointer<Float>
    private let channelInputs: UnsafeMutablePointer<UnsafePointer<Float>>
    private let channelOutputs: UnsafeMutablePointer<UnsafeMutablePointer<Float>>

    init(gain: Float = 1) {
        let gain = min(Self.maxGain, max(0, gain))
        targetGainBits = Atomic(gain.bitPattern)
        currentGain = gain

        scratch = .allocate(capacity: Self.maxFrames * 2)
        scratch.initialize(repeating: 0, count: Self.maxFrames * 2)
        channelInputs = .allocate(capacity: 2)
        channelInputs.initialize(to: UnsafePointer(scratch))
        (channelInputs + 1).initialize(to: UnsafePointer(scratch + 1))
        channelOutputs = .allocate(capacity: 2)
        channelOutputs.initialize(to: scratch)
        (channelOutputs + 1).initialize(to: scratch + 1)

        let flat = Equalizer.coefficients(gains: Equalizer.flat, sampleRate: 48000)
        eqBuffers = .allocate(capacity: Self.coefficientCount * 3)
        for index in 0 ..< 3 {
            (eqBuffers + index * Self.coefficientCount).initialize(from: flat, count: Self.coefficientCount)
        }
        let perChannel = flat + flat
        eqSetup = vDSP_biquadm_CreateSetup(perChannel, vDSP_Length(Equalizer.bandCount), 2)
    }

    deinit {
        if let eqSetup {
            vDSP_biquadm_DestroySetup(eqSetup)
        }
        scratch.deallocate()
        channelInputs.deallocate()
        channelOutputs.deallocate()
        eqBuffers.deallocate()
    }

    // MARK: Main thread / engine

    var targetGain: Float {
        Float(bitPattern: targetGainBits.load(ordering: .relaxed))
    }

    func setTargetGain(_ gain: Float) {
        targetGainBits.store(min(Self.maxGain, max(0, gain)).bitPattern, ordering: .relaxed)
    }

    /// Returns the peak level since the last call and resets it.
    func takePeak() -> Float {
        Float(bitPattern: peakBits.exchange(0, ordering: .relaxed))
    }

    /// Sets the EQ band gains in dB (nil = flat).
    func setEqualizer(_ gains: [Float]?) {
        let gains = gains ?? Equalizer.flat
        if !Equalizer.isFlat(gains) {
            eqEnabled.store(true, ordering: .releasing)
        }
        eqWriter.withLock { writer in
            writer.gains = gains
            publishCoefficients(&writer)
        }
    }

    /// Called by the engine before a session starts, with the device's sample rate.
    func setSampleRate(_ sampleRate: Double) {
        guard sampleRate > 0 else { return }
        sampleRateBits.store(Float(sampleRate).bitPattern, ordering: .relaxed)
        eqWriter.withLock { writer in
            guard writer.sampleRate != sampleRate else { return }
            writer.sampleRate = sampleRate
            publishCoefficients(&writer)
        }
    }

    private func publishCoefficients(_ writer: inout EQWriter) {
        let coefficients = Equalizer.coefficients(gains: writer.gains, sampleRate: writer.sampleRate)
        (eqBuffers + writer.backIndex * Self.coefficientCount).update(from: coefficients, count: Self.coefficientCount)
        let previous = eqMiddle.exchange(writer.backIndex | Self.dirtyFlag, ordering: .acquiringAndReleasing)
        writer.backIndex = previous & ~Self.dirtyFlag
    }

    // MARK: Audio thread

    /// Called from the IOProc. Processes the tapped app's audio (the last input buffer) and writes it to the
    /// device output. Real-time safe: no allocation, locks, logging, async or Objective-C.
    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let target = Float(bitPattern: targetGainBits.load(ordering: .relaxed))

        for buffer in outputs {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }

        // The tap's stream comes after any input streams of the output device, so it is the last buffer.
        guard !inputs.isEmpty,
              let tapBuffer = inputs.last,
              let tapData = tapBuffer.mData?.assumingMemoryBound(to: Float.self)
        else {
            currentGain = target
            return
        }

        let tapChannels = max(1, Int(tapBuffer.mNumberChannels))
        let frames = min(Self.maxFrames, Int(tapBuffer.mDataByteSize) / (MemoryLayout<Float>.size * tapChannels))
        let startGain = currentGain
        currentGain = target
        guard frames > 0, startGain > 0 || target > 0 else { return }

        loadStereo(from: tapData, channels: tapChannels, frames: frames)
        applyEqualizer(frames: frames)
        applyGainRamp(from: startGain, to: target, frames: frames)
        applyLimiter(frames: frames)
        recordPeak(frames: frames)
        writeOutputs(outputs, frames: frames)
    }

    /// Copies the tap's first two channels into the interleaved stereo scratch buffer.
    private func loadStereo(from source: UnsafeMutablePointer<Float>, channels: Int, frames: Int) {
        if channels == 2 {
            scratch.update(from: source, count: frames * 2)
            return
        }
        var zero: Float = 0
        let length = vDSP_Length(frames)
        vDSP_vsadd(source, vDSP_Stride(channels), &zero, scratch, 2, length)
        vDSP_vsadd(source + (channels > 1 ? 1 : 0), vDSP_Stride(channels), &zero, scratch + 1, 2, length)
    }

    private func applyEqualizer(frames: Int) {
        guard eqEnabled.load(ordering: .acquiring), let eqSetup else { return }
        if eqMiddle.load(ordering: .acquiring) & Self.dirtyFlag != 0 {
            let handedOver = eqMiddle.exchange(eqFrontIndex, ordering: .acquiringAndReleasing)
            eqFrontIndex = handedOver & ~Self.dirtyFlag
            let coefficients = eqBuffers + eqFrontIndex * Self.coefficientCount
            for channel in 0 ..< 2 {
                vDSP_biquadm_SetCoefficientsDouble(
                    eqSetup, coefficients, 0, vDSP_Length(channel), vDSP_Length(Equalizer.bandCount), 1
                )
            }
        }
        vDSP_biquadm(eqSetup, channelInputs, 2, channelOutputs, 2, vDSP_Length(frames))
    }

    /// Linear gain ramp across the buffer, so volume changes never click.
    private func applyGainRamp(from start: Float, to target: Float, frames: Int) {
        guard start != 1 || target != 1 else { return }
        var step = (target - start) / Float(frames)
        for channel in 0 ..< 2 {
            var gain = start
            vDSP_vrampmul(scratch + channel, 2, &gain, &step, scratch + channel, 2, vDSP_Length(frames))
        }
    }

    /// A peak limiter that looks at the whole buffer before changing it. It reduces gain instantly when the
    /// buffer would exceed the ceiling and releases smoothly afterwards, so the output can never clip.
    private func applyLimiter(frames: Int) {
        var peak: Float = 0
        vDSP_maxmgv(scratch, 1, &peak, vDSP_Length(frames * 2))
        let required = peak > Self.limiterCeiling ? Self.limiterCeiling / peak : 1

        let sampleRate = Float(bitPattern: sampleRateBits.load(ordering: .relaxed))
        let releaseFactor = expf(-Float(frames) / (Self.limiterReleaseSeconds * max(sampleRate, 8000)))
        let released = 1 - (1 - limiterGain) * releaseFactor
        let end = min(required, released)
        // Starting no higher than `required` keeps every sample in this buffer at or below the ceiling.
        let start = min(limiterGain, required)
        limiterGain = end
        guard start < 1 || end < 1 else { return }

        var step = (end - start) / Float(frames)
        for channel in 0 ..< 2 {
            var gain = start
            vDSP_vrampmul(scratch + channel, 2, &gain, &step, scratch + channel, 2, vDSP_Length(frames))
        }
    }

    private func recordPeak(frames: Int) {
        var level: Float = 0
        vDSP_maxmgv(scratch, 1, &level, vDSP_Length(frames * 2))
        var stored = peakBits.load(ordering: .relaxed)
        while Float(bitPattern: stored) < level {
            let (exchanged, original) = peakBits.compareExchange(
                expected: stored, desired: level.bitPattern, ordering: .relaxed
            )
            if exchanged {
                break
            }
            stored = original
        }
    }

    /// Writes left/right to device channels 0/1, whether the device's buffers are interleaved (one buffer,
    /// many channels) or not (one buffer per channel). Other channels stay silent.
    private func writeOutputs(_ outputs: UnsafeMutableAudioBufferListPointer, frames: Int) {
        var zero: Float = 0
        var deviceChannel = 0
        for buffer in outputs {
            let outChannels = max(1, Int(buffer.mNumberChannels))
            defer { deviceChannel += outChannels }
            guard deviceChannel < 2, let outData = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let outFrames = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * outChannels))
            guard outFrames > 0 else { continue }
            for channel in 0 ..< min(outChannels, 2 - deviceChannel) {
                vDSP_vsadd(
                    scratch + deviceChannel + channel, 2, &zero,
                    outData + channel, vDSP_Stride(outChannels), vDSP_Length(outFrames)
                )
            }
        }
    }
}
