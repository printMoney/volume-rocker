import SwiftUI

/// The panel that opens when you click the menu bar icon.
struct MixerPanelView: View {
    let model: MixerModel
    /// Closes the panel (before opening Settings, for example).
    var onRequestClose: () -> Void = {}
    /// Reports the content's natural size, so the panel window can grow and shrink to fit it.
    var onSizeChange: (CGSize) -> Void = { _ in }
    /// The tallest the whole panel may be on the current screen (set by the panel controller).
    var maxPanelHeight: CGFloat = 800

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSavingProfile = false
    /// Natural height of the app list, measured so the list only scrolls when it doesn't fit.
    @State private var appListHeight: CGFloat = 0
    /// Height the app list actually shows (after its maximum), and the panel's whole natural height.
    @State private var appListVisibleHeight: CGFloat = 0
    @State private var panelHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceSectionView(
                controller: model.output,
                devices: model.devices.outputs,
                onSelect: { model.select($0, for: .output) }
            )

            if model.showInputControls, model.input.isAvailable {
                DeviceSectionView(
                    controller: model.input,
                    devices: model.devices.inputs,
                    onSelect: { model.select($0, for: .input) }
                )
            }

            if !model.canControlApps {
                PermissionBanner(model: model)
                    .transition(.opacity)
            }

            Divider()

            appsSection

            Divider()

            if isSavingProfile {
                SaveProfileView(model: model, isPresented: $isSavingProfile)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            footer
        }
        .padding(14)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            panelHeight = size.height
            onSizeChange(size)
        }
        // If the window is ever shorter than the content, trim the bottom, never the header.
        .frame(maxHeight: .infinity, alignment: .top)
        .trackingWindowVisibility()
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1), value: model.visibleApps.map(\.id))
        .animation(reduceMotion ? nil : .default, value: model.canControlApps)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: isSavingProfile)
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apps")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            let apps = model.visibleApps
            if apps.isEmpty {
                Text("Apps appear here as soon as they play sound.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(apps) { item in
                            AppRowView(item: item, model: model)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { appListHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.automatic)
                .frame(height: min(max(appListHeight, 1), maxAppListHeight))
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { appListVisibleHeight = $0 }
            }
        }
    }

    /// The app list grows with its content up to this height, then scrolls, so the panel always fits on screen
    /// with its device controls and buttons visible.
    /// How tall the app list may get: whatever room the panel has left after everything else in it
    /// (device sections, expanded device lists, footer), but at most 460 points and at least 120.
    private var maxAppListHeight: CGFloat {
        let everythingElse = max(0, panelHeight - appListVisibleHeight)
        return min(460, max(120, maxPanelHeight - everythingElse))
    }

    private var profilesMenu: some View {
        Menu {
            if model.profiles.isEmpty {
                Text("No Profiles Yet")
            }
            ForEach(model.profiles) { profile in
                Button {
                    model.applyProfile(profile)
                } label: {
                    if profile.id == model.activeProfileID {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
            Divider()
            Button("Save Current Mix…") { isSavingProfile = true }
            if !model.profiles.isEmpty {
                Button("Manage Profiles…") {
                    NSApp.activate()
                    openSettings()
                }
            }
        } label: {
            Image(systemName: "square.stack.3d.up")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.activeProfile.map { Text("Profile: \($0.name)") } ?? Text("Profiles"))
        .accessibilityLabel(Text("Profiles"))
        .accessibilityValue(model.activeProfile.map { Text($0.name) } ?? Text("None"))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Show Recent Apps", isOn: Binding(
                get: { model.showRecentApps },
                set: { model.showRecentApps = $0 }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Spacer()

            profilesMenu

            Button {
                onRequestClose()
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .keyboardShortcut(",")
            .help(Text("Settings…"))
            .accessibilityLabel(Text("Settings"))

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .keyboardShortcut("q")
            .help(Text("Quit Volume Rocker"))
            .accessibilityLabel(Text("Quit Volume Rocker"))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }
}

/// Button that toggles mute. Its icon follows the volume level.
struct MuteButton: View {
    let isMuted: Bool
    let symbol: String
    let label: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, alignment: .leading)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isMuted ? Color.secondary : Color.primary)
        .accessibilityLabel(isMuted ? Text("Unmute \(label)") : Text("Mute \(label)"))
        .help(isMuted ? Text("Unmute") : Text("Mute"))
    }
}

/// Shown when Volume Rocker doesn't have the System Audio Recording permission yet.
struct PermissionBanner: View {
    let model: MixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Permission Needed", systemImage: "lock.shield")
                .font(.callout.weight(.semibold))
            Text("To change the volume of individual apps, allow Volume Rocker to access system audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.permission == .denied {
                    Button("Open System Settings") {
                        if let url = AudioCapturePermission.settingsURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    Button("Allow Access…") {
                        Task {
                            await model.requestPermission()
                            model.completeOnboarding()
                        }
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Inline form for saving the current mix as a profile.
struct SaveProfileView: View {
    let model: MixerModel
    @Binding var isPresented: Bool

    @State private var name = ""
    @State private var includeOutputDevice = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save Current Mix")
                .font(.subheadline.weight(.semibold))
            TextField("Profile Name, e.g. Work", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(save)
            Toggle("Also switch to \(model.output.deviceName)", isOn: $includeOutputDevice)
                .toggleStyle(.checkbox)
                .controlSize(.small)
            if model.profiles
                .contains(where: { $0.name.localizedCaseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }) {
                Text("This replaces the existing profile with the same name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.small)
        }
        .onAppear { isNameFocused = true }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.saveProfile(named: name, includeOutputDevice: includeOutputDevice)
        isPresented = false
    }
}
