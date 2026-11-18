import SwiftUI

/// The native Settings window. More tabs (Apps, Shortcuts, Updates) arrive in Phase 4.
struct SettingsView: View {
    let model: MixerModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(model: model)
            }
            Tab("Devices", systemImage: "hifispeaker.2") {
                DeviceSettingsView(model: model)
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

private struct DeviceSettingsView: View {
    let model: MixerModel

    var body: some View {
        Form {
            Section {
                Toggle("Remember app volumes for each output device", isOn: Binding(
                    get: { model.rememberVolumesPerDevice },
                    set: { model.rememberVolumesPerDevice = $0 }
                ))
            } footer: {
                Text("""
                For example, keep music quieter on your speakers than on your headphones. \
                Volumes switch automatically with the output device.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show input device in the mixer", isOn: Binding(
                    get: { model.showInputControls },
                    set: { model.showInputControls = $0 }
                ))
            } footer: {
                Text("Switch the microphone and change its input volume from the menu bar. This does not record audio.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
