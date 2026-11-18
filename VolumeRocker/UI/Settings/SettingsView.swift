import SwiftUI

/// The native Settings window. More tabs (Apps, Devices, Shortcuts, Updates) arrive in Phase 4.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
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
    var body: some View {
        Form {
            Text("General settings will appear here.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
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

#Preview {
    SettingsView()
}
