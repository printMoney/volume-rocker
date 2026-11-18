# AudioEngine

Core Audio process taps, the private aggregate devices and the real-time IOProc that applies gain, metering and EQ. Code here must be real-time safe: no allocations, locks, async calls, logging or Objective-C in the audio callback. Arrives in Phase 1.
