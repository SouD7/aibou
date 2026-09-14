import SpriteKit
import AppKit

/// Display-only payload. Detection and recovery decisions belong to the monitor backend.
struct ComponentWarning: Codable, Equatable {
    let message: String
}

final class RoomWarningBadges: SKNode {
    private(set) var badges: [String: SKNode] = [:]
    private let catalog: RoomComponentCatalog

    init(catalog: RoomComponentCatalog) {
        self.catalog = catalog
        super.init()
        zPosition = 40
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func anchor(for component: RoomComponent) -> CGPoint {
        let bounds = component.hitPath.boundingBoxOfPath
        return CGPoint(x: min(max(bounds.maxX - 12, 32), catalog.canvas.x - 32),
                       y: catalog.canvas.y - min(max(bounds.minY - 18, 40), catalog.canvas.y - 40))
    }

    func update(_ warnings: [String: ComponentWarning], reducedMotion: Bool) {
        for id in Array(badges.keys) where warnings[id] == nil {
            badges.removeValue(forKey: id)?.removeFromParent()
        }
        for component in catalog.components where warnings[component.id] != nil {
            if let existing = badges[component.id] {
                if reducedMotion { existing.removeAllActions(); existing.setScale(1) }
                continue
            }
            let badge = SKNode()
            badge.name = "warning-\(component.id)"
            badge.position = anchor(for: component)
            let bubble = SKShapeNode(circleOfRadius: 25)
            bubble.fillColor = NSColor(hex: "#FFCF66")
            bubble.strokeColor = NSColor(hex: "#FFF1CC"); bubble.lineWidth = 2
            bubble.glowWidth = 2
            let tailPath = CGMutablePath()
            tailPath.move(to: CGPoint(x: -8, y: -20)); tailPath.addLine(to: CGPoint(x: 0, y: -34))
            tailPath.addLine(to: CGPoint(x: 8, y: -20)); tailPath.closeSubpath()
            let tail = SKShapeNode(path: tailPath)
            tail.fillColor = bubble.fillColor; tail.strokeColor = .clear
            badge.addChild(tail); badge.addChild(bubble)
            let mark = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            mark.text = "!"; mark.fontSize = 36; mark.fontColor = NSColor(hex: "#382B10")
            mark.horizontalAlignmentMode = .center; mark.verticalAlignmentMode = .center
            badge.addChild(mark)
            addChild(badge); badges[component.id] = badge
            if !reducedMotion {
                badge.setScale(0.85)
                let grow = SKAction.scale(to: 1.10, duration: 0.14)
                grow.timingMode = .easeOut
                badge.run(.sequence([grow, .scale(to: 1, duration: 0.12)]))
            }
        }
    }

    func componentID(at point: CGPoint) -> String? {
        guard !isHidden else { return nil }
        return catalog.components.reversed().first { component in
            guard let badge = badges[component.id] else { return false }
            let delta = CGPoint(x: point.x - badge.position.x, y: point.y - badge.position.y)
            return abs(delta.x) <= 30 && delta.y >= -36 && delta.y <= 30
        }?.id
    }
}
