# Performance

Measured on 18 November 2026 on a MacBook Pro (Apple Silicon) running macOS 27.2, with a Release build of Volume Rocker 0.1.0 and Bluetooth headphones (44.1 kHz) as the output.

## Method

- **CPU:** Instruments' *Time Profiler* template, attached to the running app with `xcrun xctrace record --attach`. The reported numbers are the average of Instruments' per-10 ms *Process CPU Usage* samples over the recording. 100% would be one CPU core fully busy.
- **Memory:** `footprint` (physical footprint, the number Activity Monitor shows as "Memory").
- **Leaks:** Apple's `leaks` tool (the same engine as Instruments' *Leaks* template), after repeatedly opening and closing the panel and starting and stopping audio.
- **Panel latency:** time from the open request to the panel being on screen, logged inside the app.

Two background apps (a chat app and a browser) kept audio streams open the whole time, so Volume Rocker was always processing at least two streams. That is a realistic "idle".

## Results

| Scenario | Average CPU | Target |
| --- | --- | --- |
| Idle: panel closed, two background streams tapped | **0.32%** | < 1% |
| Processing: a third app playing at 150% with Bass Boost EQ, panel closed | **1.36%** | < 3% |
| Panel open with live level meters (Liquid Glass) | **2.13%** | — |

| Measurement | Result | Target |
| --- | --- | --- |
| Memory (physical footprint) | **32 MB** (peak 33 MB) | < 50 MB |
| Leaks | **0** | 0 |
| Opening the panel | **~25 ms** | no visible lag |

The real-time audio code (`TapRenderState.render`: EQ, gain ramp, limiter and meter) used about 4 ms of CPU time per second of audio for all three apps together.

## What the profiling found and fixed

| Problem | Before | After | Fix |
| --- | --- | --- | --- |
| Level meters kept redrawing while the panel was closed | ~20% CPU, 150 MB | 0.4% | Meters pause when the panel window isn't visible |
| SwiftUI redrew every meter 30× a second | 9.2% with panel open | — | Meters drawn with Core Animation layers instead |
| A per-view display link made AppKit re-run the panel's whole layout every frame | 26% with panel open | 2.1% | A plain timer drives the meters |
| First panel open built the interface on demand | 127 ms | ~25 ms | The panel is built in the background a second after launch |
| Low-quality sample-rate conversion on 44.1 kHz devices (audible distortion) | — | — | Maximum drift-compensation quality, about 0.1% CPU per app |

## Reproducing

```bash
xcrun xctrace record --template 'Time Profiler' --attach "$(pgrep -f 'Volume Rocker.app/Contents/MacOS')" --time-limit 15s --output idle.trace
```

Open the trace in Instruments, select Volume Rocker, and read the CPU Usage track. Or export it with `xcrun xctrace export --input idle.trace --toc`.
