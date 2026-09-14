import Foundation
import SpriteKit

func testRoomVisualStates() throws {
    let defaults = RoomVisualState()
    let counts = ["bed":5,"bookshelf":3,"desk":3,"display":2,"fans":3,"network":3,"compute":3]
    for (id,count) in counts {
        let options = RoomVisualState.options(for:id)
        try expect(options.count == count, "requested state count for \(id)")
        for option in options {
            let state = try XCTUnwrap(defaults.applying(optionID:option.id,for:id), "valid option")
            try expect(state.currentOptionID(for:id) == option.id, "option round trip")
            let decoded = try JSONDecoder().decode(RoomVisualState.self,from:JSONEncoder().encode(state))
            try expect(decoded == state, "backend JSON round trip")
            for other in counts.keys where other != id {
                try expect(state.currentOptionID(for:other) == defaults.currentOptionID(for:other), "independent component state")
            }
        }
    }
    for value in ["-1","5","1.5","01"] {
        try expect(defaults.applying(optionID:value,for:"bed") == nil, "invalid battery count rejected")
    }
    for json in ["{\"bedLights\":5}","{\"fans\":\"turbo\"}"] {
        do { _ = try JSONDecoder().decode(RoomVisualState.self,from:Data(json.utf8)); throw TestFailure(message:"bad payload accepted") }
        catch is DecodingError {} catch is RoomVisualStateError {}
    }
    let assets = URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    let rig = try RigManifest.load(from:assets.appendingPathComponent("rig.json"))
    let scene = try AvatarScene(manifest:rig,resourceDirectory:assets)
    let renderer = try XCTUnwrap(scene.childNode(withName:"room-states") as? RoomStateRenderer,"state renderer")
    try expect(scene.componentCatalog.components.count == 11 && scene.componentCatalog.selectionComponents.count == 10,
               "two raw fan objects form one UI selection")
    for point in [CGPoint(x:1120,y:941-280),CGPoint(x:1205,y:941-275)] {
        scene.selectRoom(at:point)
        try expect(scene.selectedComponent?.id == "fans", "both fan click regions share details")
    }
    var updates = 0
    scene.onVisualStateChange = { _ in updates += 1 }
    try expect(!scene.setComponentVisualState("red",for:"chair"),"unknown state rejected")
    scene.setComponentVisualState("0",for:"bed"); scene.setComponentVisualState("0",for:"bed")
    try expect(updates == 1,"idempotent updates publish once")
    try expect(renderer.childNode(withName:"bed-0")?.isHidden == false && renderer.childNode(withName:"bed-4")?.isHidden == true,
               "zero light state replaces default lamp bank")
    scene.setComponentVisualState("stopped",for:"fan-1")
    scene.applyFrame(0.2); let still = (renderer.childNode(withName:"fan-1") as? SKSpriteNode)?.texture
    scene.applyFrame(0.8)
    try expect((renderer.childNode(withName:"fan-1") as? SKSpriteNode)?.texture === still && renderer.fanFrameIndex == 0,
               "stopped fans stay still while room continues")
    scene.setComponentVisualState("slow",for:"fans"); scene.applyFrame(0.23)
    let slow = renderer.fanFrameIndex
    scene.setComponentVisualState("fast",for:"fan-2"); scene.applyFrame(0.23)
    try expect(renderer.fanFrameIndex != slow && scene.visualState.fans == .fast,"fast speed differs and aliases control both fans")
    for frame in 0...12 {
        scene.applyFrame(Double(frame)/60)
        try expect(renderer.fanFrameIndex == frame % 12, "fast fan advances one full turn every 0.2 seconds")
    }
    for turn in 1...5 {
        scene.applyFrame(Double(turn)/5)
        try expect(renderer.fanFrameIndex == 0, "five full fast rotations per second")
    }
    scene.setComponentVisualState("staticNoise",for:"display");scene.applyFrame(0.1)
    let noise = renderer.displayFrameIndex; scene.applyFrame(0.2)
    try expect(noise != renderer.displayFrameIndex,"static noise animates")
    scene.setComponentVisualState("red",for:"compute")
    scene.setComponentVisualState("yellow",for:"network")
    scene.reducedMotion = true; scene.applyFrame(0.33)
    try expect(renderer.fanFrameIndex == 0 && renderer.computeFrameIndex == 0 && renderer.displayFrameIndex == 0,
               "reduced motion freezes local animation")
    scene.setAnimationPaused(true); scene.setComponentVisualState("sparse",for:"bookshelf")
    try expect(renderer.childNode(withName:"bookshelf-sparse")?.isHidden == false,"manual state changes work while paused")
    scene.focused = true
    try expect(renderer.isHidden && scene.visualState.compute == .red,"focus hides and retains states")
    scene.focused = false
    try expect(!renderer.isHidden && scene.visualState.network == .yellow,"return restores states")
    scene.setComponentWarning(ComponentWarning(message:"fan test"),for:"fans")
    try expect(scene.componentWarnings["fan-1"] != nil && scene.componentWarnings["fan-2"] != nil,"group warning targets both objects")
    scene.setComponentWarning(nil,for:"fans")
    try expect(scene.componentWarnings.isEmpty,"group warning clears both objects")
}
