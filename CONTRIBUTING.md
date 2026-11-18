# Contributing to Volume Rocker

Thanks for your interest! Bug reports, ideas, translations and code are all welcome.

## Getting started

1. Install Xcode 26 or newer, then the tools: `brew install xcodegen swiftlint swiftformat`
2. Fork and clone the repo, then run `xcodegen generate` and open `VolumeRocker.xcodeproj`.
3. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), especially the real-time rules.

Local builds made with `Scripts/build.sh` + `Scripts/sign.sh` are ad-hoc signed with a requirement based on the bundle identifier, so macOS keeps the System Audio Recording permission across rebuilds. (Builds run from Xcode get a new signature each time and may ask for the permission again.)

The `.xcodeproj` is generated from `project.yml` and is not committed. If you add files or change build settings, edit `project.yml` and re-run `xcodegen generate`.

## Before opening a pull request

- Run `Scripts/test.sh`. It must pass with **zero warnings**.
- Run `swiftformat .` to format your code.
- Add unit tests for anything that isn't real-time audio code.
- Make every user-facing string localizable (SwiftUI `Text("…")` does this automatically; otherwise use `String(localized:)`).
- Add VoiceOver labels to new controls, and check with VoiceOver (⌘F5).
- Add a line under **Unreleased** in `CHANGELOG.md`.

## Code guidelines

- Swift 6 with strict concurrency. Avoid `@unchecked Sendable` and `nonisolated(unsafe)` unless there is no other way, and add a comment explaining why.
- UI and models live on the `MainActor` and use `@Observable`.
- **Audio thread:** no allocations, locks, logging, `async` calls or Objective-C. Use `Atomic` to share values. If unsure, ask in the PR.
- Prefer SwiftUI. Use AppKit only where SwiftUI can't do the job.
- New dependencies need discussion in an issue first. Current ones: Sparkle (updates) and KeyboardShortcuts, pinned to exact versions in `project.yml`.

## Translations

Strings live in `VolumeRocker/Resources/Localizable.xcstrings`. Open it in Xcode, add a language, and translate. No coding required.

## Commit messages

Use the imperative mood and keep the first line under 72 characters, for example "Add per-app mute button".

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE) and that you'll follow the [Code of Conduct](CODE_OF_CONDUCT.md).
