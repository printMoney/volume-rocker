# Volume Rocker Roadmap

Volume Rocker is a free, open-source macOS menu bar app that gives every app its own volume control. It should feel like something Apple built.

Legend: ✅ done · 🚧 in progress · ⬜ not started

## Phase 0: Foundation ✅

- ✅ Git repository, `.gitignore`, MIT license
- ✅ XcodeGen `project.yml` (Swift 6, strict concurrency, arm64 only, macOS 15+)
- ✅ Module folders: `AudioEngine`, `DeviceManager`, `ProcessMonitor`, `Persistence`, `UI`
- ✅ Empty menu bar app (`MenuBarExtra`, `.window` style, no Dock icon)
- ✅ Unit test target
- ✅ SwiftLint and SwiftFormat config
- ✅ GitHub Actions: `ci.yml` (build, test, lint) and `release.yml` (sign, notarize, DMG, appcast; skips signing cleanly when no secrets are set)
- ✅ `Scripts/` for building, making the DMG and notarizing locally
- ✅ Docs skeleton: README, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CHANGELOG, ARCHITECTURE
- ✅ `.github` issue templates, PR template, FUNDING placeholder
- ✅ App icon placeholder

## Phase 1: Core mixer ✅

- ✅ Live detection of apps producing audio (`kAudioHardwarePropertyProcessObjectList`, per-process "is running output")
- ✅ Helper processes grouped under their parent app (browsers, Electron apps)
- ✅ Per-app volume (0–100%) and mute via Core Audio process taps and a private aggregate device
- ✅ Real-time-safe IOProc: no allocations, locks, async code or logging; parameters passed with `Atomic`; ramped gain
- ✅ Master volume and mute, in sync with the volume keys
- ✅ Live per-app level meters (vDSP)
- ✅ Per-app volume and mute remembered by bundle ID
- ✅ Permission onboarding for "System Audio Recording"
- ✅ Menu bar icon reflects volume and mute

Notes: each app gets its own private aggregate device (see docs/ARCHITECTURE.md for why). Known limitation: when a paused app resumes after more than 30 seconds, its first few milliseconds play at the original volume while the tap starts.

## Phase 2: Devices ⬜

- ⬜ One-click output device switching (built-in, Bluetooth, HDMI/DisplayPort, USB, AirPlay)
- ⬜ Input device switching and input volume
- ⬜ Survive device connect and disconnect, sleep and wake, and sample-rate changes
- ⬜ Optional per-device memory of app volumes

## Phase 3: Power features ⬜

- ⬜ Per-app boost up to 200% with a soft limiter
- ⬜ Per-app output routing
- ⬜ Per-app 10-band EQ with presets (vDSP biquads)
- ⬜ Profiles ("Work", "Gaming", "Movie", …)

## Phase 4: Integration and quality of life ⬜

- ⬜ Scroll on the menu bar icon for master volume; Option-click for the device list
- ⬜ Global keyboard shortcuts (KeyboardShortcuts)
- ⬜ App Intents for Shortcuts and Siri
- ⬜ Control Center control (WidgetKit, macOS 26)
- ⬜ Launch at login (`SMAppService`)
- ⬜ Settings window: General, Apps, Devices, Shortcuts, Updates, About
- ⬜ First-launch onboarding
- ⬜ Sparkle auto-updates (EdDSA-signed appcast)

## Release readiness ⬜

- ⬜ Instruments performance check (idle < 1% CPU, active < 3%, < 50 MB)
- ⬜ Memory-leak check
- ⬜ Accessibility audit (VoiceOver, keyboard navigation, Reduce Motion/Transparency)
- ⬜ README polish with real screenshots

## Performance targets

| Metric | Target |
| --- | --- |
| CPU when idle | < 1% |
| CPU while processing audio | < 3% |
| Memory | < 50 MB |
| Menu open latency | No visible lag |
