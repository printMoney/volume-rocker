import CoreFoundation
import Foundation

/// The "System Audio Recording" permission that Core Audio process taps require.
///
/// macOS has no public API to *check* this permission. If a tap is created without it, the tapped app is muted
/// and we receive silence, which would silence the user's apps. So, like Apple-adjacent sample code (AudioCap),
/// we ask the TCC framework directly. If those functions ever disappear, the status falls back to `.unknown`
/// and the app relies on the system prompt shown when the first tap is created.
enum AudioCapturePermission {
    enum Status: Sendable, Equatable {
        case authorized
        case denied
        case notDetermined
        case unknown
    }

    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let serviceName = "kTCCServiceAudioCapture"
    private static let tccPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle = dlopen(tccPath, RTLD_NOW), let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }

    static func status() -> Status {
        guard let preflight = symbol("TCCAccessPreflight", as: PreflightFunction.self) else { return .unknown }
        switch preflight(serviceName as CFString, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// Shows the system permission prompt (only the first time) and returns whether access was granted.
    static func request() async -> Status {
        guard let request = symbol("TCCAccessRequest", as: RequestFunction.self) else { return .unknown }
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            request(serviceName as CFString, nil) { granted in continuation.resume(returning: granted) }
        }
        return granted ? .authorized : .denied
    }

    /// Opens System Settings → Privacy & Security → Screen & System Audio Recording.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
}
