import SwiftUI

/// One app in the mixer: icon, name, volume slider, mute button and live level meter.
struct AppRowView: View {
    let item: AppAudioItem
    let model: MixerModel

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: item.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(item.isMuted ? String(localized: "Muted") : item.volume.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 8) {
                    MuteButton(
                        isMuted: item.isMuted,
                        volume: item.volume,
                        label: Text(item.name),
                        action: { model.toggleMute(item) }
                    )

                    Slider(
                        value: Binding(get: { Double(item.volume) }, set: { model.setVolume(Float($0), for: item) }),
                        in: 0 ... 1
                    ) {
                        Text("\(item.name) Volume")
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityValue(
                        item.isMuted ? Text("Muted") : Text(item.volume, format: .percent.precision(.fractionLength(0)))
                    )
                }

                if item.isPlaying {
                    LevelMeterView(meter: item.meter)
                        .padding(.leading, 26)
                }
            }
        }
        .opacity(item.isPlaying ? 1 : 0.65)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(item.name))
    }
}

/// A thin live level bar. It redraws about 30 times per second only while visible on screen.
struct LevelMeterView: View {
    let meter: LevelMeter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 10 : 1.0 / 30)) { context in
            let level = CGFloat(meter.level(at: context.date))
            Canvas { graphics, size in
                let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                graphics.fill(track, with: .style(.quaternary))
                let width = max(0, min(size.width, size.width * level))
                guard width > 0 else { return }
                let fill = Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: size.height), cornerRadius: size.height / 2)
                graphics.fill(fill, with: .style(.tint))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
