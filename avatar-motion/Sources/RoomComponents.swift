import AppKit
import SpriteKit

struct RoomComponent: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let category: String
    let symbol: String
    let summary: String
    let z: Int
    let polygons: [[Point2]]

    // Asset coordinates have their origin at the top left.
    var hitPath: CGPath {
        let path = CGMutablePath()
        for polygon in polygons {
            guard let first = polygon.first else { continue }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in polygon.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            path.closeSubpath()
        }
        return path
    }

    func contains(_ point: Point2) -> Bool {
        // Test each region separately so overlapping islands never cancel out.
        polygons.contains { polygon in
            let path = CGMutablePath()
            guard let first = polygon.first else { return false }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for p in polygon.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
            path.closeSubpath()
            return path.contains(CGPoint(x: point.x, y: point.y))
        }
    }
}

struct RoomComponentCatalog: Codable {
    let source: String
    let sceneID: String
    let canvas: Point2
    let components: [RoomComponent]

    /// UI-facing catalog. The scene retains both raw fan hit regions, while menus and
    /// detail presentation expose one combined cooling component.
    var selectionComponents: [RoomComponent] {
        let rawFans = components.filter { ["fan-1", "fan-2"].contains($0.id) }
        var includedFans = false
        return components.compactMap { component in
            if ["fan-1", "fan-2"].contains(component.id) {
                guard !includedFans else { return nil }
                includedFans = true
                return RoomComponent(id: "fans", title: "ファン", category: component.category,
                                     symbol: component.symbol,
                                     summary: "2基のファンの回転状態をまとめて切り替えます。",
                                     z: rawFans.map(\.z).max() ?? component.z,
                                     polygons: rawFans.flatMap(\.polygons))
            }
            if component.id == "compute" {
                return RoomComponent(id: component.id, title: "CPU", category: component.category,
                                     symbol: component.symbol, summary: component.summary,
                                     z: component.z, polygons: component.polygons)
            }
            return component
        }
    }

    func selectionComponent(for id: String) -> RoomComponent? {
        let canonicalID = ["fan-1", "fan-2", "fans"].contains(id) ? "fans" : id
        return selectionComponents.first { $0.id == canonicalID }
    }

    func component(at point: Point2) -> RoomComponent? {
        guard point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.x <= canvas.x, point.y >= 0, point.y <= canvas.y else { return nil }
        return components.enumerated().sorted {
            $0.element.z == $1.element.z ? $0.offset > $1.offset : $0.element.z > $1.element.z
        }.first { $0.element.contains(point) }?.element
    }

    static func load(from url: URL, canvas: Point2) throws -> RoomComponentCatalog {
        let catalog = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard catalog.canvas == canvas, !catalog.components.isEmpty,
              Set(catalog.components.map(\.id)).count == catalog.components.count,
              catalog.components.allSatisfy({ component in
                  !component.id.isEmpty && !component.polygons.isEmpty && component.polygons.allSatisfy {
                      $0.count >= 3 && $0.allSatisfy {
                          $0.x.isFinite && $0.y.isFinite && (0...canvas.x).contains($0.x) && (0...canvas.y).contains($0.y)
                      }
                  }
              }) else {
            throw NSError(domain: "RoomComponents", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "部屋の選択領域が画像と一致しません。"])
        }
        return catalog
    }
}

final class RoomComponentHighlights: SKNode {
    private let hover = SKShapeNode()
    private let selected = SKShapeNode()
    private let label = SKLabelNode(fontNamed: "HiraginoSans-W5")
    private let labelBackground = SKShapeNode()
    private let canvas: Point2

    init(canvas: Point2) {
        self.canvas = canvas
        super.init()
        // Behind the avatar, above the precomposed animated room.
        zPosition = -3
        for shape in [selected, hover] {
            shape.strokeColor = NSColor(hex: "#64E7F0")
            shape.lineWidth = 2.5; shape.glowWidth = 3
            shape.fillColor = NSColor(hex: "#64E7F0").withAlphaComponent(0.10)
            shape.isHidden = true; addChild(shape)
        }
        selected.strokeColor = NSColor(hex: "#B8A7FF")
        selected.fillColor = NSColor(hex: "#B8A7FF").withAlphaComponent(0.10)
        label.fontSize = 20; label.fontColor = .white
        label.verticalAlignmentMode = .center; label.horizontalAlignmentMode = .center
        labelBackground.fillColor = NSColor(hex: "#18252F").withAlphaComponent(0.96)
        labelBackground.strokeColor = NSColor(hex: "#64E7F0").withAlphaComponent(0.6)
        // Keep the name readable even where the foreground avatar covers the furniture.
        labelBackground.lineWidth = 1; labelBackground.zPosition = 30
        labelBackground.isHidden = true; labelBackground.addChild(label); addChild(labelBackground)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func path(for component: RoomComponent) -> CGPath {
        var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvas.y)
        return component.hitPath.copy(using: &transform)!
    }

    func showHover(_ component: RoomComponent?, at point: CGPoint?) {
        hover.path = component.map { path(for: $0) }; hover.isHidden = component == nil
        labelBackground.isHidden = component == nil
        guard let component, let point else { return }
        label.text = "\(component.title) · \(component.category)"
        let width = label.frame.width + 32
        labelBackground.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -21, width: width, height: 42),
                                      cornerWidth: 10, cornerHeight: 10, transform: nil)
        labelBackground.position = CGPoint(x: min(max(point.x, width / 2 + 12), canvas.x - width / 2 - 12),
                                           y: min(max(point.y + 48, 28), canvas.y - 28))
    }

    func showSelection(_ component: RoomComponent?) {
        selected.path = component.map { path(for: $0) }; selected.isHidden = component == nil
    }
}
