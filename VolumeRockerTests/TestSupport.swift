import CoreAudio
@testable import VolumeRocker

/// Owns fake audio buffers for feeding `TapRenderState.render`.
final class TestBufferList {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []

    init(_ layout: [(channels: Int, frames: Int)], fill: (Int) -> Float = { _ in 0 }) {
        list = AudioBufferList.allocate(maximumBuffers: layout.count)
        for (index, buffer) in layout.enumerated() {
            let count = buffer.channels * buffer.frames
            let data = UnsafeMutablePointer<Float>.allocate(capacity: count)
            for sample in 0 ..< count {
                data[sample] = fill(sample)
            }
            storage.append(data)
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(buffer.channels),
                mDataByteSize: UInt32(count * MemoryLayout<Float>.size),
                mData: data
            )
        }
    }

    func samples(_ index: Int) -> [Float] {
        let buffer = list[index]
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        return Array(UnsafeBufferPointer(start: storage[index], count: count))
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

func render(_ state: TapRenderState, input: TestBufferList, output: TestBufferList) {
    state.render(input: UnsafePointer(input.list.unsafePointer), output: output.list.unsafeMutablePointer)
}
