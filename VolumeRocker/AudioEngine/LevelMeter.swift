import Foundation

/// Turns raw peak samples into a smooth meter value: instant rise, steady fall, on a decibel scale.
struct MeterBallistics: Equatable {
    static let floorDecibels: Float = -60
    static let decayDecibelsPerSecond: Float = 36

    private(set) var level: Float = 0

    /// Maps a linear peak (0...1+) to 0...1 on a −60…0 dB scale.
    static func normalized(peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        let decibels = 20 * log10(peak)
        return min(1, max(0, (decibels - floorDecibels) / -floorDecibels))
    }

    mutating func update(peak: Float, elapsed: TimeInterval) -> Float {
        let decay = Float(max(0, elapsed)) * Self.decayDecibelsPerSecond / -Self.floorDecibels
        level = max(Self.normalized(peak: peak), max(0, level - decay))
        return level
    }
}

/// Reads one app's peaks from the audio thread and smooths them for display.
@MainActor
final class LevelMeter {
    private let state: TapRenderState
    private var ballistics = MeterBallistics()
    private var lastSample: Date?

    init(state: TapRenderState) {
        self.state = state
    }

    func level(at date: Date) -> Float {
        let elapsed = lastSample.map { date.timeIntervalSince($0) } ?? 0
        lastSample = date
        return ballistics.update(peak: state.takePeak(), elapsed: min(elapsed, 0.5))
    }
}
