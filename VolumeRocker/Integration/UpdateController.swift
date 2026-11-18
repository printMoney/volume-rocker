import AppKit
import Observation
import Sparkle

/// Automatic updates via Sparkle. Updates are signed with an EdDSA key; the public half is in Info.plist
/// (`SUPublicEDKey`) and the feed is the appcast on GitHub Pages (`SUFeedURL`).
///
/// Until a real key is configured (see docs/RELEASING.md), the updater stays off instead of showing errors.
@MainActor
@Observable
final class UpdateController {
    let isConfigured: Bool
    @ObservationIgnored private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        isConfigured = Self.isConfigured(info: bundle.infoDictionary ?? [:])
        controller = isConfigured
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    /// Sparkle needs a feed URL and a real EdDSA public key (44 base64 characters).
    nonisolated static func isConfigured(info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String, URL(string: feed)?.scheme == "https",
              let key = info["SUPublicEDKey"] as? String, key.count == 44, Data(base64Encoded: key) != nil
        else { return false }
        return true
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                controller?.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var lastUpdateCheckDate: Date? {
        controller?.updater.lastUpdateCheckDate
    }

    var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
