import AppKit
import QuartzCore
import SwiftUI

/// A thin live level bar.
///
/// Drawn with Core Animation and driven by a plain timer, so each update only resizes one layer.
/// Redrawing it through SwiftUI cost about 8% CPU while the panel was open, and a per-view display link
/// made AppKit re-run the whole panel's layout every frame (about 25%). Now it is about 1%.
/// It pauses while the panel is hidden, and updates less often with Reduce Motion.
struct LevelMeterView: View {
    let meter: LevelMeter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isWindowVisible) private var isWindowVisible

    var body: some View {
        LevelMeterRepresentable(meter: meter, isPaused: !isWindowVisible, framesPerSecond: reduceMotion ? 10 : 30)
            .frame(height: 3)
            .accessibilityHidden(true)
    }
}

private struct LevelMeterRepresentable: NSViewRepresentable {
    let meter: LevelMeter
    let isPaused: Bool
    let framesPerSecond: Float

    func makeNSView(context _: Context) -> LevelMeterNSView {
        LevelMeterNSView(meter: meter)
    }

    func updateNSView(_ view: LevelMeterNSView, context _: Context) {
        view.meter = meter
        view.setPaused(isPaused, framesPerSecond: framesPerSecond)
    }
}

final class LevelMeterNSView: NSView {
    var meter: LevelMeter
    private let track = CALayer()
    private let fill = CALayer()
    private var timer: Timer?
    private var level: CGFloat = 0
    private var isPaused = true
    private var framesPerSecond: Float = 30

    init(meter: LevelMeter) {
        self.meter = meter
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(track)
        track.addSublayer(fill)
        track.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool {
        true
    }

    func setPaused(_ paused: Bool, framesPerSecond: Float) {
        isPaused = paused
        self.framesPerSecond = framesPerSecond
        updateDisplayLink()
    }

    /// The timer keeps this view alive while it runs, so it is always stopped when the view leaves its window
    /// or the panel is hidden.
    private func updateDisplayLink() {
        if isPaused || window == nil {
            timer?.invalidate()
            timer = nil
            return
        }
        let interval = 1.0 / Double(framesPerSecond)
        if let timer, abs(timer.timeInterval - interval) < 0.001 {
            return
        }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDisplayLink()
    }

    private func tick() {
        let newLevel = CGFloat(meter.level(at: Date()))
        guard abs(newLevel - level) > 0.002 else { return }
        level = newLevel
        layoutFill()
    }

    override func layout() {
        super.layout()
        if level == 0 {
            level = CGFloat(meter.level(at: Date()))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        track.cornerRadius = bounds.height / 2
        CATransaction.commit()
        layoutFill()
    }

    private func layoutFill() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = max(0, min(bounds.width, bounds.width * level))
        fill.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        fill.cornerRadius = bounds.height / 2
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            fill.backgroundColor = NSColor.controlAccentColor.cgColor
        }
    }
}
