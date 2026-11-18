# Architecture

This document explains how Volume Rocker changes the volume of individual apps without a virtual audio driver.

## The big picture

macOS 14.4 added **process taps**: a way to capture the audio an app is about to play. Volume Rocker uses them like this:

1. **Tap and mute the original.** For each app that is playing, Volume Rocker creates a private tap (`CATapDescription(stereoMixdownOfProcesses:)` + `AudioHardwareCreateProcessTap`) covering all of that app's processes, with `muteBehavior = .mutedWhenTapped`. The app's sound no longer reaches the speakers directly, but Volume Rocker receives it.
2. **Wrap the device in a private aggregate device.** A private aggregate device (`AudioHardwareCreateAggregateDevice`, `kAudioAggregateDeviceIsPrivateKey = true`) combines the device the app was playing to with the tap. It is invisible to other apps and disappears when Volume Rocker quits.
3. **Process and play.** An IOProc on the aggregate device runs on Core Audio's real-time thread. It reads the app's audio, applies the app's gain (and later EQ and limiting), and writes it to the real device's output. macOS mixes the output of all apps' aggregate devices together.

### Why one aggregate device per app (not per output device)

The original plan was one aggregate device per output device, holding every app's tap. But changing an aggregate device's tap list means stopping and restarting its audio, so every time *any* app started or stopped playing, *all* apps would drop out for a moment. With one small aggregate device per app, apps start and stop independently, and per-app output routing (Phase 3) only needs a different sub-device. The cost is one extra Core Audio IO thread per playing app, which is cheap: each one only copies and scales a buffer with vDSP.

```mermaid
flowchart LR
    subgraph Apps
        A1[Spotify]
        A2[Safari + helpers]
        A3[Zoom]
    end
    A1 -- tap --> T1((Tap))
    A2 -- tap --> T2((Tap))
    A3 -- tap --> T3((Tap))
    T1 --> IO1[Aggregate + IOProc<br/>EQ · gain · limiter · meter]
    T2 --> IO2[Aggregate + IOProc<br/>EQ · gain · limiter · meter]
    T3 --> IO3[Aggregate + IOProc<br/>EQ · gain · limiter · meter]
    IO1 & IO2 & IO3 --> OUT[Output device<br/>Speakers / AirPods / HDMI<br/>macOS mixes the streams]
    UI[Mixer UI<br/>MainActor] -- "Atomic gain<br/>(lock-free)" --> IO1 & IO2 & IO3
    IO1 & IO2 & IO3 -- "Atomic peak levels" --> UI
```

## Modules

| Folder | Responsibility | Thread |
| --- | --- | --- |
| `App/` | Entry point, `MixerModel` (turns state into tap requests), `AppAudioItem` | Main |
| `CoreAudioSupport/` | Typed property reading/writing and listener helpers | Main |
| `ProcessMonitor/` | Watches `kAudioHardwarePropertyProcessObjectList` and each process's `kAudioProcessPropertyIsRunningOutput`; groups helpers (e.g. "Google Chrome Helper") under their parent app | Main + Core Audio listener queue |
| `DeviceManager/` | Lists devices, default device, system volume/mute, connect/disconnect, sleep/wake | Main + listener queue |
| `AudioEngine/` | `AudioEngine` actor creates taps and aggregate devices; `TapRenderState` is the real-time render code | **Real-time** (IOProc) + engine actor (setup) |
| `Persistence/` | Per-app and per-device settings and profiles (`UserDefaults`, Codable) | Main |
| `UI/` | SwiftUI menu panel, Settings, onboarding; `StatusItemController` for scroll/Option-click on the icon | Main |
| `Integration/` | App Intents (Shortcuts, Siri), Sparkle updates, launch at login | Main |
| `VolumeRockerControls/` | Separate, sandboxed WidgetKit extension with Control Center controls (macOS 26+) | Its own process |

Models are `@Observable` and isolated to the `MainActor`. The project compiles in Swift 6 language mode with complete strict-concurrency checking.

## The real-time rules

Core Audio calls the IOProc every few milliseconds, with a hard deadline. If it is late, you hear a click. Inside the IOProc Volume Rocker therefore **never**:

- allocates or frees memory (no `Array` growth, no `String`, no class instances),
- takes a lock or waits on anything,
- calls `async` code, logs, or touches Objective-C objects.

Instead:

- **Parameters in:** each app's target gain, mute and EQ settings live in `Atomic` values from the Swift `Synchronization` module. The UI writes them; the audio thread reads them.
- **Levels out:** the audio thread writes peak and RMS levels into `Atomic` values, and the UI reads them about 30 times per second while the panel is open.
- **No zipper noise:** the gain never jumps. Each buffer ramps linearly from the previous gain to the new target (`vDSP_vrampmul`), so moving a slider is perfectly smooth.
- **Pre-allocated buffers:** scratch buffers are sized when the aggregate device starts and when the sample rate or buffer size changes, never inside the callback.
- **Math with Accelerate:** gain, mixing, metering and biquad EQ all use vDSP.

## The render pipeline

Each IOProc call runs one buffer (normally 512 frames) through `TapRenderState.render`:

1. **Load:** copy the tap's left/right channels into a stereo scratch buffer that was allocated up front.
2. **EQ:** ten peaking biquads (RBJ cookbook, one octave wide, ±12 dB) via `vDSP_biquadm`. New coefficients arrive through a **lock-free triple buffer**: the main thread writes a spare set and swaps an atomic index, and the audio thread picks the new set up at the start of the next buffer. Neither side ever waits. The filters run only after an EQ has been set once.
3. **Gain:** a linear ramp from the previous gain to the new one across the buffer (`vDSP_vrampmul`), 0–200%.
4. **Limiter:** because the whole buffer is available before it is played, the limiter measures its peak first, then applies a gain that keeps every sample under −0.1 dBFS. It reduces instantly and releases over about 250 ms. Boosted or EQ'd audio therefore can never clip.
5. **Meter:** the buffer's peak goes into an atomic for the UI.
6. **Write:** left/right go to the device's first two channels, interleaved or not.

## How the pieces talk

The engine is **declarative**. Whenever anything changes (an app starts or stops playing, the permission changes, the output device changes), `MixerModel` builds the complete list of taps that *should* exist (`[TapRequest]`) and hands it to the `AudioEngine` actor. The engine compares it with what is running, then stops, starts or restarts sessions to match. Calls are serialized, so an older list can never overwrite a newer one. Slow Core Audio setup calls run on the actor, never on the main thread.

A tap is kept for 30 seconds after an app goes quiet, so pausing and resuming doesn't rebuild it.

Volume changes don't go through the engine at all. The slider writes the new gain straight into that app's `TapRenderState` atomic, and the next audio buffer ramps to it.

## Apple API notes (things that behave differently than documented)

- **"Is running output" notifications don't arrive.** Listening for `kAudioProcessPropertyIsRunningOutput` changes on a process object never fires (tested on macOS 27). `kAudioProcessPropertyIsRunning` does fire, and by then the output flag is already up to date, so `AudioProcessMonitor` listens to both and re-reads.
- **There is no public API to check the System Audio Recording permission.** Without the permission, a tap still "works" but delivers silence while muting the app, which would silence the user's apps. Volume Rocker therefore checks it through the TCC framework's `TCCAccessPreflight`/`TCCAccessRequest`, loaded dynamically (the same approach as the well-known AudioCap sample). If those functions disappear, the app falls back to the system prompt.
- **Helper processes.** Browsers play sound from helper processes. Chrome's helpers live inside `Google Chrome.app`, so the outermost `.app` in the executable path identifies the app. Safari's audio comes from WebKit's GPU process, which lives outside Safari. For that case macOS's "responsible process" (looked up with `responsibility_get_pid_responsible_for_pid`, also loaded dynamically) points back to Safari.
- **Taps always deliver 48 kHz.** The tap's format is 48 kHz stereo even when the app plays to a 44.1 kHz device, and pinning the tap to a device (`CATapDescription.deviceUID`) doesn't change that. The aggregate device's drift compensation converts the rate, and the IOProc receives equal frame counts for input and output. But a tap entry without an explicit `kAudioSubTapDriftCompensationQualityKey` uses a low-quality converter, which was audible as distortion on 44.1 kHz Bluetooth headphones. Volume Rocker requests `kAudioAggregateDriftCompensationMaxQuality`, at about 1% CPU per playing app.
- **Hidden menu bar panels keep animating.** A `MenuBarExtra` window stays alive while closed, and SwiftUI keeps `TimelineView` animations running in it. The level meters therefore pause based on the panel window's occlusion state (`NSWindow.didChangeOcclusionStateNotification`). Without this, the closed panel used about 20% CPU while audio played.
- **Headsets with microphones.** An aggregate device built on AirPods also contains their microphone, which could switch Bluetooth into low-quality call mode. The engine marks those input streams as unused for its IOProc (`kAudioDevicePropertyIOProcStreamUsage`).

## Lifecycle and robustness

- **Device switching:** choosing a device in the panel sets the system default (`kAudioHardwarePropertyDefaultOutputDevice`/`…InputDevice`), exactly like Control Center. If alerts were following the default output, they move too.
- **Device changes:** when an app moves to another output device, or the default output device changes, its tap request changes and the engine rebuilds that app's aggregate device. Each request uses the app's device only if it's still in the device list and is a real output device. Otherwise (disconnected, or an automatic voice-processing aggregate) it falls back to the default output.
- **Device list:** `AudioDeviceList` watches `kAudioHardwarePropertyDevices` and hides hidden devices, our own private aggregates and devices that can't be the default.
- **Sample-rate changes:** `AudioDeviceList` watches each output device's nominal sample rate. When one changes, the taps on that device are rebuilt by bumping a per-device *generation* number in their `TapRequest`s.
- **Sleep/wake:** on `NSWorkspace.willSleepNotification` every tap is released, so apps play normally and devices can sleep. Two seconds after wake (so Bluetooth can reconnect), the global generation is bumped and all taps are rebuilt.
- **Core Audio restarts:** if `coreaudiod` restarts (`kAudioHardwarePropertyServiceRestarted`), every object ID is stale, so all monitors, controllers and taps start over.
- **Per-app routing:** an app with a chosen output device gets its aggregate device built on that device instead of its own. If the device disconnects, the app falls back to its own device, then returns when the device reconnects. Routing is stored once per app, never per device.
- **Profiles:** a profile is a snapshot of every app's settings, plus optionally the output device. Applying it sets known apps and resets the others to 100%.
- **Per-device memory (optional):** with "Remember app volumes for each output device" on, settings are stored as `"<device UID>|<bundle ID>"`. A new device starts from the app's general setting.
- **Crash safety:** private aggregate devices and taps belong to the Volume Rocker process. If it crashes or quits, macOS removes them and the apps play normally again, so audio is never left silent.

## Menu bar icon, shortcuts and Control Center

- **Scroll and Option-click:** `MenuBarExtra` has no API for either. `StatusItemController` installs a *local* event monitor (only this app's events) and handles scroll-wheel and Option-click/right-click events whose window is the app's own `NSStatusBarWindow`. Scrolling follows the physical direction regardless of "natural scrolling".
- **Opening the panel from a shortcut** clicks the status item's button programmatically.
- **Keyboard shortcuts** use the KeyboardShortcuts package. Each profile gets its own shortcut name (`profile.<UUID>`).
- **App Intents** run inside the app. Entities: apps (bundle IDs from running and remembered apps), output devices (by UID) and profiles.
- **Control Center controls** live in a sandboxed extension. *Mute Sound* changes the default device's mute directly through Core Audio, so it works even when the app isn't running. *Next Profile* and *Open Volume Rocker* post a distributed notification without any data, which the running app observes. Any local process could post the same notifications, but they can only switch profiles or open the panel.

## Signing

Releases signed with Developer ID use the hardened runtime, as notarization requires. Ad-hoc builds (local builds and the unsigned fallback) do **not**: the hardened runtime only loads frameworks from the same developer team, and ad-hoc signatures have no team, so the app couldn't load Sparkle. `Scripts/sign.sh` signs inside out (Sparkle's helpers, frameworks, the extension, then the app) and keeps each piece's entitlements.

## Permissions

Process taps need the **System Audio Recording** permission (`NSAudioCaptureUsageDescription`). macOS shows the prompt the first time a tap is created. Volume Rocker explains why on an onboarding screen first. Microphone access is never requested unless an input feature is turned on.
