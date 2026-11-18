import Accelerate
import CoreAudio
import Synchronization

/// State shared between the main thread and one app's real-time IOProc.
///
/// `@unchecked Sendable` is deliberate and safe here: every value that crosses threads is an `Atomic`,
/// and `currentGain` is only ever read and written by the audio thread inside `render`.
final class TapRenderState: @unchecked Sendable {
    /// Gain the UI wants (0...1 in Phase 1), stored as Float bits. Written by the main thread.
    private let targetGainBits: Atomic<UInt32>
    /// Highest output peak since the UI last read it, stored as Float bits. Written by the audio thread.
    private let peakBits = Atomic<UInt32>(0)
    /// Gain applied at the end of the previous buffer. Audio thread only.
    private var currentGain: Float

    init(gain: Float = 1) {
        let gain = max(0, gain)
        targetGainBits = Atomic(gain.bitPattern)
        currentGain = gain
    }

    // MARK: Main thread

    var targetGain: Float {
        Float(bitPattern: targetGainBits.load(ordering: .relaxed))
    }

    func setTargetGain(_ gain: Float) {
        targetGainBits.store(max(0, gain).bitPattern, ordering: .relaxed)
    }

    /// Returns the peak level since the last call and resets it.
    func takePeak() -> Float {
        Float(bitPattern: peakBits.exchange(0, ordering: .relaxed))
    }

    // MARK: Audio thread

    /// Called from the IOProc. Copies the tapped app's audio (the last input buffer) to the device output,
    /// ramping the gain linearly across the buffer so changes never click.
    ///
    /// Real-time safe: no allocation, locks, logging, async or Objective-C.
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
        let tapFrames = Int(tapBuffer.mDataByteSize) / (MemoryLayout<Float>.size * tapChannels)
        let startGain = currentGain
        currentGain = target
        guard tapFrames > 0 else { return }

        var inputPeak: Float = 0
        vDSP_maxmgv(tapData, 1, &inputPeak, vDSP_Length(tapFrames * tapChannels))
        recordPeak(inputPeak * max(startGain, target))

        if startGain == 0, target == 0 {
            return
        }

        // Write tap channel 0/1 (left/right) to device channels 0/1, whether the device's buffers are
        // interleaved (one buffer, many channels) or not (one buffer per channel).
        var deviceChannel = 0
        for buffer in outputs {
            let outChannels = max(1, Int(buffer.mNumberChannels))
            defer { deviceChannel += outChannels }
            guard deviceChannel < 2, let outData = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let outFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
            let frames = min(tapFrames, outFrames)
            guard frames > 0 else { continue }
            var step = (target - startGain) / Float(frames)
            for channel in 0 ..< min(outChannels, 2 - deviceChannel) {
                let source = tapData + min(deviceChannel + channel, tapChannels - 1)
                var gain = startGain
                vDSP_vrampmul(source, tapChannels, &gain, &step, outData + channel, outChannels, vDSP_Length(frames))
            }
        }
    }

    private func recordPeak(_ level: Float) {
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
}
