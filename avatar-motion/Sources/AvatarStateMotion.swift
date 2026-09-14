import Foundation

/// Pure, deterministic timing for the persistent signal-interference state.
/// Each four-second block contains two pulses with slightly different gaps and lengths.
enum GlitchCadence {
    static func noiseProgress(at time: Double) -> Double? {
        guard time.isFinite, time >= 0 else { return nil }
        let block = floor(time / 4)
        let local = time - block * 4
        let firstStart = 0.62 + variation(block, salt: 1) * 0.24
        let firstDuration = 0.20 + variation(block, salt: 2) * 0.15
        let secondStart = 2.48 + variation(block, salt: 3) * 0.42
        let secondDuration = 0.24 + variation(block, salt: 4) * 0.18

        if local >= firstStart, local < firstStart + firstDuration {
            return (local - firstStart) / firstDuration
        }
        if local >= secondStart, local < secondStart + secondDuration {
            return (local - secondStart) / secondDuration
        }
        return nil
    }

    private static func variation(_ block: Double, salt: Double) -> Double {
        let value = sin((block + 1) * 12.9898 + salt * 78.233) * 43_758.5453
        return value - floor(value)
    }
}

struct CloseUpEntranceSample: Equatable {
    let alpha: Double
    let verticalOffset: Double
    let scale: Double
    let finished: Bool
}

/// The close-up waits one second after departure, then rises,
/// overshoots, bounces once, and settles. Values are independent of SpriteKit.
enum CloseUpEntranceTiming {
    static let startsAt = 1.0
    static let duration = 0.62
    static let transitionDuration = 1.62

    static func sample(atTransitionElapsed elapsed: Double, canvasHeight: Double) -> CloseUpEntranceSample {
        let local = elapsed - startsAt
        guard local > 0 else {
            return CloseUpEntranceSample(alpha: 0, verticalOffset: -canvasHeight * 0.92,
                                         scale: 0.94, finished: false)
        }
        if local >= duration {
            return CloseUpEntranceSample(alpha: 1, verticalOffset: 0, scale: 1, finished: true)
        }

        if local < 0.22 {
            let progress = local / 0.22
            let eased = 1 - pow(1 - progress, 3)
            return CloseUpEntranceSample(alpha: min(1, local / 0.10),
                                         verticalOffset: (-0.92 + 0.98 * eased) * canvasHeight,
                                         scale: 0.94 + 0.10 * eased, finished: false)
        }
        if local < 0.40 {
            let progress = (local - 0.22) / 0.18
            let eased = 0.5 - 0.5 * cos(.pi * progress)
            return CloseUpEntranceSample(alpha: 1,
                                         verticalOffset: (0.06 - 0.08 * eased) * canvasHeight,
                                         scale: 1.04 - 0.055 * eased, finished: false)
        }
        let progress = (local - 0.40) / (duration - 0.40)
        let eased = 1 - pow(1 - progress, 2)
        return CloseUpEntranceSample(alpha: 1,
                                     verticalOffset: (-0.02 + 0.02 * eased) * canvasHeight,
                                     scale: 0.985 + 0.015 * eased, finished: false)
    }
}
