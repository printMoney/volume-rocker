import SwiftUI

/// Output or input section of the panel: current device, volume slider, mute button, and an expandable
/// list of devices to switch to with one click, like Control Center's Sound module.
struct DeviceSectionView: View {
    let controller: DefaultDeviceController
    let devices: [AudioDevice]
    let onSelect: (AudioDevice) -> Void

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOutput: Bool {
        controller.direction == .output
    }

    private var title: Text {
        isOutput ? Text("Output") : Text("Input")
    }

    private var muteSymbol: String {
        if isOutput {
            return VolumeSymbol.name(volume: controller.volume, isMuted: controller.isMuted)
        }
        return controller.isMuted || controller.volume <= 0.001 ? "mic.slash.fill" : "mic.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            HStack(spacing: 8) {
                MuteButton(
                    isMuted: controller.isMuted,
                    symbol: muteSymbol,
                    label: title,
                    action: { controller.setMuted(!controller.isMuted) }
                )
                .disabled(!controller.hasMuteControl)

                Slider(
                    value: Binding(get: { Double(controller.volume) }, set: { controller.setVolume(Float($0)) }),
                    in: 0 ... 1
                ) {
                    isOutput ? Text("Output Volume") : Text("Input Volume")
                }
                .labelsHidden()
                .accessibilityValue(Text(controller.volume, format: .percent.precision(.fractionLength(0))))
                .disabled(!controller.hasVolumeControl)
            }

            if !controller.hasVolumeControl, controller.isAvailable {
                Text("This device’s volume can’t be changed from the Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(devices) { device in
                        DeviceRow(
                            device: device,
                            direction: controller.direction,
                            isSelected: device.id == controller.deviceID,
                            action: { onSelect(device) }
                        )
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    title
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(controller.deviceName.isEmpty ? String(localized: "No Device") : controller.deviceName)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOutput ? Text("Output device") : Text("Input device"))
        .accessibilityValue(Text(controller.deviceName))
        .accessibilityHint(isExpanded ? Text("Hides the device list") : Text("Shows devices you can switch to"))
        .help(isOutput ? Text("Choose output device") : Text("Choose input device"))
    }
}

/// One device in the list: icon in a circle (filled with the accent color when selected) and name.
struct DeviceRow: View {
    let device: AudioDevice
    let direction: AudioDirection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: device.symbolName(for: direction))
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(
                        Circle().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    )
                Text(device.name)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(device.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
