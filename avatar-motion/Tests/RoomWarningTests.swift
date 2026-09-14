import Foundation
import AppKit

func testRoomWarnings() throws {
    let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    let rig = try RigManifest.load(from: assets.appendingPathComponent("rig.json"))
    let scene = try AvatarScene(manifest: rig, resourceDirectory: assets)
    let warning = ComponentWarning(message: "テスト警告")
    var notifications = 0
    scene.onWarningsChange = { _ in notifications += 1 }
    try expect(scene.componentWarnings.isEmpty, "initial state has no detected or demo warnings")
    try expect(!scene.setComponentWarning(warning, for: "unknown"), "unknown component rejected")
    try expect(notifications == 0, "unknown input does not publish")
    scene.setAnimationPaused(true)
    try expect(scene.setComponentWarning(warning, for: "compute"), "known warning accepted while paused")
    scene.setComponentWarning(warning, for: "compute")
    try expect(notifications == 1 && scene.componentWarnings.count == 1, "same warning is idempotent")
    scene.setComponentWarning(warning, for: "bed")
    scene.setComponentWarning(nil, for: "compute")
    try expect(scene.componentWarnings["bed"] == warning && scene.componentWarnings["compute"] == nil,
               "clearing one component preserves others")
    scene.replaceComponentWarnings(["fan-1": warning, "unknown": warning])
    try expect(Set(scene.componentWarnings.keys) == ["fan-1"], "snapshot clears missing IDs and ignores unknown IDs")

    let badges = RoomWarningBadges(catalog: scene.componentCatalog)
    let fan = try XCTUnwrap(scene.componentCatalog.components.first { $0.id == "fan-1" }, "fan component")
    let anchor = badges.anchor(for: fan)
    scene.hoverRoom(at: anchor)
    try expect(scene.hoveredComponent?.id == "fans", "warning badge is hoverable outside the original component")
    scene.selectRoom(at: anchor)
    try expect(scene.selectedComponent?.id == "fans", "badge opens matching component")
    scene.selectRoomComponent(nil)
    try expect(scene.componentWarnings["fan-1"] == warning, "closing details does not acknowledge or clear a warning")
    scene.focused = true; scene.selectRoom(at: anchor)
    try expect(scene.selectedComponent == nil && scene.componentWarnings.count == 1, "avatar-only mode hides but retains warnings")
    scene.focused = false; scene.selectRoom(at: anchor)
    try expect(scene.selectedComponent?.id == "fans", "retained badge works after returning to room")
    scene.replaceComponentWarnings([:])
    scene.hoverRoom(at: anchor)
    try expect(scene.componentWarnings.isEmpty && scene.hoveredComponent == nil, "cleared badge no longer catches pointer")

    let all = Dictionary(uniqueKeysWithValues: scene.componentCatalog.components.map { ($0.id, warning) })
    badges.update(all, reducedMotion: true)
    try expect(badges.badges.count == 11, "all eleven components support warning badges")
    for component in scene.componentCatalog.components {
        let node = try XCTUnwrap(badges.badges[component.id], "badge \(component.id)")
        try expect(node.xScale == 1 && !node.hasActions(), "reduced motion has no pop animation")
        try expect(node.position.x >= 30 && node.position.x <= 1642 && node.position.y >= 36 && node.position.y <= 911,
                   "badge stays inside visible canvas")
        try expect(badges.componentID(at: node.position) == component.id, "badge centers have distinct hit targets")
    }
    let original = badges.badges["bed"]
    badges.update(all, reducedMotion: false)
    try expect(badges.badges["bed"] === original, "unchanged snapshots reuse badge nodes")
    badges.update([:], reducedMotion: false)
    try expect(badges.badges.isEmpty && badges.children.isEmpty, "clearing removes visual nodes")
    let decoded = try JSONDecoder().decode(ComponentWarning.self, from: JSONEncoder().encode(warning))
    try expect(decoded == warning, "backend display payload round-trip")
}
