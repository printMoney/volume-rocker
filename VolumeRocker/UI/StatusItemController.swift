import AppKit

/// Extra menu bar icon behavior that SwiftUI's `MenuBarExtra` doesn't offer:
/// scroll over the icon to change the output volume, and Option-click (or right-click) it for a quick
/// device menu. It also lets keyboard shortcuts open the panel.
///
/// `MenuBarExtra` creates the status item itself, so events are recognized by the window they arrive in:
/// the menu bar icon lives in an `NSStatusBarWindow` that belongs to this app.
@MainActor
final class StatusItemController {
    private let model: MixerModel
    private var monitor: Any?

    init(model: MixerModel) {
        self.model = model
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// Opens or closes the mixer panel, as if the menu bar icon was clicked.
    func togglePanel() {
        statusButton?.performClick(nil)
    }

    // MARK: Events

    private func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window, Self.isStatusBarWindow(window) else { return false }
        switch event.type {
        case .scrollWheel:
            let delta = Self.volumeDelta(
                scrollingDeltaY: Float(event.scrollingDeltaY),
                isPrecise: event.hasPreciseScrollingDeltas,
                isInverted: event.isDirectionInvertedFromDevice
            )
            guard delta != 0, model.output.hasVolumeControl else { return true }
            model.output.setVolume(model.output.volume + delta)
            return true
        case .leftMouseDown where event.modifierFlags.contains(.option), .rightMouseDown:
            showDeviceMenu(below: window)
            return true
        default:
            return false
        }
    }

    /// Volume change for a scroll event. Physically scrolling up (or swiping up) makes it louder, whatever the
    /// "natural scrolling" setting. Trackpads send many small precise deltas, mouse wheels a few coarse ones.
    nonisolated static func volumeDelta(scrollingDeltaY: Float, isPrecise: Bool, isInverted: Bool) -> Float {
        let physical = isInverted ? -scrollingDeltaY : scrollingDeltaY
        let scale: Float = isPrecise ? 0.004 : 0.03
        return max(-0.25, min(0.25, physical * scale))
    }

    nonisolated static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        window.className.contains("NSStatusBarWindow")
    }

    private var statusButton: NSButton? {
        NSApp.windows.first(where: Self.isStatusBarWindow)?.contentView.flatMap(Self.findButton)
    }

    private static func findButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton {
            return button
        }
        for subview in view.subviews {
            if let button = findButton(in: subview) {
                return button
            }
        }
        return nil
    }

    // MARK: Device menu

    private func showDeviceMenu(below window: NSWindow) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addSection(to: menu, title: String(localized: "Output"), devices: model.devices.outputs, direction: .output)
        if model.showInputControls, !model.devices.inputs.isEmpty {
            menu.addItem(.separator())
            addSection(to: menu, title: String(localized: "Input"), devices: model.devices.inputs, direction: .input)
        }
        if !model.profiles.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: String(localized: "Profiles")))
            for profile in model.profiles {
                let item = ClosureMenuItem(title: profile.name) { [model] in model.applyProfile(profile) }
                item.state = profile.id == model.activeProfileID ? .on : .off
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: String(localized: "Open Mixer")) { [weak self] in self?.togglePanel() })

        let origin = NSPoint(x: window.frame.minX, y: window.frame.minY - 4)
        menu.popUp(positioning: nil, at: origin, in: nil)
    }

    private func addSection(to menu: NSMenu, title: String, devices: [AudioDevice], direction: AudioDirection) {
        menu.addItem(.sectionHeader(title: title))
        let currentID = direction == .output ? model.output.deviceID : model.input.deviceID
        for device in devices {
            let item = ClosureMenuItem(title: device.name) { [model] in model.select(device, for: direction) }
            item.image = NSImage(systemSymbolName: device.symbolName(for: direction), accessibilityDescription: nil)
            item.state = device.id == currentID ? .on : .off
            menu.addItem(item)
        }
    }
}

/// A menu item that runs a closure when chosen.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
