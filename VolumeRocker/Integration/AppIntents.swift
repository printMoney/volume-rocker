import AppIntents
import Foundation

// Actions for the Shortcuts app and Siri: set an app's volume, mute an app, switch the output device,
// set the output volume, and apply a profile. They run inside Volume Rocker, launching it if needed.

// MARK: Entities

/// An app whose volume Volume Rocker can control.
struct AppAudioEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static let defaultQuery = AppAudioQuery()

    /// The app's bundle ID.
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct AppAudioQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [AppAudioEntity] {
        let model = try await requireModel()
        return identifiers.map { AppAudioEntity(id: $0, name: model.appName(forID: $0)) }
    }

    @MainActor
    func suggestedEntities() async throws -> [AppAudioEntity] {
        let model = try await requireModel()
        return model.knownAppIDs.map { AppAudioEntity(id: $0, name: model.appName(forID: $0)) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [AppAudioEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

/// An output device.
struct OutputDeviceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Output Device"
    static let defaultQuery = OutputDeviceQuery()

    /// The device's UID, which stays the same across reconnects and restarts.
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct OutputDeviceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [OutputDeviceEntity] {
        AudioDeviceList.currentOutputs().filter { identifiers.contains($0.uid) }.map(OutputDeviceEntity.init)
    }

    func suggestedEntities() async throws -> [OutputDeviceEntity] {
        AudioDeviceList.currentOutputs().map(OutputDeviceEntity.init)
    }

    func entities(matching string: String) async throws -> [OutputDeviceEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

extension OutputDeviceEntity {
    init(_ device: AudioDevice) {
        self.init(id: device.uid, name: device.name)
    }
}

/// A saved profile.
struct ProfileEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Profile"
    static let defaultQuery = ProfileQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProfileQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ProfileEntity] {
        ProfileStore().profiles.filter { identifiers.contains($0.id) }.map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ProfileEntity] {
        ProfileStore().profiles.map { ProfileEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ProfileEntity] {
        try await suggestedEntities().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

enum MuteAction: String, AppEnum {
    case mute, unmute, toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mute Action"
    static let caseDisplayRepresentations: [MuteAction: DisplayRepresentation] = [
        .mute: "Mute",
        .unmute: "Unmute",
        .toggle: "Toggle",
    ]

    var mutedValue: Bool? {
        switch self {
        case .mute: true
        case .unmute: false
        case .toggle: nil
        }
    }
}

// MARK: Intents

struct SetAppVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set App Volume"
    static let description = IntentDescription("Sets the volume of one app, from 0% to 100% (or up to 200% with boost).")

    @Parameter(title: "App")
    var app: AppAudioEntity

    @Parameter(title: "Volume", default: 50, inclusiveRange: (0, 200))
    var volume: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set \(\.$app) volume to \(\.$volume)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try await requireModel()
        model.setVolume(Float(volume) / 100, forAppID: app.id)
        return .result()
    }
}

struct MuteAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute App"
    static let description = IntentDescription("Mutes, unmutes or toggles one app’s sound.")

    @Parameter(title: "App")
    var app: AppAudioEntity

    @Parameter(title: "Action", default: .toggle)
    var action: MuteAction

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) \(\.$app)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try await requireModel()
        model.setMuted(action.mutedValue, forAppID: app.id)
        return .result()
    }
}

struct SwitchOutputDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Output Device"
    static let description = IntentDescription("Plays the Mac’s sound through another device.")

    @Parameter(title: "Device")
    var device: OutputDeviceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Switch output to \(\.$device)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let target = AudioDeviceList.currentOutputs().first(where: { $0.uid == device.id }) else {
            throw $device.needsValueError("That device isn’t connected. Which device should play the sound?")
        }
        AudioDeviceList.makeDefault(target, for: .output)
        return .result()
    }
}

struct SetOutputVolumeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Output Volume"
    static let description = IntentDescription("Sets the Mac’s overall volume.")

    @Parameter(title: "Volume", default: 50, inclusiveRange: (0, 100))
    var volume: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set output volume to \(\.$volume)%")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try await requireModel()
        model.output.setVolume(Float(volume) / 100)
        return .result()
    }
}

struct ApplyProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Profile"
    static let description = IntentDescription("Applies a saved mix, such as Work or Movie.")

    @Parameter(title: "Profile")
    var profile: ProfileEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apply \(\.$profile)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = try await requireModel()
        guard let saved = model.profiles.first(where: { $0.id == profile.id }) else {
            throw $profile.needsValueError("That profile no longer exists. Which profile should be applied?")
        }
        model.applyProfile(saved)
        return .result()
    }
}

// MARK: Siri phrases

struct VolumeRockerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyProfileIntent(),
            phrases: [
                "Apply \(\.$profile) in \(.applicationName)",
                "Switch \(.applicationName) to \(\.$profile)",
            ],
            shortTitle: "Apply Profile",
            systemImageName: "square.stack.3d.up"
        )
        AppShortcut(
            intent: MuteAppIntent(),
            phrases: [
                "Mute \(\.$app) with \(.applicationName)",
                "Toggle \(\.$app) sound in \(.applicationName)",
            ],
            shortTitle: "Mute App",
            systemImageName: "speaker.slash"
        )
        AppShortcut(
            intent: SwitchOutputDeviceIntent(),
            phrases: [
                "Switch \(.applicationName) output to \(\.$device)",
                "Play sound on \(\.$device) with \(.applicationName)",
            ],
            shortTitle: "Switch Output",
            systemImageName: "hifispeaker"
        )
        AppShortcut(
            intent: SetAppVolumeIntent(),
            phrases: ["Set app volume with \(.applicationName)"],
            shortTitle: "Set App Volume",
            systemImageName: "slider.horizontal.3"
        )
    }
}

// MARK: Helpers

/// The running model. When Shortcuts launches the app to run an action, launch may still be in progress,
/// so wait briefly for it.
@MainActor
func requireModel() async throws -> MixerModel {
    for _ in 0 ..< 20 {
        if let model = AppServices.model {
            return model
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw AppServicesError.notRunning
}
