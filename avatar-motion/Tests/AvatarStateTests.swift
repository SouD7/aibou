import Foundation
import SpriteKit

func testAvatarStates() throws {
    try testNewStateMetadata()
    try testGlitchCadence()
    try testCloseUpEntrance()
    try testWritingAndRestMotion()
    try testNewStateSceneBehavior()
}

private func testNewStateMetadata() throws {
    let selectable: [AvatarPoseID] = [.writing, .cpuRest, .glitch, .closeUp]
    try expect(selectable.allSatisfy { AvatarPoseID.primaryModes.contains($0) },
               "all four new avatar states are selectable")
    try expect(AvatarPoseID.glitch.hasActiveFace && AvatarPoseID.closeUp.hasActiveFace,
               "standing-derived glitch and face close-up retain facial motion")
    try expect(!AvatarPoseID.writing.hasActiveFace && !AvatarPoseID.cpuRest.hasActiveFace,
               "writing and resting artwork keep their authored faces")
    for state in selectable {
        try expect(ElectricTransition.requiresEffect(from: .standing, to: state),
                   "entering \(state.rawValue) requires the electric effect")
        try expect(ElectricTransition.requiresEffect(from: state, to: .standing),
                   "leaving \(state.rawValue) requires the electric effect")
    }
    try expect(!ElectricTransition.requiresEffect(from: .standing, to: .standingBackHands),
               "legacy standing-variant swaps remain direct")

    for state in [AvatarPoseID.glitch, .closeUp] {
        let output = MotionMath.output(for: state,
            input: MotionInput(time: 4.42, speechAmplitude: 0.8, forceBlink: 1))
        try expect(output.blink == 1 && output.mouthOpen > 0,
                   "\(state.rawValue) preserves standing-style face animation")
    }
}

private func testGlitchCadence() throws {
    let samples = stride(from: 0.0, through: 12.0, by: 0.01).map {
        (time: $0, progress: GlitchCadence.noiseProgress(at: $0))
    }
    let active = samples.filter { $0.progress != nil }
    try expect(!active.isEmpty, "glitch state periodically activates arrival-style noise")
    try expect(active.allSatisfy { (0..<1).contains($0.progress!) },
               "periodic glitch progress remains normalized")

    var starts: [Double] = []
    for index in samples.indices.dropFirst() where samples[index].progress != nil && samples[index - 1].progress == nil {
        starts.append(samples[index].time)
    }
    try expect(starts.count >= 4, "glitch repeats several times over twelve seconds")
    let intervals = zip(starts.dropFirst(), starts).map { $0.0 - $0.1 }
    try expect(intervals.allSatisfy { (1.4...2.7).contains($0) },
               "glitch recurs roughly every two seconds")
    let roundedIntervals = Set(intervals.map { Int(($0 * 100).rounded()) })
    try expect(roundedIntervals.count > 1, "glitch intervals vary instead of looping mechanically")

    var durations: [Double] = []
    var pulseStart: Double?
    for sample in samples {
        if sample.progress != nil, pulseStart == nil { pulseStart = sample.time }
        if sample.progress == nil, let start = pulseStart {
            durations.append(sample.time - start); pulseStart = nil
        }
    }
    let roundedDurations = Set(durations.map { Int(($0 * 100).rounded()) })
    try expect(roundedDurations.count > 1, "glitch pulse durations vary")
}

private func testCloseUpEntrance() throws {
    let height = 941.0
    let before = CloseUpEntranceTiming.sample(atTransitionElapsed: 0.99, canvasHeight: height)
    try expect(before.alpha == 0 && before.verticalOffset < 0 && !before.finished,
               "close-up waits below the screen until the beam completes")

    let start = CloseUpEntranceTiming.sample(atTransitionElapsed: CloseUpEntranceTiming.startsAt,
                                              canvasHeight: height)
    try expect(start.alpha == 0 && start.verticalOffset < 0,
               "close-up begins transparent and below its destination")

    let moving = CloseUpEntranceTiming.sample(atTransitionElapsed: 1.12, canvasHeight: height)
    try expect(moving.alpha > 0 && moving.alpha <= 1 && moving.verticalOffset > start.verticalOffset,
               "close-up fades in while moving upward quickly")

    let overshoot = CloseUpEntranceTiming.sample(atTransitionElapsed: 1.22, canvasHeight: height)
    try expect(overshoot.alpha == 1 && overshoot.verticalOffset > 0 && overshoot.scale > 1,
               "close-up passes its final position at full visibility")
    let bounce = CloseUpEntranceTiming.sample(atTransitionElapsed: 1.40, canvasHeight: height)
    try expect(bounce.verticalOffset < 0 && bounce.scale < 1,
               "close-up makes one smaller return bounce")

    let settled = CloseUpEntranceTiming.sample(
        atTransitionElapsed: CloseUpEntranceTiming.startsAt + CloseUpEntranceTiming.duration,
        canvasHeight: height)
    try expect(settled == CloseUpEntranceSample(alpha: 1, verticalOffset: 0, scale: 1, finished: true),
               "close-up settles fully visible at its authored position")
}

private func testWritingAndRestMotion() throws {
    let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    let rig = try RigManifest.load(from: assets.appendingPathComponent("rig.json"))
    let writing = try XCTUnwrap(rig.pose(.writing), "real writing pose")
    let movingInput = MotionInput(time: 1, strength: 1)
    for chairPoint in [Point2(0.18, 0.48), Point2(0.30, 0.72), Point2(0.52, 0.82)] {
        try expect(MotionMath.displacement(at: chairPoint, pose: writing, input: movingInput) == Point2(0, 0),
                   "writing pose keeps chair vertex \(chairPoint) rigid")
    }
    let writingChest = MotionMath.displacement(at: writing.chest, pose: writing, input: movingInput)
    try expect(abs(writingChest.x) + abs(writingChest.y) > 0.000001,
               "writing upper body continues breathing above the rigid chair")

    let resting = try XCTUnwrap(rig.pose(.cpuRest), "real CPU-rest pose")
    let head = MotionMath.displacement(at: resting.head, pose: resting, input: movingInput)
    let knee = MotionMath.displacement(at: Point2(0.50, 0.88), pose: resting, input: movingInput)
    let chest = MotionMath.displacement(at: resting.chest, pose: resting, input: movingInput)
    try expect(head == Point2(0, 0), "CPU-rest face contact remains fixed")
    try expect(knee == Point2(0, 0), "CPU-rest knee contact remains fixed")
    try expect(abs(chest.x) + abs(chest.y) > 0.000001,
               "CPU-rest chest breathes while face and knee contacts stay anchored")
}

private func testNewStateSceneBehavior() throws {
    let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    let rig = try RigManifest.load(from: assets.appendingPathComponent("rig.json"))
    try expect(rig.pose(.closeUp)?.entranceImage == "standing-smile-crescent.png",
               "close-up declares its smiling entrance artwork")
    let scene = try AvatarScene(manifest: rig, resourceDirectory: assets)

    func noiseVisible(_ pose: AvatarPoseID) -> Bool {
        scene.childNode(withName: "\(pose.rawValue)/arrival-noise")?.isHidden == false
    }

    scene.selectPose(.standing, animated: false)
    scene.setDeterministicTime(0)
    scene.selectPose(.glitch)
    scene.setDeterministicTime(0.5)
    try expect(scene.poseTransition == nil && scene.currentPose == .glitch,
               "glitch state first completes the standard electric transition")

    let pulseTime = stride(from: 0.5, through: 8.0, by: 0.01).first {
        GlitchCadence.noiseProgress(at: $0) != nil
    }
    let activeTime = try XCTUnwrap(pulseTime, "deterministic glitch pulse")
    scene.setDeterministicTime(activeTime)
    try expect(noiseVisible(.glitch), "glitch state renders the periodic arrival-noise effect")
    scene.setAnimationPaused(true)
    try expect(!noiseVisible(.glitch), "pausing clears periodic glitch noise")
    scene.setAnimationPaused(false)
    scene.reducedMotion = true
    scene.setDeterministicTime(activeTime)
    try expect(!noiseVisible(.glitch), "reduced motion suppresses periodic glitch noise")
    scene.reducedMotion = false
    scene.selectPose(.writing, animated: false)
    try expect(!noiseVisible(.glitch), "leaving glitch clears its noise layer")

    let renderer = try XCTUnwrap(scene.childNode(withName: "room-states") as? RoomStateRenderer,
                                 "room state renderer")
    renderer.apply(state: scene.visualState, time: 0.35, reducedMotion: false, roomFrameIndex: 2)
    try expect(renderer.writingBackdropFrameIndex == 2,
               "writing backdrop follows a supplied nonuniform room frame instead of deriving it from time")
    renderer.apply(state: scene.visualState, time: 9.9, reducedMotion: true, roomFrameIndex: 0)
    try expect(renderer.writingBackdropFrameIndex == 0,
               "static room fallback keeps the writing backdrop on frame zero")
    scene.applyFrame(0.35)
    try expect(renderer.writingBackdropFrameIndex == scene.roomFrameIndex,
               "scene keeps writing backdrop and animated room on the same frame")
    let writingBackdrop = try XCTUnwrap(renderer.childNode(withName: "writing-backdrop"), "writing backdrop")
    let roomChair = try XCTUnwrap(renderer.childNode(withName: "chair"), "room chair")
    try expect(!writingBackdrop.isHidden && roomChair.isHidden,
               "settled writing swaps in its occupied backdrop without a second chair")
    scene.setComponentVisualState("stacked", for: "desk")
    try expect(!writingBackdrop.isHidden && roomChair.isHidden,
               "desk state changes preserve the occupied writing backdrop")
    scene.selectPose(.standing, animated: false)
    try expect(writingBackdrop.isHidden && !roomChair.isHidden,
               "leaving writing restores the selected desk state and room chair")
    scene.setComponentVisualState("normal", for: "desk")
    try expect(writingBackdrop.isHidden && roomChair.isHidden,
               "normal desk state restores its original chair visibility")
    scene.setDeterministicTime(9)
    scene.selectPose(.writing)
    scene.setDeterministicTime(9.15)
    try expect(writingBackdrop.isHidden, "writing backdrop stays hidden during the beam")
    scene.setDeterministicTime(9.2)
    try expect(!writingBackdrop.isHidden && roomChair.isHidden,
               "writing backdrop appears exactly with the incoming pose")
    scene.selectPose(.standing, animated: false)

    scene.setDeterministicTime(10)
    scene.selectPose(.closeUp)
    scene.setDeterministicTime(10.5)
    let closeUp = try XCTUnwrap(
        scene.childNode(withName: AvatarPoseID.closeUp.rawValue) as? PoseVisual, "close-up visual")
    try expect(closeUp.alpha == 0 && closeUp.position.y < 0,
               "close-up remains below the screen during the one-second wait")
    try expect(!noiseVisible(.closeUp), "close-up does not reveal arrival noise during its wait")
    scene.setDeterministicTime(11.12)
    try expect(closeUp.alpha > 0 && closeUp.isUsingEntranceArtwork,
               "close-up rises with its dedicated smiling entrance artwork")
    scene.setDeterministicTime(11.62)
    try expect(scene.poseTransition == nil && !closeUp.isUsingEntranceArtwork,
               "close-up restores neutral artwork when the bounce settles")

    scene.selectPose(.standing, animated: false)
    scene.setDeterministicTime(20)
    scene.selectPose(.closeUp)
    scene.setDeterministicTime(21.12)
    try expect(closeUp.isUsingEntranceArtwork, "close-up smile is active before interruption")
    scene.setAnimationPaused(true)
    let closeUpPose = try XCTUnwrap(rig.pose(.closeUp), "close-up manifest")
    try expect(scene.poseTransition == nil && closeUp.alpha == 1 && closeUp.xScale == 1 && closeUp.yScale == 1 &&
                   abs(closeUp.position.y - (rig.canvas.y - closeUpPose.center.y)) < 0.000001 &&
                   !closeUp.isUsingEntranceArtwork,
               "pausing settles the entrance and restores neutral artwork")

    scene.setAnimationPaused(false)
    scene.selectPose(.standing, animated: false)
    scene.setDeterministicTime(30)
    scene.selectPose(.closeUp)
    scene.setDeterministicTime(31.12)
    scene.reducedMotion = true
    try expect(scene.poseTransition == nil && !closeUp.isUsingEntranceArtwork,
               "reduced motion restores neutral close-up artwork")

    scene.reducedMotion = false
    scene.selectPose(.standing, animated: false)
    scene.setDeterministicTime(40)
    scene.selectPose(.closeUp)
    scene.setDeterministicTime(41.12)
    scene.focused = true
    try expect(scene.poseTransition == nil && !closeUp.isUsingEntranceArtwork,
               "focus changes restore neutral close-up artwork")
    scene.focused = false

    scene.selectPose(.standing, animated: false)
    scene.setDeterministicTime(50)
    scene.selectPose(.closeUp)
    scene.setDeterministicTime(51.12)
    scene.selectPose(.reading)
    scene.setDeterministicTime(51.62)
    try expect(!closeUp.isUsingEntranceArtwork,
               "a rapid queued selection restores neutral close-up artwork before the next route")
}
