import AppIntents
import AppKit
import CoreAudio
import SwiftUI
import WidgetKit

// Controls for Control Center and the menu bar on macOS 26 and later.
// This extension runs in its own sandboxed process, separate from the app.

@main
struct VolumeRockerControlsBundle: WidgetBundle {
    var body: some Widget {
        OutputMuteControl()
        NextProfileControl()
        OpenMixerControl()
    }
}

// MARK: Mute Sound

struct OutputMuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.printmoney.VolumeRocker.outputMute", provider: Provider()) { isMuted in
            ControlWidgetToggle("Mute Sound", isOn: isMuted, action: SetOutputMutedIntent()) { isOn in
                Label(isOn ? "Muted" : "Sound On", systemImage: isOn ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
        }
        .displayName("Mute Sound")
        .description("Mutes or unmutes the Mac’s sound output.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            OutputMute.isMuted
        }
    }
}

struct SetOutputMutedIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Mute Sound"

    @Parameter(title: "Muted")
    var value: Bool

    func perform() async throws -> some IntentResult {
        OutputMute.set(value)
        return .result()
    }
}

/// Reads and sets the default output device's mute directly through Core Audio.
enum OutputMute {
    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static var defaultOutputDevice: AudioDeviceID {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    static var isMuted: Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        AudioObjectGetPropertyData(defaultOutputDevice, &address, 0, nil, &size, &muted)
        return muted != 0
    }

    static func set(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var address = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        AudioObjectSetPropertyData(defaultOutputDevice, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

// MARK: Requests to the app

/// Asks the running app to act. Sandboxed extensions can post distributed notifications (without data),
/// which the app listens for. If the app isn't running, nothing happens.
enum AppRequest {
    static let nextProfile = Notification.Name("io.github.printmoney.VolumeRocker.nextProfile")
    static let openMixer = Notification.Name("io.github.printmoney.VolumeRocker.openMixer")

    static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

struct NextProfileControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.printmoney.VolumeRocker.nextProfile") {
            ControlWidgetButton(action: NextProfileIntent()) {
                Label("Next Profile", systemImage: "square.stack.3d.up")
            }
        }
        .displayName("Next Volume Profile")
        .description("Switches Volume Rocker to the next saved profile.")
    }
}

struct NextProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Volume Profile"

    func perform() async throws -> some IntentResult {
        AppRequest.post(AppRequest.nextProfile)
        return .result()
    }
}

struct OpenMixerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "io.github.printmoney.VolumeRocker.openMixer") {
            ControlWidgetButton(action: OpenMixerIntent()) {
                Label("Volume Rocker", systemImage: "slider.vertical.3")
            }
        }
        .displayName("Open Volume Rocker")
        .description("Opens the per-app volume mixer.")
    }
}

struct OpenMixerIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Volume Rocker"

    func perform() async throws -> some IntentResult {
        AppRequest.post(AppRequest.openMixer)
        return .result()
    }
}
