# Changelog

All notable changes to Volume Rocker are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A harmless Core Audio error was logged whenever an app quit.
- Level meters kept redrawing while the panel was closed, using about 20% CPU while audio played.
- `Scripts/build.sh` could report success after a failed build.
- Distorted audio on Bluetooth headphones and other devices that don't run at 48 kHz. Sample-rate conversion now uses the best quality.

### Added

- **Scroll on the menu bar icon** to change the output volume; **Option-click or right-click** it for a quick menu of output and input devices and profiles.
- **Global keyboard shortcuts** (Settings → Shortcuts): open the mixer, mute, volume up/down, next profile, and one per profile.
- **Shortcuts and Siri actions:** Set App Volume, Mute App, Switch Output Device, Set Output Volume, Apply Profile.
- **Control Center controls** (macOS 26): Mute Sound, Next Volume Profile, Open Volume Rocker.
- **Open at login** (Settings → General and onboarding).
- **Automatic updates** with Sparkle 2, EdDSA-signed (Settings → Updates; active once a signing key is configured).
- Settings → **Apps**: default volume for new apps and **excluded apps** that Volume Rocker never touches.
- Settings now has General, Apps, Devices, Shortcuts, Profiles, Updates and About tabs.

### Changed

- Ad-hoc signed builds no longer use the hardened runtime, so they can load the embedded frameworks. Developer ID releases still use it.
- **Volume boost up to 200%** per app (turn on in Settings → General), with a built-in limiter so boosted audio never clips.
- **10-band equalizer per app** with presets (Bass Boost, Vocal, Spoken Word, Loudness, Rock, Electronic, Classical, Late Night and more).
- **Per-app output routing:** play any app on a specific device, e.g. calls on the headset and music on the speakers.
- **Profiles:** save the current mix as "Work", "Gaming", "Movie" and so on, and switch from the panel. Manage them in Settings → Profiles.
- Right-click an app for Mute, Equalizer, Output Device and Reset.
- **One-click output device switching** in the panel (built-in, Bluetooth/AirPods, HDMI, DisplayPort, USB, AirPlay), with device icons like Control Center.
- **Input device switching and input volume**, which can be hidden in Settings → Devices. Changing the input volume never records audio.
- **Remember app volumes for each output device** (optional, Settings → Devices).
- New **Devices** tab in Settings.
- Taps are released during sleep and rebuilt after wake; rebuilt when a device's sample rate changes; and everything restarts cleanly if the Core Audio system service restarts.
- Apps whose output device disconnects fall back to the default output.
- **Per-app volume and mute** using Core Audio process taps and private aggregate devices, with no virtual audio driver.
- Live detection of apps playing audio, with helper processes grouped under their app (e.g. Chrome and Safari helpers).
- Smooth, click-free gain changes (per-buffer linear ramps with vDSP) on a real-time-safe audio path.
- Live per-app level meters.
- Output volume and mute for the current output device, kept in sync with the volume keys.
- Menu bar icon that reflects the output volume and mute state.
- Per-app volume and mute remembered by bundle ID across restarts.
- "Show Recent Apps" option to also list apps that are quiet right now.
- First-launch onboarding that explains and requests the System Audio Recording permission.
- Permission status in Settings → General.
- Project foundation: XcodeGen project (Swift 6, strict concurrency, Apple Silicon only, macOS 15+).
- Empty menu bar app with a mixer panel placeholder and a native Settings window (General, About).
- Unit tests with Swift Testing.
- SwiftLint and SwiftFormat configuration.
- GitHub Actions for CI and releases (signing and notarization skip cleanly without secrets).
- Release scripts: build, sign, DMG, notarize.
- Documentation: README, architecture, releasing guide, contributing guide, code of conduct, security policy.
- Placeholder app icon.

[Unreleased]: https://github.com/printMoney/volume-rocker/commits/main
