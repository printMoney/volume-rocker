# Changelog

All notable changes to Volume Rocker are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-18

The first public release.

### Added

**Mixer**
- Per-app volume and mute, using Core Audio process taps. No audio driver or system extension needed.
- Live detection of apps playing sound, with helper processes grouped under their app (for example Chrome's and Safari's).
- Live level meters for each app.
- Volume boost up to 200% per app (Settings → General), with a built-in limiter so boosted audio never clips.
- 10-band equalizer per app with presets: Bass Boost, Bass Reducer, Treble Boost, Vocal, Spoken Word, Loudness, Rock, Electronic, Classical and Late Night.
- Per-app output routing: play any app on a specific device, for example calls on the headset and music on the speakers.
- Profiles: save the current mix as "Work", "Gaming", "Movie" and so on, and switch with one click or a keyboard shortcut.
- Every app's volume, mute, EQ and routing are remembered across restarts, optionally per output device.
- "Show Recent Apps" to also list apps that are quiet right now; right-click an app for more options.

**Devices**
- One-click switching of the output device (built-in, Bluetooth and AirPods, HDMI, DisplayPort, USB, AirPlay) and the input device, with input volume.
- Output volume and mute in sync with the keyboard volume keys; the menu bar icon shows the current level.
- Handles devices connecting and disconnecting, sleep and wake, sample-rate changes and Core Audio restarts without leaving audio silent.
- High-quality sample-rate conversion for devices that don't run at 48 kHz, such as many Bluetooth headphones.

**Integration**
- Scroll on the menu bar icon to change the volume; Option-click or right-click it for devices and profiles.
- Global keyboard shortcuts: open the mixer, mute, volume up and down, next profile, and one per profile.
- Shortcuts and Siri actions: Set App Volume, Mute App, Switch Output Device, Set Output Volume, Apply Profile.
- Control Center controls on macOS 26: Mute Sound, Next Volume Profile, Open Volume Rocker.
- Open at login, a first-launch welcome that explains the permission, and a native Settings window (General, Apps, Devices, Shortcuts, Profiles, Updates, About).
- Excluded apps that Volume Rocker never touches, and a default volume for new apps.
- Automatic updates with Sparkle, EdDSA-signed (switched on once the update key is configured).

**Quality**
- About 0.3% CPU at idle, 1.4% while processing audio and 32 MB of memory, measured with Instruments ([details](https://github.com/printMoney/volume-rocker/blob/main/docs/PERFORMANCE.md)).
- Real-time-safe audio path: no allocations, locks or logging on the audio thread; smooth, click-free volume changes.
- VoiceOver and keyboard support; respects Reduce Motion and Reduce Transparency; Liquid Glass on macOS 26.
- All user-facing text in String Catalogs, ready for translation.

### Known limitations

- This build is not signed with an Apple Developer ID. See the README for how to open it the first time.
- Automatic updates are not active in this version yet.
- When an app resumes after being paused for more than 30 seconds, its first few milliseconds may play at its original volume.
- To choose a specific AirPlay speaker, use Control Center.

[Unreleased]: https://github.com/printMoney/volume-rocker/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/printMoney/volume-rocker/releases/tag/v0.1.0
