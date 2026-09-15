import Foundation
import simd

struct MotionInput: Equatable {
    var time: Double
    var strength: Double
    var reducedMotion: Bool
    var speechAmplitude: Double
    var forceBlink: Double?

    init(time: Double, strength: Double = 1, reducedMotion: Bool = false,
         speechAmplitude: Double = 0, forceBlink: Double? = nil) {
        self.time = time; self.strength = strength; self.reducedMotion = reducedMotion
        self.speechAmplitude = speechAmplitude; self.forceBlink = forceBlink
    }
}

struct MotionOutput: Equatable {
    var blink: Double
    var mouthOpen: Double
    var pageTurn: Double
}

enum MotionMath {
    static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
        min(max(value, lower), upper)
    }

    static func gaussian(_ point: Point2, around anchor: Point2, radiusX: Double, radiusY: Double) -> Double {
        let dx = (point.x - anchor.x) / radiusX
        let dy = (point.y - anchor.y) / radiusY
        return exp(-(dx * dx + dy * dy) * 0.5)
    }

    static func blinkAmount(at time: Double) -> Double {
        // Deterministic uneven cadence: a normal blink, then an occasional double blink.
        let cycle = time.truncatingRemainder(dividingBy: 5.7)
        func pulse(center: Double, width: Double) -> Double {
            let distance = abs(cycle - center)
            guard distance < width else { return 0 }
            return 0.5 + 0.5 * cos(.pi * distance / width)
        }
        return max(pulse(center: 4.42, width: 0.105), pulse(center: 4.72, width: 0.075) * 0.72)
    }

    static func pageTurnAmount(at time: Double) -> Double {
        let cycle = time.truncatingRemainder(dividingBy: 13.0)
        guard cycle >= 10.7, cycle <= 11.65 else { return 0 }
        let phase = (cycle - 10.7) / 0.95
        return sin(.pi * phase)
    }

    static func output(for pose: AvatarPoseID, input: MotionInput) -> MotionOutput {
        let faceIsActive = pose.isStanding
        return MotionOutput(
            blink: faceIsActive ? clamp(input.forceBlink ?? blinkAmount(at: input.time)) : 0,
            mouthOpen: faceIsActive ? clamp(input.speechAmplitude * 1.45) : 0,
            pageTurn: pose == .reading && !input.reducedMotion ? pageTurnAmount(at: input.time) * input.strength : 0
        )
    }

    /// Returns an offset in normalized image coordinates (x right, y down).
    static func displacement(at point: Point2, pose: PoseManifest, input: MotionInput) -> Point2 {
        let reducedFactor = input.reducedMotion ? 0.22 : 1.0
        let amount = clamp(input.strength, 0, 1.6) * reducedFactor
        guard amount > 0 else { return Point2(0, 0) }

        let headWeight = gaussian(point, around: pose.head, radiusX: 0.26, radiusY: 0.20)
        let chestWeight = gaussian(point, around: pose.chest, radiusX: 0.31, radiusY: 0.22)
        let hipWeight = gaussian(point, around: pose.hip, radiusX: 0.34, radiusY: 0.25)
        let edgeSoftening = clamp(point.x / 0.08) * clamp((1 - point.x) / 0.08)

        switch pose.id {
        case .standing, .standingBackHands, .standingFrontHands:
            let contactLock = 1 - pow(clamp((point.y - 0.72) / 0.28), 1.35)
            let breath = sin(input.time * .pi * 0.72)
            let secondary = sin(input.time * .pi * 0.49 + 1.1)
            let headSway = sin(input.time * .pi * 0.38)
            let hairBias = clamp((pose.head.y + 0.36 - point.y) / 0.34) * clamp(abs(point.x - pose.head.x) / 0.28)
            let dx = (0.0075 * headSway * headWeight + 0.0045 * secondary * hairBias) * contactLock
            let dy = (-0.0062 * breath * chestWeight - 0.0025 * secondary * hipWeight) * contactLock
            return Point2(dx * amount * edgeSoftening, dy * amount)

        case .sleeping:
            // The sleeping art is horizontal. Lock its long lower bed-contact band rather than
            // treating the lower image corners as standing feet.
            let bedContact = Point2(0.5, min(0.92, pose.hip.y + 0.16))
            let contactLock = 1 - 0.94 * gaussian(point, around: bedContact, radiusX: 0.68, radiusY: 0.11)
            let breath = sin(input.time * .pi * 0.58)
            let dx = 0.0050 * breath * chestWeight * (point.x < pose.chest.x ? -1 : 1)
            let dy = -0.0070 * breath * chestWeight
            return Point2(dx * amount * contactLock * edgeSoftening, dy * amount * contactLock)

        case .reading:
            let groundLock = 1 - pow(clamp((point.y - 0.75) / 0.25), 1.3)
            let breath = sin(input.time * .pi * 0.55)
            let headSway = sin(input.time * .pi * 0.30 + 0.7)
            let dx = (0.0035 * headSway * headWeight + 0.002 * breath * chestWeight) * groundLock
            let dy = -0.0048 * breath * chestWeight * groundLock
            return Point2(dx * amount * edgeSoftening, dy * amount)
        }
    }

    static func destinationGrid(columns: Int, rows: Int, pose: PoseManifest, input: MotionInput) -> [SIMD2<Float>] {
        var positions: [SIMD2<Float>] = []
        positions.reserveCapacity((columns + 1) * (rows + 1))
        for row in 0...rows {
            for column in 0...columns {
                let gridX = Double(column) / Double(columns)
                let gridY = Double(row) / Double(rows)
                let point = Point2(gridX, 1 - gridY)
                let delta = displacement(at: point, pose: pose, input: input)
                // SKWarp uses normalized 0...1 coordinates with y increasing upward.
                positions.append(SIMD2(Float(gridX + delta.x), Float(gridY - delta.y)))
            }
        }
        return positions
    }

    static func sourceGrid(columns: Int, rows: Int) -> [SIMD2<Float>] {
        var positions: [SIMD2<Float>] = []
        positions.reserveCapacity((columns + 1) * (rows + 1))
        for row in 0...rows {
            for column in 0...columns {
                positions.append(SIMD2(Float(Double(column) / Double(columns)),
                                       Float(Double(row) / Double(rows))))
            }
        }
        return positions
    }
}
