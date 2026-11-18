import Foundation
import Observation
import OSLog
import ServiceManagement

/// "Open at Login", using the modern `SMAppService` API. macOS lists the app in
/// System Settings → General → Login Items, where the user can also turn it off.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger(subsystem: "io.github.printmoney.VolumeRocker", category: "LoginItem")
                .error("Login item change failed: \(String(describing: error), privacy: .public)")
        }
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
