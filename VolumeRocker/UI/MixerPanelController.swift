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
    private(set) var panel: MixerPanel?
    private var outsideClickMonitor: Any?
    /// When the panel was last closed by a click outside it.
    private var closedByOutsideClickAt: ContinuousClock.Instant?
    /// The content's latest natural size. It can be reported before the panel exists, so it is kept.
    private(set) var contentSize: CGSize?
    private var hosting: NSHostingView<MixerPanelView>?
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
        } else if !Self.wasJustClosed(at: closedByOutsideClickAt, now: .now) {
            show()
        }
    }

    /// A click on the menu bar icon can reach the "click outside" handler first (the menu bar belongs to
    /// another process on recent macOS). That click already closed the panel, so it must not reopen it.
    nonisolated static func wasJustClosed(at closedAt: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
        guard let closedAt else { return false }
        return now - closedAt < .milliseconds(300)
    }

    /// Builds the panel ahead of time, so even the first click opens it instantly (~25 ms instead of ~125 ms).
    func prepare() {
        guard panel == nil else { return }
        let panel = makePanel()
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        applyContentSize()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        applyContentSize()
        position(panel)
        // VoiceOver only moves into windows of the frontmost app, so bring the app forward for VoiceOver users.
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSApp.activate()
        }
        panel.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)

        // Close when the user clicks into another app or the desktop. A click on the menu bar icon is left to
        // the icon, which toggles the panel closed.
        closedByOutsideClickAt = nil
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                guard let self, !self.isOnIcon(location) else { return }
                self.close()
                self.closedByOutsideClickAt = .now
            }
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

    /// Resizes the window to the content's natural size, keeping it anchored under the menu bar icon.
    private func fit(to size: CGSize) {
        contentSize = size
        applyContentSize()
    }

    private func applyContentSize() {
        guard let panel, let size = contentSize, size.width > 0, size.height > 0 else { return }
        layout(panel, contentSize: NSSize(width: ceil(size.width), height: ceil(size.height)))
    }

    private func isOnIcon(_ screenPoint: NSPoint) -> Bool {
        guard let button = anchor?(), let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.insetBy(dx: -2, dy: -2).contains(screenPoint)
    }

    private func makePanel() -> MixerPanel {
        let content = MixerPanelView(
            model: model,
            onRequestClose: { [weak self] in self?.close() },
            onSizeChange: { [weak self] size in self?.fit(to: size) }
        )
        let hosting = NSHostingView(rootView: content)
        self.hosting = hosting
        hosting.sizingOptions = []

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
            content.autoresizingMask = [.width, .height]
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
        layout(panel, contentSize: panel.frame.size)
    }

    /// The screen area the panel may use, and the point its top edge hangs from (centered under the icon).
    private struct Placement {
        let visible: NSRect
        let anchorX: CGFloat
        let top: CGFloat
    }

    private func placement() -> Placement? {
        let iconFrame: NSRect? = anchor?().flatMap { button in
            button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) }
        }
        let screen = NSScreen.screens.first { screen in iconFrame.map { screen.frame.intersects($0) } ?? false }
            ?? NSScreen.main
        guard let screen else { return nil }
        let visible = screen.visibleFrame
        // If macOS reports the icon somewhere off this screen, fall back to the top-right corner.
        guard let iconFrame, screen.frame.intersects(iconFrame) else {
            return Placement(visible: visible, anchorX: visible.maxX - 200, top: visible.maxY - Self.gap)
        }
        // Never start under the menu bar, wherever the icon is reported.
        return Placement(visible: visible, anchorX: iconFrame.midX, top: min(iconFrame.minY, visible.maxY) - Self.gap)
    }

    private static let gap: CGFloat = 6

    /// The tallest the panel may be on its screen.
    private var maxPanelHeight: CGFloat {
        guard let placement = placement() else { return 800 }
        return placement.top - placement.visible.minY - 8
    }

    /// Sets the panel's whole frame in one step: top-anchored under the icon, kept on screen.
    private func layout(_ panel: NSPanel, contentSize: NSSize) {
        guard let placement = placement() else { return }
        let visible = placement.visible
        let height = min(contentSize.height, placement.top - visible.minY - 8)
        var x = placement.anchorX - contentSize.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - contentSize.width - 8)
        let frame = NSRect(x: x, y: placement.top - height, width: contentSize.width, height: height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        let limit = placement.top - visible.minY - 8
        if let hosting, abs(hosting.rootView.maxPanelHeight - limit) > 0.5 {
            hosting.rootView.maxPanelHeight = limit
        }
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
