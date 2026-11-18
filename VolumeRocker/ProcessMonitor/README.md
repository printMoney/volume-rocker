# ProcessMonitor

- `AudioProcessMonitor`: watches `kAudioHardwarePropertyProcessObjectList` and each process's running state.
- `AppResolver`: maps a process to the app the user sees, grouping helpers (Chrome helpers, Safari's WebKit GPU process) under their parent app.
