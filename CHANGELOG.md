# Changelog

All notable changes to Volume Rocker are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
