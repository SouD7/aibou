import SwiftUI

/// Screen-space wiring: every segment is horizontal or vertical, including turns.
struct MonitorCircuitFlow: View {
    var exclusions: [CGRect] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()

    // Matches ElectricTransitionEffect's pale-blue glow and bright blue-white core.
    private let glow = Color(red: 184 / 255, green: 234 / 255, blue: 1)
    private let core = Color(red: 240 / 255, green: 251 / 255, blue: 1)

    private static let routes: [[CGPoint]] = [
        [.init(x: 0, y: 0.075), .init(x: 0.34, y: 0.075), .init(x: 0.34, y: 0.27), .init(x: 1, y: 0.27)],
        [.init(x: 1, y: 0.15), .init(x: 0.72, y: 0.15), .init(x: 0.72, y: 0.58), .init(x: 0, y: 0.58)],
        [.init(x: 0, y: 0.80), .init(x: 0.52, y: 0.80), .init(x: 0.52, y: 0.93), .init(x: 1, y: 0.93)],
        [.init(x: 0.014, y: 1), .init(x: 0.014, y: 0.36), .init(x: 0.22, y: 0.36), .init(x: 0.22, y: 0)],
        [.init(x: 0.986, y: 0), .init(x: 0.986, y: 0.69), .init(x: 0.83, y: 0.69), .init(x: 0.83, y: 1)],
        [.init(x: 0.60, y: 1), .init(x: 0.60, y: 0.46), .init(x: 0.10, y: 0.46), .init(x: 0.10, y: 0)]
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas { context, size in
                // Intersect inverse rectangles individually so overlapping exclusions stay hidden.
                for rect in exclusions {
                    var visible = Path(CGRect(origin: .zero, size: size))
                    visible.addRect(rect)
                    context.clip(to: visible, style: FillStyle(eoFill: true))
                }
                let elapsed = reduceMotion ? 0 : max(0, timeline.date.timeIntervalSince(startedAt))
                for (index, route) in Self.routes.enumerated() {
                    let points = route.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                    let length = zip(points, points.dropFirst()).reduce(CGFloat.zero) {
                        $0 + abs($1.1.x - $1.0.x) + abs($1.1.y - $1.0.y)
                    }
                    guard length > 0, let first = points.first else { continue }
                    var path = Path()
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    context.stroke(path, with: .color(glow.opacity(0.075)), lineWidth: 0.8)

                    // A finite pulse moves at a stable speed, then leaves a quiet interval.
                    let pulseLength = min(150, length * 0.18)
                    let cycle = (length + pulseLength) / 220 + 1.8
                    let time = (elapsed + Double(index) * 1.7).truncatingRemainder(dividingBy: cycle)
                    let head = CGFloat(time * 220)
                    let start = max(0, (head - pulseLength) / length)
                    let end = min(1, head / length)
                    guard start < end else { continue }
                    let pulse = path.trimmedPath(from: start, to: end)
                    context.drawLayer { halo in
                        halo.addFilter(.blur(radius: 4))
                        halo.stroke(pulse, with: .color(glow.opacity(0.55)), lineWidth: 5)
                    }
                    context.stroke(pulse, with: .color(glow.opacity(0.8)), lineWidth: 1.8)
                    context.stroke(pulse, with: .color(core.opacity(0.65)), lineWidth: 0.65)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
