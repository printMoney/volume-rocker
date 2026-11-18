import Foundation

/// A saved mix, such as "Work", "Gaming" or "Movie": each app's settings, and optionally the output device.
struct MixProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var apps: [String: AppVolumeSetting]
    /// Output device to switch to when the profile is applied, if it is connected.
    var outputDeviceUID: String?
    var outputDeviceName: String?
}

/// Saves profiles and remembers which one was applied last.
@MainActor
final class ProfileStore {
    static let storageKey = "profiles"
    static let activeKey = "activeProfileID"

    private let defaults: UserDefaults
    private(set) var profiles: [MixProfile]
    private(set) var activeProfileID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([MixProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = []
        }
        activeProfileID = defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
        if let activeProfileID, !profiles.contains(where: { $0.id == activeProfileID }) {
            self.activeProfileID = nil
        }
    }

    /// Saves a profile. A profile with the same name (ignoring case) is replaced, so "Save as Work" updates Work.
    @discardableResult
    func save(_ profile: MixProfile) -> MixProfile {
        var profile = profile
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = profiles.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(profile.name) == .orderedSame }) {
            profile.id = profiles[index].id
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
        return profile
    }

    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = name
        persist()
    }

    func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            setActive(nil)
        }
        persist()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func setActive(_ id: UUID?) {
        activeProfileID = id
        defaults.set(id?.uuidString, forKey: Self.activeKey)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
