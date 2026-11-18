# AudioEngine

- `AudioEngine`: actor that creates and tears down process taps and private aggregate devices to match a list of `TapRequest`s.
- `TapRenderState`: the real-time render code (gain ramp, peak metering) plus the atomics shared with the UI. **No allocations, locks, logging, async code or Objective-C in `render`.**
- `LevelMeter`: smooths peaks for the on-screen meters.
- `AudioCapturePermission`: checks and requests the System Audio Recording permission.
