import AppKit
import SwiftUI
import Testing
@testable import VolumeRocker

/// Opens the real mixer panel under a stand-in menu bar icon and checks that the window always fits its
/// content and stays fully on screen below the menu bar, also when the content grows while it is open.
@MainActor
@Suite(.needsInteractiveSession)
struct PanelLayoutTests {
    private func previewItem(_ name: String) -> AppAudioItem {
        let item = AppAudioItem(
            app: ResolvedApp(id: "test.\(name)", name: name, bundlePath: nil, isRegularApp: true),
            setting: .default
        )
        item.setPlaying(true, at: Date())
        return item
    }

    private func settle() async throws {
        for _ in 0 ..< 10 {
            try await Task.sleep(for: .milliseconds(30))
            NSApp.windows.forEach { $0.contentView?.layoutSubtreeIfNeeded() }
        }
    }

    @Test func panelFitsContentAndStaysBelowMenuBar() async throws {
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let model = try MixerModel(defaults: #require(UserDefaults(suiteName: "panel.\(UUID())")))
        model.completeOnboarding()
        model.output.setPreview(deviceName: "Speakers", volume: 0.5)
        model.input.setPreview(deviceName: "Microphone", volume: 0.5)
        model.apps = [previewItem("One")]
        model.devices.start() // the Mac's real devices, so expanding the device list adds real rows

        // A stand-in for the menu bar icon, placed in the menu bar area at the top right.
        let iconWindow = NSWindow(
            contentRect: NSRect(x: visible.maxX - 200, y: visible.maxY, width: 30, height: screen.frame.maxY - visible.maxY),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        let icon = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: screen.frame.maxY - visible.maxY))
        iconWindow.contentView = icon
        iconWindow.orderFront(nil)
        defer { iconWindow.orderOut(nil) }

        let controller = MixerPanelController(model: model)
        controller.anchor = { icon }
        controller.show()
        defer { controller.close() }
        try await settle()

        func check(_ stage: String) throws {
            let panel = try #require(controller.panel)
            let content = try #require(controller.contentSize)
            #expect(
                abs(panel.frame.height - ceil(content.height)) < 1,
                "\(stage): window \(panel.frame.height) vs content \(content.height)"
            )
            #expect(panel.frame.maxY <= visible.maxY + 0.5, "\(stage): top \(panel.frame.maxY) above menu bar \(visible.maxY)")
            #expect(panel.frame.minY >= visible.minY - 0.5, "\(stage): bottom \(panel.frame.minY) below screen \(visible.minY)")
        }
        try check("small")

        // Grow the content a lot while the panel is open.
        model.apps = (1 ... 12).map { previewItem("App \($0)") }
        try await settle()
        try check("grown")

        model.apps = [previewItem("One")]
        try await settle()
        try check("shrunk")

        // Click the "Output" header to expand the device list (animated), like a user would.
        let panel = try #require(controller.panel)
        let before = panel.frame.height
        try clickHeader(of: panel)
        try await settle()
        try await Task.sleep(for: .milliseconds(500))
        try await settle()
        #expect(panel.frame.height > before, "expanding the device list should make the panel taller")
        try check("expanded")
    }

    private func clickHeader(of panel: NSPanel) throws {
        let headerPoint = NSPoint(x: panel.frame.width / 2, y: panel.frame.height - 32)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: headerPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
            panel.sendEvent(event)
        }
    }

    @Test func appListShrinksWhenScreenSpaceIsTight() async throws {
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let model = try MixerModel(defaults: #require(UserDefaults(suiteName: "panel.\(UUID())")))
        model.completeOnboarding()
        model.output.setPreview(deviceName: "Speakers", volume: 0.5)
        model.input.setPreview(deviceName: "Microphone", volume: 0.5)
        model.apps = (1 ... 12).map { previewItem("App \($0)") }

        // Only ~400 points of room below the icon.
        let iconWindow = NSWindow(
            contentRect: NSRect(x: visible.maxX - 200, y: visible.minY + 410, width: 30, height: 24),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        let icon = NSButton(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
        iconWindow.contentView = icon
        iconWindow.orderFront(nil)
        defer { iconWindow.orderOut(nil) }

        let controller = MixerPanelController(model: model)
        controller.anchor = { icon }
        controller.show()
        defer { controller.close() }
        try await settle()

        let panel = try #require(controller.panel)
        let content = try #require(controller.contentSize)
        #expect(panel.frame.minY >= visible.minY - 0.5, "bottom \(panel.frame.minY) below screen \(visible.minY)")
        #expect(panel.frame.maxY <= visible.minY + 410, "top \(panel.frame.maxY) above the icon")
        #expect(abs(panel.frame.height - ceil(content.height)) < 1, "window \(panel.frame.height) vs content \(content.height)")
    }
}
