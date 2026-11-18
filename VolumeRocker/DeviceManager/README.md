# DeviceManager

- `DefaultDeviceController`: the default output or input device, its volume and mute, kept in sync with the volume keys through Core Audio listeners.
- `AudioDeviceList`: every selectable output and input device, live; switches the system default; reports sample-rate changes.
- `AudioDevice`: a device's name, UID and connection type, and its SF Symbol.
- `SystemAudioEvents`: sleep, wake and Core Audio daemon restarts.
