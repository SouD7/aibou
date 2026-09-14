import Foundation
import SpriteKit

func testElectricTransition() throws {
    let transition = ElectricTransition(from: .standing, to: .sleeping, startedAt: 0,
                                        origin: CGPoint(x: 800, y: 550), destination: CGPoint(x: 250, y: 420))
    try expect(transition.sample(at: 0).outgoingAlpha == 0, "source vanishes immediately")
    let departure = transition.sample(at: 0.05)
    try expect(departure.incomingAlpha == 0 && departure.departure > 0 && departure.beam == 0,
               "first 0.1 seconds show only the spark burst")
    let beam = transition.sample(at: 0.1)
    try expect(beam.departure == 0 && beam.incomingAlpha == 0 && beam.beam == 1,
               "whole straight beam flashes at 0.1 seconds")
    let arrival = transition.sample(at: 0.2)
    try expect(arrival.beam == 0 && arrival.incomingAlpha == 1 && arrival.noiseProgress == 0,
               "target appears fully at 0.2 seconds with noise")
    try expect(transition.sample(at: 0.499).noiseProgress != nil, "noise lasts until 0.5 seconds")
    try expect(transition.sample(at: 0.5).finished && transition.sample(at: 0.5).noiseProgress == nil,
               "noise ends after exactly 0.3 seconds")
    let effect = ElectricTransitionEffect()
    effect.render(transition, at: 0.11)
    let path1 = (effect.children.first as? SKShapeNode)?.path
    effect.render(transition, at: 0.19)
    let path2 = (effect.children.first as? SKShapeNode)?.path
    try expect(path1 == path2, "beam geometry stays fixed instead of travelling")
    try expect(path1?.boundingBox == CGRect(x: 250, y: 420, width: 550, height: 130),
               "beam spans the entire direct route")

    let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    let rig = try RigManifest.load(from: assets.appendingPathComponent("rig.json"))
    let scene = try AvatarScene(manifest: rig, resourceDirectory: assets)
    func visible() -> [String] {
        scene.children.compactMap { node in
            guard node is PoseVisual, !node.isHidden, node.alpha > 0 else { return nil }
            return node.name
        }
    }
    // All directed room routes, including both standing variants, must settle cleanly.
    for from in AvatarPoseID.allCases {
        for to in AvatarPoseID.allCases where from != to {
            scene.selectPose(from, animated: false); scene.setDeterministicTime(0)
            scene.selectPose(to)
            if !(from.isStanding && to.isStanding) {
                scene.setDeterministicTime(0.15)
                try expect(visible().isEmpty, "\(from) to \(to) hides bodies during beam")
                try expect(scene.childNode(withName: "electric-transition")?.isHidden == false, "beam visible")
            }
            scene.setDeterministicTime(0.2)
            try expect(visible() == [to.rawValue], "target appears instantly after beam")
            if !(from.isStanding && to.isStanding) {
                try expect(scene.childNode(withName: "\(to.rawValue)/arrival-noise")?.isHidden == false,
                           "arrival displays texture interference")
            }
            scene.setDeterministicTime(0.5)
            try expect(scene.childNode(withName: "\(to.rawValue)/arrival-noise")?.isHidden == true,
                       "noise layer clears at completion")
            try expect(visible() == [to.rawValue] && scene.poseTransition == nil, "route completes with exactly one target")
            try expect(scene.childNode(withName: "electric-transition")?.isHidden == true, "effect removed after arrival")
        }
    }
    scene.selectPose(.standing, animated: false); scene.setDeterministicTime(0)
    scene.selectPose(.sleeping); scene.setDeterministicTime(0.3)
    scene.selectPose(.reading); scene.selectPose(.standingFrontHands)
    scene.setDeterministicTime(0.9); scene.setDeterministicTime(1.8)
    try expect(visible() == [AvatarPoseID.standingFrontHands.rawValue] && scene.poseTransition == nil,
               "rapid selections finish at latest target without stale bodies")
    scene.selectPose(.sleeping); scene.setDeterministicTime(2.05); scene.setAnimationPaused(true)
    try expect(scene.childNode(withName: "sleeping/arrival-noise")?.isHidden == true,
               "pause clears active noise slices")
    try expect(visible() == ["sleeping"] && scene.poseTransition == nil, "pausing settles active transition")
    scene.selectPose(.reading)
    try expect(visible() == ["reading"], "selection while paused stays visible")
    scene.setAnimationPaused(false); scene.selectPose(.standing); scene.reducedMotion = true
    try expect(visible() == ["standing"] && scene.poseTransition == nil, "reduced motion clears electricity")
    scene.selectPose(.sleeping)
    try expect(visible() == ["sleeping"] && scene.poseTransition == nil, "reduced motion switches without lightning")
    scene.reducedMotion = false; scene.selectPose(.reading); scene.focused = true
    try expect(visible() == ["reading"] && scene.poseTransition == nil, "focus change clears old room route")
}
