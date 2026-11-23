import SwiftUI

/// The per-app 10-band equalizer, shown in a popover from the app's row.
struct EqualizerView: View {
    let item: AppAudioItem
    let model: MixerModel

    private var gains: [Float] {
        item.equalizer ?? Equalizer.flat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Equalizer: \(item.name)")
                    .font(.headline)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                presetMenu
            }

            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(Equalizer.frequencies.enumerated()), id: \.offset) { index, frequency in
                    BandSlider(
                        frequency: frequency,
                        gain: Binding(get: { gains[index] }, set: { setGain($0, at: index) })
                    )
                }
            }
            .frame(height: 170)

            HStack {
                Text("+12 dB … −12 dB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { model.setEqualizer(nil, for: item) }
                    .disabled(!item.hasEqualizer)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 400)
    }

    private var presetMenu: some View {
        Menu {
            ForEach(Equalizer.presets) { preset in
                Button(String(localized: preset.name)) { model.setEqualizer(preset.gains, for: item) }
            }
        } label: {
            Text(Equalizer.preset(matching: item.equalizer).map { String(localized: $0.name) } ?? String(localized: "Custom"))
        }
        .fixedSize()
        .controlSize(.small)
        .accessibilityLabel(Text("Preset"))
    }

    private func setGain(_ gain: Float, at index: Int) {
        var updated = gains
        // Snap to 0 dB near the middle, so returning a band to neutral is easy.
        updated[index] = abs(gain) < 0.4 ? 0 : (gain * 2).rounded() / 2
        model.setEqualizer(updated, for: item)
    }
}

/// One EQ band: a native vertical slider with its frequency underneath.
///
/// It uses AppKit's real vertical `NSSlider`. (A rotated SwiftUI `Slider` only *looks* vertical: its click
/// area stays horizontal, so every click jumped to the maximum.)
private struct BandSlider: View {
    let frequency: Double
    @Binding var gain: Float

    var body: some View {
        VStack(spacing: 4) {
            VerticalSlider(
                value: $gain,
                range: Equalizer.gainRange,
                accessibilityLabel: String(localized: "\(Equalizer.label(for: frequency)) hertz")
            )
            Text(Equalizer.label(for: frequency))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .help(Text("\(Equalizer.label(for: frequency)) Hz: \(gain, format: .number.precision(.fractionLength(1))) dB"))
    }
}

/// A native vertical `NSSlider` for SwiftUI. VoiceOver reads it as "31 hertz, plus 6 decibels", and it
/// works with the arrow keys and with Full Keyboard Access.
struct VerticalSlider: NSViewRepresentable {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> DecibelSlider {
        let slider = DecibelSlider()
        slider.isVertical = true
        slider.minValue = Double(range.lowerBound)
        slider.maxValue = Double(range.upperBound)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.setAccessibilityLabel(accessibilityLabel)
        slider.doubleValue = Double(value)
        return slider
    }

    func updateNSView(_ slider: DecibelSlider, context: Context) {
        context.coordinator.value = $value
        // Don't fight the user's drag: only push outside changes (presets, Reset) into the slider.
        if abs(slider.doubleValue - Double(value)) > 0.001, NSEvent.pressedMouseButtons == 0 {
            slider.doubleValue = Double(value)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Float>

        init(value: Binding<Float>) {
            self.value = value
        }

        @objc func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = Float(sender.doubleValue)
        }
    }
}

/// Reports its value to VoiceOver in decibels.
final class DecibelSlider: NSSlider {
    override func accessibilityValueDescription() -> String? {
        let decibels = Float(doubleValue).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
        return String(localized: "\(decibels) decibels")
    }
}
