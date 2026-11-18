import AppKit
import SwiftUI
import Testing
@testable import VolumeRocker

/// Renders the screenshots used in README.md from the real SwiftUI views with example apps.
/// Skipped in normal test runs; run Scripts/render-readme-images.sh to update the images.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RENDER_README_IMAGES"] != nil))
struct ReadmeImages {
    private let outputDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/images")

    private func item(_ id: String, _ name: String, _ path: String, _ setting: AppVolumeSetting, level: Float) -> AppAudioItem {
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let item = AppAudioItem(
            app: ResolvedApp(id: id, name: name, bundlePath: resolvedPath, isRegularApp: true),
            setting: setting
        )
        item.setPlaying(true, at: Date())
        // Feed a little audio through the real render code so the meter shows a level.
        let input = TestBufferList([(2, 256)]) { _ in level }
        let output = TestBufferList([(2, 256)])
        render(item.renderState, input: input, output: output)
        return item
    }

    private func makeModel() -> MixerModel {
        let model = MixerModel(defaults: UserDefaults(suiteName: "readme.\(UUID())")!)
        model.allowBoost = true
        model.completeOnboarding()
        model.output.setPreview(deviceName: "MacBook Pro Speakers", volume: 0.62)
        model.input.setPreview(deviceName: "MacBook Pro Microphone", volume: 0.7)
        model.apps = [
            item("com.apple.FaceTime", "FaceTime", "/System/Applications/FaceTime.app", .default, level: 0.25),
            item(
                "com.apple.Music",
                "Music",
                "/System/Applications/Music.app",
                AppVolumeSetting(volume: 0.55, equalizer: Equalizer.presets[1].gains),
                level: 0.5
            ),
            item("com.apple.podcasts", "Podcasts", "/System/Applications/Podcasts.app", AppVolumeSetting(volume: 1.4), level: 0.12),
            item("com.apple.Safari", "Safari", "/Applications/Safari.app", AppVolumeSetting(volume: 0.3, isMuted: true), level: 0),
        ]
        return model
    }

    private func save(_ view: some View, size: CGSize, name: String, dark: Bool) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = CGRect(origin: .zero, size: size)
        // An active, key window (placed off screen) so controls draw in their normal accent colors.
        let window = MixerPanel(
            contentRect: host.frame.offsetBy(dx: -20000, dy: -20000),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.contentView = host
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        host.display()
        // Render at 2× for sharp images on Retina screens.
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try data.write(to: outputDirectory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
    }

    @Test func renderImages() throws {
        let model = makeModel()
        for dark in [false, true] {
            let hero = ZStack {
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.10, green: 0.12, blue: 0.24), Color(red: 0.25, green: 0.12, blue: 0.32)]
                        : [Color(red: 0.62, green: 0.72, blue: 0.98), Color(red: 0.86, green: 0.70, blue: 0.95)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                MixerPanelView(model: model)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
            }
            try save(hero, size: CGSize(width: 480, height: 540), name: "hero", dark: dark)

            let music = try #require(model.apps.first { $0.id == "com.apple.Music" })
            let equalizer = EqualizerView(item: music, model: model)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(24)
            try save(equalizer, size: CGSize(width: 448, height: 300), name: "equalizer", dark: dark)
        }
    }
}
