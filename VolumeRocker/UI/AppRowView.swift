import SwiftUI

/// One app in the mixer: icon, name, volume slider, mute button, EQ, output routing and live level meter.
struct AppRowView: View {
    let item: AppAudioItem
    let model: MixerModel

    @State private var showsEqualizer = false
    @State private var showsRouting = false

    private var percentText: String {
        item.isMuted ? String(localized: "Muted") : item.volume.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                header

                HStack(spacing: 8) {
                    MuteButton(
                        isMuted: item.isMuted,
                        symbol: VolumeSymbol.name(volume: min(item.volume, 1), isMuted: item.isMuted),
                        label: Text(item.name),
                        action: { model.toggleMute(item) }
                    )

                    Slider(
                        value: Binding(get: { Double(item.volume) }, set: { model.setVolume(Float($0), for: item) }),
                        in: 0 ... Double(model.maxAppVolume)
                    ) {
                        Text("\(item.name) Volume")
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityValue(Text(percentText))
                }

                if item.isPlaying {
                    LevelMeterView(meter: item.meter)
                        .padding(.leading, 26)
                }
            }
        }
        .opacity(item.isPlaying ? 1 : 0.65)
        .contextMenu { contextMenu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(item.name))
        .accessibilityValue(item.isPlaying ? Text("Playing") : Text("Quiet"))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let device = model.routedDevice(of: item) {
                    Label(device.name, systemImage: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityLabel(Text("Plays on \(device.name)"))
                }
            }
            Spacer(minLength: 4)

            Button {
                showsEqualizer.toggle()
            } label: {
                Image(systemName: "slider.vertical.3")
                    .foregroundStyle(item.hasEqualizer ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .help(Text("Equalizer"))
            .accessibilityLabel(Text("Equalizer for \(item.name)"))
            .accessibilityValue(item.hasEqualizer ? Text("On") : Text("Off"))
            .popover(isPresented: $showsEqualizer, arrowEdge: .trailing) {
                EqualizerView(item: item, model: model)
            }

            Button {
                showsRouting.toggle()
            } label: {
                Image(systemName: "hifispeaker")
                    .foregroundStyle(item.routedDeviceUID != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showsRouting, arrowEdge: .trailing) {
                RoutingView(item: item, model: model) { showsRouting = false }
            }
            .help(Text("Output Device"))
            .accessibilityLabel(Text("Output device for \(item.name)"))

            Text(percentText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(item.volume > 1 && !item.isMuted ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .frame(minWidth: 34, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var routingMenu: some View {
        Picker(selection: Binding(
            get: { item.routedDeviceUID },
            set: { model.route(item, to: $0) }
        )) {
            Text("Same as App").tag(String?.none)
            Divider()
            ForEach(model.devices.outputs) { device in
                Label(device.name, systemImage: device.symbolName(for: .output)).tag(Optional(device.uid))
            }
        } label: {
            Text("Play \(item.name) On")
        }
        .pickerStyle(.inline)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(item.isMuted ? "Unmute" : "Mute") { model.toggleMute(item) }
        Button("Equalizer…") { showsEqualizer = true }
        Menu("Output Device") { routingMenu }
        Divider()
        Button("Reset to 100%, No EQ") { model.reset(item) }
    }
}

/// Popover for choosing which device an app plays on.
struct RoutingView: View {
    let item: AppAudioItem
    let model: MixerModel
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Play \(item.name) On")
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Button {
                model.route(item, to: nil)
                onDone()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(item.routedDeviceUID == nil ? Color.white : Color.primary)
                        .background(Circle().fill(
                            item.routedDeviceUID == nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)
                        ))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Same as App")
                        Text("Wherever \(item.name) plays by itself")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(item.routedDeviceUID == nil ? .isSelected : [])

            Divider()

            ForEach(model.devices.outputs) { device in
                DeviceRow(
                    device: device,
                    direction: .output,
                    isSelected: device.uid == item.routedDeviceUID,
                    action: {
                        model.route(item, to: device.uid)
                        onDone()
                    }
                )
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
