import AppKit
import Observation

/// The menu bar icon. It is an AppKit `NSStatusItem` rather than SwiftUI's `MenuBarExtra`, because
/// `MenuBarExtra` can't be opened by the app itself (needed for keyboard shortcuts and Control Center) and
/// offers no scroll or Option-click handling.
///
/// - Click: open or close the mixer panel.
/// - Scroll: change the output volume.
/// - Option-click or right-click: quick menu of devices and profiles.
@MainActor
final class StatusItemController {
    private let model: MixerModel
    private let panel: MixerPanelController
    private var statusItem: NSStatusItem?
    private var scrollMonitor: Any?

    init(model: MixerModel, panel: MixerPanelController) {
        self.model = model
        self.panel = panel
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(buttonPressed)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.setAccessibilityLabel(String(localized: "Volume Rocker"))
            button.setAccessibilityHelp(String(localized: "Click for the mixer. Option-click for devices."))
        }
        statusItem = item
        panel.anchor = { [weak self] in self?.statusItem?.button }
        panel.onVisibilityChange = { [weak self] visible in self?.statusItem?.button?.highlight(visible) }
        updateIcon()

        // Scrolling over the icon: a local monitor sees events for this app's windows, including the icon's.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleScroll(event) ?? false }
            return handled ? nil : event
        }
    }

    func stop() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
        scrollMonitor = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    /// Opens or closes the mixer panel (also used by keyboard shortcuts and Control Center).
    func togglePanel() {
        panel.toggle()
    }

    // MARK: Events

    @objc private func buttonPressed() {
        guard let event = NSApp.currentEvent else { return panel.toggle() }
        if event.type == .rightMouseDown || event.modifierFlags.contains(.option) {
            panel.close()
            showDeviceMenu()
        } else {
            panel.toggle()
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button, event.window === button.window else { return false }
        let delta = Self.volumeDelta(
            scrollingDeltaY: Float(event.scrollingDeltaY),
            isPrecise: event.hasPreciseScrollingDeltas,
            isInverted: event.isDirectionInvertedFromDevice
        )
        if delta != 0, model.output.hasVolumeControl {
            model.output.setVolume(model.output.volume + delta)
        }
        return true
    }

    /// Keeps the icon in sync with the output volume and mute, using Observation.
    private func updateIcon() {
        withObservationTracking {
            let output = model.output
            let symbol = VolumeSymbol.name(volume: output.volume, isMuted: output.isMuted)
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            image?.isTemplate = true
            statusItem?.button?.image = image
            statusItem?.button?.setAccessibilityValue(
                output.isMuted ? String(localized: "Muted") : output.volume.formatted(.percent.precision(.fractionLength(0)))
            )
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    /// Volume change for a scroll event. Physically scrolling up (or swiping up) makes it louder, whatever the
    /// "natural scrolling" setting. Trackpads send many small precise deltas, mouse wheels a few coarse ones.
    nonisolated static func volumeDelta(scrollingDeltaY: Float, isPrecise: Bool, isInverted: Bool) -> Float {
        let physical = isInverted ? -scrollingDeltaY : scrollingDeltaY
        let scale: Float = isPrecise ? 0.004 : 0.03
        return max(-0.25, min(0.25, physical * scale))
    }

    // MARK: Device menu

    private func showDeviceMenu() {
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

        // Shows the menu below the icon, like any menu bar menu.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
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
