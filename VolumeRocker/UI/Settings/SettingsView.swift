import SwiftUI

/// The native Settings window. More tabs (Apps, Devices, Shortcuts, Updates) arrive in Phase 4.
struct SettingsView: View {
    let model: MixerModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(model: model)
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .scenePadding()
        .frame(width: 460)
    }
}

private struct GeneralSettingsView: View {
    let model: MixerModel

    var body: some View {
        Form {
            Section {
                Toggle("Show recent apps in the mixer", isOn: Binding(
                    get: { model.showRecentApps },
                    set: { model.showRecentApps = $0 }
                ))
            } footer: {
                Text("When off, only apps that are playing sound right now are shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permission") {
                LabeledContent("System Audio Recording") {
                    switch model.permission {
                    case .authorized: Text("Allowed")
                    case .denied: Text("Not Allowed")
                    case .notDetermined: Text("Not Requested")
                    case .unknown: Text("Unknown")
                    }
                }
                if model.permission != .authorized {
                    Button("Open Privacy Settings") {
                        if let url = AudioCapturePermission.settingsURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text(AppInfo.name)
                .font(.title2.bold())
            Text("Version \(AppInfo.versionString)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Per-app volume control for your Mac.")
            if let url = AppInfo.repositoryURL {
                Link("View on GitHub", destination: url)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
