import SpriteKit

/// One clock controls the spark burst, full straight beam, and arrival interference.
/// No delayed callbacks survive a newer selection or a pause/focus change.
struct ElectricTransition {
    static let duration = 0.5
    let from: AvatarPoseID
    let to: AvatarPoseID
    let startedAt: Double
    let origin: CGPoint
    let destination: CGPoint

    struct Sample {
        let outgoingAlpha: Double
        let incomingAlpha: Double
        let departure: Double
        let beam: Double
        let noiseProgress: Double?
        let finished: Bool
    }

    var duration: Double { to == .closeUp ? CloseUpEntranceTiming.transitionDuration : Self.duration }

    static func requiresEffect(from: AvatarPoseID, to: AvatarPoseID) -> Bool {
        guard from != to else { return false }
        let newStates: Set<AvatarPoseID> = [.writing, .cpuRest, .glitch, .closeUp]
        return newStates.contains(from) || newStates.contains(to) || !(from.isStanding && to.isStanding)
    }

    func sample(at time: Double) -> Sample {
        // Quantize sub-nanosecond subtraction error at exact phase boundaries.
        let t = (max(0, time - startedAt) * 1e9).rounded() / 1e9
        let arrivalStartsAt = to == .closeUp ? CloseUpEntranceTiming.startsAt : 0.2
        return Sample(outgoingAlpha: 0,
                      incomingAlpha: t >= arrivalStartsAt ? 1 : 0,
                      departure: t < 0.1 ? 1 - t / 0.1 : 0,
                      beam: (0.1..<0.2).contains(t) ? 1 - (t - 0.1) / 0.1 * 0.7 : 0,
                      noiseProgress: (0.2..<0.5).contains(t) ? (t - 0.2) / 0.3 : nil,
                      finished: t >= duration)
    }

}

/// Disconnected sparks expand at the origin; the entire straight beam flashes at once.
final class ElectricTransitionEffect: SKNode {
    private let glow = SKShapeNode()
    private let core = SKShapeNode()

    override init() {
        super.init()
        name = "electric-transition"; zPosition = 12; isHidden = true
        for node in [glow, core] {
            node.fillColor = .clear; node.lineCap = .round
            addChild(node)
        }
        glow.strokeColor = NSColor(hex: "#B8EAFF"); glow.lineWidth = 5; glow.glowWidth = 7
        core.strokeColor = NSColor(hex: "#F0FBFF"); core.lineWidth = 1.8; core.glowWidth = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func render(_ transition: ElectricTransition, at time: Double) {
        let sample = transition.sample(at: time)
        isHidden = sample.departure == 0 && sample.beam == 0
        guard !isHidden else { return }
        let path = CGMutablePath()
        if sample.departure > 0 {
            let progress = 1 - sample.departure
            for ray in 0..<22 {
                let seed = Double(ray)
                let angle = seed * .pi * 2 / 22 + sin(seed * 7.13) * 0.16
                let radius = (12 + progress * 105) * (0.65 + abs(sin(seed * 3.71)) * 0.5)
                let length = (8 + abs(cos(seed * 5.19)) * 22) * (1 - progress * 0.6)
                let start = CGPoint(x: transition.origin.x + cos(angle) * radius,
                                    y: transition.origin.y + sin(angle) * radius)
                path.move(to: start)
                path.addLine(to: CGPoint(x: start.x + cos(angle) * length,
                                        y: start.y + sin(angle) * length))
            }
        }
        if sample.beam > 0 {
            path.move(to: transition.origin)
            path.addLine(to: transition.destination)
        }
        glow.path = path; core.path = path
        alpha = max(sample.departure, sample.beam)
    }
}
