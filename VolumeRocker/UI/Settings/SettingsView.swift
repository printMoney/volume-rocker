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
            Tab("Profiles", systemImage: "square.stack.3d.up") {
                ProfileSettingsView(model: model)
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

            Section {
                Toggle("Allow volume boost up to 200%", isOn: Binding(
                    get: { model.allowBoost },
                    set: { model.allowBoost = $0 }
                ))
            } footer: {
                Text("Makes quiet apps louder. A built-in limiter keeps boosted sound from distorting.")
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

private struct ProfileSettingsView: View {
    let model: MixerModel

    var body: some View {
        Form {
            Section {
                if model.profiles.isEmpty {
                    Text("Save your current mix from the menu bar panel with the profiles button.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.profiles) { profile in
                    ProfileRow(profile: profile, model: model)
                }
                .onMove { model.moveProfiles(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Profiles")
            } footer: {
                Text("A profile saves each app’s volume, mute, equalizer and output device. Apps a profile doesn’t know go back to 100%.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProfileRow: View {
    let profile: MixProfile
    let model: MixerModel
    @State private var name: String

    init(profile: MixProfile, model: MixerModel) {
        self.profile = profile
        self.model = model
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $name)
                .labelsHidden()
                .onSubmit { model.renameProfile(profile, to: name) }
            if let device = profile.outputDeviceName {
                Label(device, systemImage: "hifispeaker")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(profile.apps.count) apps")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Apply") { model.applyProfile(profile) }
            Button(role: .destructive) {
                model.deleteProfile(profile)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Delete \(profile.name)"))
        }
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
