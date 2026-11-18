import SwiftUI

/// The panel that opens when you click the menu bar icon.
struct MixerPanelView: View {
    let model: MixerModel

    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            footer
        }
        .padding(14)
        .frame(width: 340)
        .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.1), value: model.visibleApps.map(\.id))
        .animation(reduceMotion ? nil : .default, value: model.canControlApps)
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
                ForEach(apps) { item in
                    AppRowView(item: item, model: model)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
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

            Button {
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
