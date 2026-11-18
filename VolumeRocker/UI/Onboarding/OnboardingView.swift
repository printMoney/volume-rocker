import AppKit
import SwiftUI

/// Shows the first-launch onboarding in its own window. SwiftUI can't open a window on launch from a
/// menu-bar-only app, so a small AppKit window controller hosts the SwiftUI view.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(model: MixerModel, loginItem: LoginItem) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let view = OnboardingView(model: model, loginItem: loginItem) { [weak self] in self?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "Welcome to Volume Rocker")
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    private func close() {
        window?.close()
        window = nil
    }
}

/// Welcome → permission → done.
struct OnboardingView: View {
    let model: MixerModel
    let loginItem: LoginItem
    let onFinish: () -> Void

    private enum Step { case welcome, permission, done }
    @State private var step = Step.welcome
    @State private var isRequesting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case .welcome: welcome
            case .permission: permission
            case .done: done
            }
        }
        .padding(32)
        .frame(width: 440, height: 400)
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: step)
    }

    private var welcome: some View {
        page(
            symbol: "slider.vertical.3",
            title: Text("Welcome to Volume Rocker"),
            message: Text("Give every app its own volume. Turn down a noisy browser tab without touching your music.")
        ) {
            Button("Continue") { step = model.permission == .authorized ? .done : .permission }
        }
    }

    private var permission: some View {
        page(
            symbol: "lock.shield",
            title: Text("One Permission"),
            message: Text("""
            To change an app’s volume, macOS requires the “System Audio Recording” permission. \
            Audio is processed on your Mac in real time. It is never recorded, saved or sent anywhere.
            """)
        ) {
            if model.permission == .denied {
                Text("Access was turned off. You can turn it on in System Settings → Privacy & Security → Screen & System Audio Recording.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open System Settings") {
                        if let url = AudioCapturePermission.settingsURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Continue") { step = .done }
                }
            } else {
                Button {
                    isRequesting = true
                    Task {
                        await model.requestPermission()
                        isRequesting = false
                        if model.permission != .denied {
                            step = .done
                        }
                    }
                } label: {
                    Text("Allow Access…")
                }
                .disabled(isRequesting)
            }
        }
    }

    private var done: some View {
        page(
            symbol: "menubar.arrow.up.rectangle",
            title: Text("You’re All Set"),
            message: Text("Volume Rocker lives in your menu bar. Click the speaker icon to open the mixer.")
        ) {
            Toggle("Open Volume Rocker at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .buttonStyle(.automatic)
            Button("Start Using Volume Rocker") {
                model.completeOnboarding()
                onFinish()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func page(
        symbol: String,
        title: Text,
        message: Text,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            title
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            message
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                actions()
            }
            .prominentButtonStyle()
            .controlSize(.large)
        }
        .transition(.opacity)
    }
}

extension View {
    /// Liquid Glass buttons on macOS 26, the classic prominent style on macOS 15.
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
