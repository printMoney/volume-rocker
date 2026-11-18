import KeyboardShortcuts
import SwiftUI

/// The native Settings window.
struct SettingsView: View {
    let model: MixerModel
    let updates: UpdateController
    let loginItem: LoginItem

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(model: model, loginItem: loginItem)
            }
            Tab("Apps", systemImage: "square.grid.2x2") {
                AppSettingsView(model: model)
            }
            Tab("Devices", systemImage: "hifispeaker.2") {
                DeviceSettingsView(model: model)
            }
            Tab("Shortcuts", systemImage: "keyboard") {
                ShortcutSettingsView(model: model)
            }
            Tab("Profiles", systemImage: "square.stack.3d.up") {
                ProfileSettingsView(model: model)
            }
            Tab("Updates", systemImage: "arrow.down.circle") {
                UpdateSettingsView(updates: updates)
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .scenePadding()
        .frame(width: 520)
    }
}

private struct SettingsFooter: View {
    let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: General

private struct GeneralSettingsView: View {
    let model: MixerModel
    let loginItem: LoginItem

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                if loginItem.needsApproval {
                    HStack {
                        Text("Allow Volume Rocker in System Settings to finish.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { loginItem.openSystemSettings() }
                    }
                }
            }

            Section {
                Toggle("Show recent apps in the mixer", isOn: Binding(
                    get: { model.showRecentApps },
                    set: { model.showRecentApps = $0 }
                ))
            } footer: {
                SettingsFooter(Text("When off, only apps that are playing sound right now are shown."))
            }

            Section {
                Toggle("Allow volume boost up to 200%", isOn: Binding(
                    get: { model.allowBoost },
                    set: { model.allowBoost = $0 }
                ))
            } footer: {
                SettingsFooter(Text("Makes quiet apps louder. A built-in limiter keeps boosted sound from distorting."))
            }

            Section {
                LabeledContent("Scroll on the menu bar icon", value: String(localized: "Changes the output volume"))
                LabeledContent("Option-click or right-click it", value: String(localized: "Shows devices and profiles"))
            } header: {
                Text("Menu Bar Icon")
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

// MARK: Apps

private struct AppSettingsView: View {
    let model: MixerModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Volume for new apps") {
                    HStack {
                        Slider(
                            value: Binding(get: { Double(model.newAppVolume) }, set: { model.newAppVolume = Float($0) }),
                            in: 0 ... 1,
                            step: 0.05
                        ) {
                            Text("Volume for new apps")
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        Text(model.newAppVolume, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } footer: {
                SettingsFooter(Text("Used for apps you haven’t adjusted yet."))
            }

            Section {
                if model.excludedAppIDs.isEmpty {
                    Text("No excluded apps.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.excludedAppIDs.sorted(), id: \.self) { appID in
                    HStack {
                        Text(model.appName(forID: appID))
                        Text(appID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") { model.include(appID: appID) }
                    }
                }
                let candidates = model.apps.filter { !model.excludedAppIDs.contains($0.id) }
                Menu("Exclude an App…") {
                    ForEach(candidates) { item in
                        Button(item.name) { model.exclude(appID: item.id) }
                    }
                }
                .disabled(candidates.isEmpty)
            } header: {
                Text("Excluded Apps")
            } footer: {
                SettingsFooter(Text("""
                Volume Rocker leaves excluded apps completely alone: they aren’t shown and their sound is never \
                touched. Useful for pro audio apps or anything that should bypass the mixer.
                """))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Devices

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
                SettingsFooter(Text("""
                For example, keep music quieter on your speakers than on your headphones. \
                Volumes switch automatically with the output device.
                """))
            }

            Section {
                Toggle("Show input device in the mixer", isOn: Binding(
                    get: { model.showInputControls },
                    set: { model.showInputControls = $0 }
                ))
            } footer: {
                SettingsFooter(Text("Switch the microphone and change its input volume from the menu bar. This does not record audio."))
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Shortcuts

private struct ShortcutSettingsView: View {
    let model: MixerModel

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open or close the mixer", name: .toggleMixer)
                KeyboardShortcuts.Recorder("Mute or unmute output", name: .toggleOutputMute)
                KeyboardShortcuts.Recorder("Output volume up", name: .outputVolumeUp)
                KeyboardShortcuts.Recorder("Output volume down", name: .outputVolumeDown)
                KeyboardShortcuts.Recorder("Next profile", name: .nextProfile)
            } footer: {
                SettingsFooter(Text("Shortcuts work in every app."))
            }

            if !model.profiles.isEmpty {
                Section("Profiles") {
                    ForEach(model.profiles) { profile in
                        KeyboardShortcuts.Recorder(profile.name, name: .profile(profile.id))
                    }
                }
            }

            Section {
                Text("""
                Volume Rocker’s actions are also in the Shortcuts app: set an app’s volume, mute an app, \
                switch the output device, set the output volume and apply a profile. Ask Siri, for example, \
                “Apply Work in Volume Rocker”.
                """)
                .foregroundStyle(.secondary)
            } header: {
                Text("Shortcuts App and Siri")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Profiles

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
                SettingsFooter(Text("""
                A profile saves each app’s volume, mute, equalizer and output device. \
                Apps a profile doesn’t know go back to 100%. Give profiles keyboard shortcuts in the Shortcuts tab.
                """))
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

// MARK: Updates

private struct UpdateSettingsView: View {
    let updates: UpdateController

    var body: some View {
        Form {
            if updates.isConfigured {
                Section {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.automaticallyChecksForUpdates = $0 }
                    ))
                    LabeledContent("Last checked") {
                        if let date = updates.lastUpdateCheckDate {
                            Text(date, format: .relative(presentation: .named))
                        } else {
                            Text("Never")
                        }
                    }
                    Button("Check for Updates Now") { updates.checkForUpdates() }
                } footer: {
                    SettingsFooter(Text("Updates are downloaded from GitHub and verified with a digital signature before installing."))
                }
            } else {
                Section {
                    Text("Automatic updates aren’t set up in this build.")
                    if let url = AppInfo.releasesURL {
                        Link("See Releases on GitHub", destination: url)
                    }
                } footer: {
                    SettingsFooter(Text("This is normal for builds made from source. Official releases update automatically."))
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: About

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
            HStack(spacing: 16) {
                if let url = AppInfo.repositoryURL {
                    Link("GitHub", destination: url)
                }
                if let url = AppInfo.issuesURL {
                    Link("Report a Problem", destination: url)
                }
            }
            Text("Free and open source under the MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
