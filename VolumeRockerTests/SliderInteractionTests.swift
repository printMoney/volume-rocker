import AppKit
import Testing
@testable import VolumeRocker

/// Clicks the real EQ band slider. Regression test: the old rotated slider jumped to the maximum on every click.
@MainActor
struct SliderInteractionTests {
    private func makeSlider() -> (DecibelSlider, NSWindow) {
        let slider = DecibelSlider(frame: NSRect(x: 20, y: 15, width: 22, height: 170))
        slider.isVertical = true
        slider.minValue = -12
        slider.maxValue = 12
        slider.controlSize = .small
        slider.doubleValue = 0
        // An active, key window (off screen): macOS ignores the first click in an inactive window.
        let window = MixerPanel(
            contentRect: NSRect(x: -20000, y: -20000, width: 60, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        window.contentView?.addSubview(slider)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return (slider, window)
    }

    /// Clicks at a height given as a fraction from the bottom (0) to the top (1) of the slider.
    private func click(_ slider: NSSlider, in window: NSWindow, atHeight fraction: CGFloat) {
        let y = slider.isFlipped ? slider.bounds.height * (1 - fraction) : slider.bounds.height * fraction
        let location = slider.convert(NSPoint(x: slider.bounds.midX, y: y), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            )
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return }
        NSApp.postEvent(up, atStart: false)
        window.sendEvent(down)
    }

    @Test func clickSetsTheValueWhereYouClick() {
        let (slider, window) = makeSlider()
        defer { window.orderOut(nil) }
        click(slider, in: window, atHeight: 0.75)
        #expect((3 ... 9).contains(slider.doubleValue), "clicked 3/4 up, got \(slider.doubleValue) dB")
        click(slider, in: window, atHeight: 0.25)
        #expect((-9 ... -3).contains(slider.doubleValue), "clicked 1/4 up, got \(slider.doubleValue) dB")
        click(slider, in: window, atHeight: 0.5)
        #expect(abs(slider.doubleValue) < 2, "clicked the middle, got \(slider.doubleValue) dB")
    }

    @Test func voiceOverReadsDecibels() {
        let (slider, window) = makeSlider()
        defer { window.orderOut(nil) }
        slider.doubleValue = 6
        let expected = Float(6).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
        #expect(slider.accessibilityValueDescription() == "\(expected) decibels")
    }
}
