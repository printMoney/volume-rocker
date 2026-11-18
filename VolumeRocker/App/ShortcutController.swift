import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleMixer = Self("toggleMixer")
    static let toggleOutputMute = Self("toggleOutputMute")
    static let outputVolumeUp = Self("outputVolumeUp")
    static let outputVolumeDown = Self("outputVolumeDown")
    static let nextProfile = Self("nextProfile")

    /// One shortcut per saved profile.
    static func profile(_ id: UUID) -> Self {
        Self("profile.\(id.uuidString)")
    }
}

/// Connects the user's global keyboard shortcuts to actions. The shortcuts themselves are recorded in
/// Settings → Shortcuts and stored by the KeyboardShortcuts package.
@MainActor
final class ShortcutController {
    /// Same step as the Mac's own volume keys (1/16).
    static let volumeStep: Float = 1 / 16

    private let model: MixerModel
    private let statusItem: StatusItemController
    private var registeredProfiles: Set<UUID> = []

    init(model: MixerModel, statusItem: StatusItemController) {
        self.model = model
        self.statusItem = statusItem
    }

    func start() {
        KeyboardShortcuts.onKeyUp(for: .toggleMixer) { [weak self] in
            MainActor.assumeIsolated { self?.statusItem.togglePanel() }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleOutputMute) { [weak self] in
            MainActor.assumeIsolated {
                guard let output = self?.model.output else { return }
                output.setMuted(!output.isMuted)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .outputVolumeUp) { [weak self] in
            MainActor.assumeIsolated { self?.changeVolume(by: Self.volumeStep) }
        }
        KeyboardShortcuts.onKeyDown(for: .outputVolumeDown) { [weak self] in
            MainActor.assumeIsolated { self?.changeVolume(by: -Self.volumeStep) }
        }
        KeyboardShortcuts.onKeyUp(for: .nextProfile) { [weak self] in
            MainActor.assumeIsolated { self?.model.applyNextProfile() }
        }
        refreshProfileShortcuts()
    }

    /// Registers handlers for new profiles and clears shortcuts of deleted ones.
    func refreshProfileShortcuts() {
        let current = Set(model.profiles.map(\.id))
        for removed in registeredProfiles.subtracting(current) {
            KeyboardShortcuts.reset(.profile(removed))
        }
        for added in current.subtracting(registeredProfiles) {
            KeyboardShortcuts.onKeyUp(for: .profile(added)) { [weak self] in
                MainActor.assumeIsolated {
                    guard let model = self?.model, let profile = model.profiles.first(where: { $0.id == added }) else { return }
                    model.applyProfile(profile)
                }
            }
        }
        registeredProfiles = current
    }

    private func changeVolume(by delta: Float) {
        let output = model.output
        guard output.hasVolumeControl else { return }
        output.setVolume(output.volume + delta)
    }
}
