import SwiftUI

/// The panel that opens when you click the menu bar icon.
/// Phase 0 shows only the frame: header, empty state and footer. App rows arrive in Phase 1.
struct MixerPanelView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volume Rocker")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ContentUnavailableView {
                Label("No Apps Playing Audio", systemImage: "speaker.slash")
            } description: {
                Text("Apps appear here as soon as they start playing sound.")
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Divider()

            HStack {
                Button("Settings…") {
                    NSApp.activate()
                    openSettings()
                }
                .keyboardShortcut(",")

                Spacer()

                Button("Quit Volume Rocker") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }
}

#Preview {
    MixerPanelView()
}
