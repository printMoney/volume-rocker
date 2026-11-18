import SwiftUI

/// App entry point. Volume Rocker lives only in the menu bar (`LSUIElement`), so there is no Dock icon
/// and no main window, just the mixer panel and a separate Settings window.
@main
struct VolumeRockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MixerPanelView(model: appDelegate.model)
        } label: {
            MenuBarIcon(output: appDelegate.model.output)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MixerModel()
    private let onboarding = OnboardingWindowController()

    /// Unit tests launch the app as their host; don't touch real audio then.
    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_: Notification) {
        guard !isRunningTests else { return }
        model.start()
        if !model.hasCompletedOnboarding {
            onboarding.show(model: model)
        }
    }

    func applicationDidBecomeActive(_: Notification) {
        guard !isRunningTests else { return }
        // The user may have changed the permission in System Settings.
        model.refreshPermission()
    }

    func applicationWillTerminate(_: Notification) {
        model.shutdown()
    }
}
