import Foundation
import AppKit

func testRoomComponents() throws {
    let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    let catalog = try RoomComponentCatalog.load(from: assets.appendingPathComponent("room-components.json"),
                                                canvas: Point2(1672, 941))
    let targets: [(String, Point2)] = [
        ("bookshelf", Point2(500, 380)), ("network", Point2(1362, 410)),
        ("clock", Point2(674, 330)), ("fan-1", Point2(1120, 280)), ("fan-2", Point2(1205, 275)),
        ("bed", Point2(300, 550)), ("desk", Point2(1060, 575)), ("compute", Point2(1500, 600)),
        ("display", Point2(1000, 420)), ("external", Point2(1608, 708)), ("chair", Point2(800, 470))
    ]
    try expect(catalog.components.count == targets.count, "all eleven room components")
    for (id, point) in targets {
        try expect(catalog.component(at: point)?.id == id, "hit test \(id) at \(point)")
    }
    for point in [Point2(1000, 850), Point2(50, 50), Point2(-1, 100), Point2(1800, 500), Point2(.nan, 20)] {
        try expect(catalog.component(at: point) == nil, "background and off-canvas must not select")
    }
    let square = [Point2(0, 0), Point2(20, 0), Point2(20, 20), Point2(0, 20)]
    let lower = RoomComponent(id: "lower", title: "", category: "", symbol: "", summary: "", z: 1, polygons: [square])
    let upper = RoomComponent(id: "upper", title: "", category: "", symbol: "", summary: "", z: 2, polygons: [square])
    let overlap = RoomComponentCatalog(source: "test", sceneID: "test", canvas: Point2(100, 100), components: [upper, lower])
    try expect(overlap.component(at: Point2(10, 10))?.id == "upper", "highest furniture z wins overlap")
    let islands = RoomComponent(id: "islands", title: "", category: "", symbol: "", summary: "", z: 1,
                                polygons: [square, square.map { Point2($0.x + 40, $0.y) }])
    try expect(islands.contains(Point2(50, 10)) && !islands.contains(Point2(30, 10)), "separate polygons preserve their gap")

    let rig = try RigManifest.load(from: assets.appendingPathComponent("rig.json"))
    let scene = try AvatarScene(manifest: rig, resourceDirectory: assets)
    var lastSelection: String?
    scene.onComponentSelection = { lastSelection = $0?.id }
    scene.setAnimationPaused(true)
    scene.hoverRoom(at: CGPoint(x: 1120, y: 941 - 280))
    try expect(scene.hoveredComponent?.id == "fan-1", "hover converts SpriteKit bottom-left coordinates while paused")
    scene.selectRoom(at: CGPoint(x: 1500, y: 941 - 600))
    try expect(lastSelection == "compute" && scene.selectedComponent?.id == "compute", "click forwards stable component ID")
    scene.selectRoomComponent("chair")
    try expect(lastSelection == "chair", "menu can select a component covered by the avatar")
    scene.hoverRoom(at: nil)
    try expect(scene.hoveredComponent == nil, "pointer exit removes hover")
    scene.selectRoom(at: CGPoint(x: 50, y: 850))
    try expect(lastSelection == nil, "empty room click dismisses details")
    scene.selectRoomComponent("bed"); scene.focused = true
    try expect(scene.selectedComponent == nil && lastSelection == nil, "avatar-only mode dismisses details")
    scene.hoverRoom(at: CGPoint(x: 1120, y: 941 - 280)); scene.selectRoomComponent("fan-1")
    try expect(scene.hoveredComponent == nil && scene.selectedComponent == nil, "hidden room cannot be selected")
    scene.focused = false; scene.selectRoomComponent("fan-2")
    try expect(lastSelection == "fan-2", "selection resumes when room is visible")
}
