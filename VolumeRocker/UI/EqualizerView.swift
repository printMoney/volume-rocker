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

/// A vertical slider for one EQ band, with its frequency underneath.
private struct BandSlider: View {
    let frequency: Double
    @Binding var gain: Float

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                Slider(
                    value: Binding(get: { Double(gain) }, set: { gain = Float($0) }),
                    in: Double(Equalizer.gainRange.lowerBound) ... Double(Equalizer.gainRange.upperBound)
                ) {
                    Text("\(Equalizer.label(for: frequency)) Hz")
                }
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: geometry.size.height)
                .rotationEffect(.degrees(-90))
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            Text(Equalizer.label(for: frequency))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Equalizer.label(for: frequency)) hertz"))
        .accessibilityValue(Text("\(gain, format: .number.precision(.fractionLength(1)).sign(strategy: .always())) decibels"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: gain = min(Equalizer.gainRange.upperBound, gain + 1)
            case .decrement: gain = max(Equalizer.gainRange.lowerBound, gain - 1)
            @unknown default: break
            }
        }
        .help(Text("\(Equalizer.label(for: frequency)) Hz: \(gain, format: .number.precision(.fractionLength(1))) dB"))
    }
}
