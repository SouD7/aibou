import Foundation
import AppKit

struct TestFailure: Error { let message: String }

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure(message: message) }
}

func fixtureManifest(chromaKey: Bool = false) throws -> RigManifest {
    let json = """
    {"canvas":[1672,941],"poses":[
      {"id":"standing","image":"standing.png","center":[870,615],"size":[300,450],
       "head":[0.5,0.16],"chest":[0.5,0.36],"hip":[0.5,0.60],
       "eyes":[[0.40,0.14,0.06,0.03],[0.54,0.14,0.06,0.03]],
       "mouth":[0.47,0.20,0.06,0.025],"skin":"#F4DCCF","chromaKey":\(chromaKey),
       "blinkImage":"standing-blink.png"},
      {"id":"sleeping","image":"sleeping.png","center":[900,650],"size":[520,280],
       "head":[0.72,0.45],"chest":[0.50,0.48],"hip":[0.30,0.55]},
      {"id":"reading","image":"reading.png","center":[900,580],"size":[350,460],
       "head":[0.5,0.16],"chest":[0.5,0.38],"hip":[0.5,0.64],"book":[0.35,0.38,0.3,0.16]}
    ]}
    """
    return try JSONDecoder().decode(RigManifest.self, from: Data(json.utf8))
}

func testManifest() throws {
    let rig = try fixtureManifest(chromaKey: true)
    try expect(rig.canvas == Point2(1672, 941), "canvas array decoding")
    let standing = try XCTUnwrap(rig.pose(.standing), "standing pose")
    try expect(standing.eyes.count == 2, "eye rectangles")
    try expect(standing.mouth == Rect4(0.47, 0.20, 0.06, 0.025), "mouth rectangle")
    try expect(standing.chromaKey, "chroma key option")
    try expect(standing.blinkImage == "standing-blink.png", "blink image option")
    let sleeping = try XCTUnwrap(rig.pose(.sleeping), "sleeping pose")
    try expect(sleeping.eyes.isEmpty && sleeping.mouth == nil && !sleeping.chromaKey, "optional defaults")
}

func testMotion() throws {
    let rig = try fixtureManifest()
    let standing = try XCTUnwrap(rig.pose(.standing), "standing pose")
    let still = MotionMath.displacement(at: standing.chest, pose: standing,
                                        input: MotionInput(time: 1, strength: 0))
    try expect(still == Point2(0, 0), "zero strength must be still")
    let contact = MotionMath.displacement(at: Point2(0.5, 1), pose: standing,
                                          input: MotionInput(time: 1, strength: 1))
    try expect(abs(contact.x) < 0.000001 && abs(contact.y) < 0.000001, "feet remain anchored")
    let moving = MotionMath.displacement(at: standing.chest, pose: standing,
                                         input: MotionInput(time: 1, strength: 1))
    let reduced = MotionMath.displacement(at: standing.chest, pose: standing,
                                          input: MotionInput(time: 1, strength: 1, reducedMotion: true))
    try expect(abs(reduced.y) < abs(moving.y), "reduced motion attenuates deformation")
    let grid = MotionMath.destinationGrid(columns: 16, rows: 24, pose: standing, input: MotionInput(time: 1))
    try expect(grid.count == 17 * 25, "16x24 grid vertex count")
    let source = MotionMath.sourceGrid(columns: 16, rows: 24)
    let identity = MotionMath.destinationGrid(columns: 16, rows: 24, pose: standing,
                                              input: MotionInput(time: 1, strength: 0))
    try expect(source == identity, "zero-strength warp is identity")
    try expect(source.first == SIMD2<Float>(0, 0) && source.last == SIMD2<Float>(1, 1),
               "SKWarp normalized corner bounds")
    let sleeping = MotionMath.output(for: .sleeping, input: MotionInput(time: 4.42, speechAmplitude: 1, forceBlink: 1))
    try expect(sleeping.blink == 0 && sleeping.mouthOpen == 0, "sleeping face remains closed")
    let reading = MotionMath.output(for: .reading, input: MotionInput(time: 11.15))
    try expect(reading.pageTurn > 0.8, "infrequent reading page turn")
}

func testEnvelope() throws {
    let envelope = AudioEnvelope(samplesPerSecond: 10, values: [0, 0.4, 1])
    try expect(abs(envelope.amplitude(at: 0.05) - 0.2) < 0.000001, "envelope interpolation")
    try expect(envelope.amplitude(at: 10) == 1, "envelope clamps at end")
    try expect(envelope.amplitude(at: -1) == 0, "negative time")
}

func testChromaKey() throws {
    let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let source = CGContext(data: nil, width: 3, height: 1, bitsPerComponent: 8, bytesPerRow: 12,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
    let sourceBytes = source.data!.bindMemory(to: UInt8.self, capacity: 12)
    [0, 255, 0, 255, 0, 230, 230, 255, 100, 170, 100, 255].enumerated().forEach { sourceBytes[$0.offset] = $0.element }
    let image = NSImage(cgImage: source.makeImage()!, size: NSSize(width: 3, height: 1))
    let result = try XCTUnwrap(ImageProcessing.removeGreenScreen(from: image), "processed image")
    let output = try XCTUnwrap(result.cgImage(forProposedRect: nil, context: nil, hints: nil), "output pixels")
    let probe = CGContext(data: nil, width: 3, height: 1, bitsPerComponent: 8, bytesPerRow: 12,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
    probe.draw(output, in: CGRect(x: 0, y: 0, width: 3, height: 1))
    let bytes = probe.data!.bindMemory(to: UInt8.self, capacity: 12)
    try expect(bytes[3] < 13, "pure green removed")
    try expect(bytes[7] > 230, "cyan preserved")
    try expect(bytes[11] > 20 && bytes[11] < 240, "green edge gets partial alpha")
    try expect(bytes[8] <= bytes[11] && bytes[9] <= bytes[11] && bytes[10] <= bytes[11],
               "translucent edge remains premultiplied")
}

func testFeatheredEyeCrop() throws {
    let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let source = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 400,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
    let sourceBytes = source.data!.bindMemory(to: UInt8.self, capacity: 100 * 80 * 4)
    for y in 0..<80 {
        for x in 0..<100 {
            let offset = (y * 100 + x) * 4
            let selectedTopRows = (20..<40).contains(y)
            sourceBytes[offset] = selectedTopRows ? 220 : 20
            sourceBytes[offset + 1] = 30
            sourceBytes[offset + 2] = selectedTopRows ? 20 : 220
            sourceBytes[offset + 3] = 255
        }
    }
    let image = NSImage(cgImage: source.makeImage()!, size: NSSize(width: 100, height: 80))
    let cropped = try XCTUnwrap(ImageProcessing.featheredCrop(from: image,
                                                              normalized: Rect4(0.2, 0.25, 0.4, 0.25)),
                                "feathered crop")
    let cg = try XCTUnwrap(cropped.cgImage(forProposedRect: nil, context: nil, hints: nil), "crop pixels")
    try expect(cg.width == 40 && cg.height == 20, "normalized crop dimensions")
    let probe = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
    probe.draw(cg, in: CGRect(x: 0, y: 0, width: 40, height: 20))
    let bytes = probe.data!.bindMemory(to: UInt8.self, capacity: 40 * 20 * 4)
    try expect(bytes[3] == 0, "patch edge is transparent")
    let centerAlpha = bytes[(10 * 40 + 20) * 4 + 3]
    try expect(centerAlpha > 250, "patch core stays opaque")
    let centerOffset = (10 * 40 + 20) * 4
    try expect(bytes[centerOffset] > bytes[centerOffset + 2], "crop honors top-left rig y coordinate")
}

func testRealAssets() throws {
    let assets = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    let rig = try RigManifest.load(from: assets.appendingPathComponent("rig.json"))
    try expect(rig.canvas == Point2(1672, 941), "real rig canvas")
    try expect(Set(rig.poses.map(\.id)) == Set(AvatarPoseID.allCases), "real rig has all poses")
    let standing = try XCTUnwrap(rig.pose(.standing), "real standing pose")
    let blinkName = try XCTUnwrap(standing.blinkImage, "real blink image declaration")
    try expect(FileManager.default.fileExists(atPath: assets.appendingPathComponent(blinkName).path),
               "real blink image resource")
    let scene = try AvatarScene(manifest: rig, resourceDirectory: assets)
    for pose in AvatarPoseID.allCases {
        scene.selectPose(pose); scene.setDeterministicTime(1.0)
        try expect(scene.currentPose == pose, "scene switches to \(pose.rawValue)")
    }
    let envelope = try AudioEnvelope.load(url: assets.appendingPathComponent("sample.aiff"))
    try expect(!envelope.values.isEmpty && (envelope.values.max() ?? 0) > 0, "real sample has a measured envelope")
    try expect(envelope.values.allSatisfy { (0...1).contains($0) }, "real sample envelope stays normalized")
}

func XCTUnwrap<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw TestFailure(message: message) }
    return value
}

@main
enum TestMain {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("manifest", testManifest), ("motion", testMotion),
            ("audio envelope", testEnvelope), ("chroma key", testChromaKey),
            ("feathered eye crop", testFeatheredEyeCrop),
            ("real assets", testRealAssets)
        ]
        var failures = 0
        for (name, test) in tests {
            do { try test(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        if failures > 0 { exit(1) }
        print("All \(tests.count) tests passed")
    }
}
