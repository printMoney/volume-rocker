import AppKit
import SwiftUI

/// Shows the SwiftUI mixer in a floating panel below the menu bar icon, like Control Center's modules.
///
/// The panel closes on Escape, when clicking anywhere else, or when clicking the icon again. It can become
/// the key window (so sliders work with the keyboard and the profile name field accepts typing) without
/// bringing the whole app to the front.
@MainActor
final class MixerPanelController {
    /// The view the panel hangs below (the menu bar button).
    var anchor: (() -> NSView?)?
    var onVisibilityChange: ((Bool) -> Void)?

    private let model: MixerModel
    private var panel: MixerPanel?
    private var outsideClickMonitor: Any?
    private var resizeObserver: (any NSObjectProtocol)?

    init(model: MixerModel) {
        self.model = model
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    /// Builds the panel ahead of time, so even the first click opens it instantly (~25 ms instead of ~125 ms).
    func prepare() {
        guard panel == nil else { return }
        let panel = makePanel()
        panel.contentView?.layoutSubtreeIfNeeded()
        self.panel = panel
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        // VoiceOver only moves into windows of the frontmost app, so bring the app forward for VoiceOver users.
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSApp.activate()
        }
        panel.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)

        // Close when the user clicks into another app or the desktop.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
        onVisibilityChange?(false)
    }

    private func makePanel() -> MixerPanel {
        let content = MixerPanelView(model: model, onRequestClose: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]

        let panel = MixerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.onCancel = { [weak self] in self?.close() }
        panel.contentView = Self.background(containing: hosting)
        panel.setAccessibilityLabel(String(localized: "Volume Rocker Mixer"))

        // Keep the panel's top edge under the menu bar icon when its content grows or shrinks.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.position(panel)
            }
        }
        return panel
    }

    /// Liquid Glass on macOS 26 and later; the frosted popover material on macOS 15.
    /// With Reduce Transparency on, macOS makes both opaque automatically.
    private static func background(containing content: NSView) -> NSView {
        let cornerRadius: CGFloat = 16
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            content.topAnchor.constraint(equalTo: effect.topAnchor),
            content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    /// Places the panel just below the icon, centered on it, kept fully on screen.
    private func position(_ panel: NSPanel) {
        guard let button = anchor?(), let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main
        else { return }
        let iconFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        let visible = screen.visibleFrame
        var x = iconFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = iconFrame.minY - 6 - size.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// A borderless panel that can take keyboard focus and closes on Escape.
final class MixerPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }
}
