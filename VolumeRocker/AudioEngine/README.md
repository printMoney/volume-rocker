# AudioEngine

- `AudioEngine`: actor that creates and tears down process taps and private aggregate devices to match a list of `TapRequest`s.
- `TapRenderState`: the real-time render pipeline (EQ → gain ramp → limiter → meter) plus the atomics and lock-free EQ triple buffer shared with the UI. **No allocations, locks, logging, async code or Objective-C in `render`.**
- `Equalizer`: band layout, presets and biquad coefficient math.
- `LevelMeter`: smooths peaks for the on-screen meters.
- `AudioCapturePermission`: checks and requests the System Audio Recording permission.
