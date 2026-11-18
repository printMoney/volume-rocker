import CoreAudio
import Foundation

/// A failed Core Audio call, with the operation that failed and its status code.
struct CoreAudioError: Error, CustomStringConvertible {
    let status: OSStatus
    let operation: String

    var description: String {
        "\(operation) failed with status \(status) (\(status.fourCharCode))"
    }
}

/// Throws a `CoreAudioError` unless `status` is `noErr`.
func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(status: status, operation: operation()) }
}

extension OSStatus {
    /// Core Audio status codes are often four printable characters, e.g. 'who?'.
    var fourCharCode: String {
        let bytes = withUnsafeBytes(of: UInt32(bitPattern: self).bigEndian) { Array($0) }
        guard bytes.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else { return String(self) }
        return String(bytes: bytes, encoding: .ascii) ?? String(self)
    }
}

extension AudioObjectPropertyAddress {
    init(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = AudioObjectID(kAudioObjectUnknown)

    var isValid: Bool {
        self != .unknown
    }

    func hasProperty(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(self, &address)
    }

    func isSettable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        guard hasProperty(address) else { return false }
        return AudioObjectIsPropertySettable(self, &address, &settable) == noErr && settable.boolValue
    }

    /// Reads a fixed-size property value.
    func read<T: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, default value: T) throws -> T {
        var address = address
        var value = value
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0) }
        try check(status, "Read '\(address.mSelector.fourCharCode)'")
        return value
    }

    /// Reads a variable-length array property.
    func readArray<T: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, of _: T.Type) throws -> [T] {
        var address = address
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "Size of '\(address.mSelector.fourCharCode)'")
        let capacity = Int(size) / MemoryLayout<T>.stride
        guard capacity > 0 else { return [] }
        return try [T](unsafeUninitializedCapacity: capacity) { buffer, initializedCount in
            var dataSize = size
            let status = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, buffer.baseAddress!)
            guard status == noErr else {
                initializedCount = 0
                throw CoreAudioError(status: status, operation: "Read '\(address.mSelector.fourCharCode)'")
            }
            initializedCount = Swift.min(capacity, Int(dataSize) / MemoryLayout<T>.stride)
        }
    }

    /// Reads a CFString property.
    func readString(_ address: AudioObjectPropertyAddress) throws -> String {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, &value), "Read '\(address.mSelector.fourCharCode)'")
        return (value?.takeRetainedValue() as String?) ?? ""
    }

    func write<T: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, value: T) throws {
        var address = address
        var value = value
        let size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafePointer(to: &value) { AudioObjectSetPropertyData(self, &address, 0, nil, size, $0) }
        try check(status, "Write '\(address.mSelector.fourCharCode)'")
    }
}

// MARK: - Devices

extension AudioObjectID {
    static func defaultOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.read(AudioObjectPropertyAddress(kAudioHardwarePropertyDefaultOutputDevice), default: .unknown)
    }

    func deviceUID() throws -> String {
        try readString(AudioObjectPropertyAddress(kAudioDevicePropertyDeviceUID))
    }

    var objectName: String {
        (try? readString(AudioObjectPropertyAddress(kAudioObjectPropertyName))) ?? ""
    }

    func streamCount(scope: AudioObjectPropertyScope) -> Int {
        let address = AudioObjectPropertyAddress(kAudioDevicePropertyStreams, scope: scope)
        return (try? readArray(address, of: AudioStreamID.self).count) ?? 0
    }
}

extension UInt32 {
    var fourCharCode: String {
        OSStatus(bitPattern: self).fourCharCode
    }
}
