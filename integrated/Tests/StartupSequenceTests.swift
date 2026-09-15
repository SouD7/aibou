import Foundation
import ImageIO

@main
struct StartupSequenceTests {
    static func main() throws {
        let assets = URL(fileURLWithPath: "../Asset/StartupMotion/Smooth", isDirectory: true)
        let sequence = try StartupSequence.load(from: assets)
        precondition(sequence.frames.count == 54 && sequence.fps == 24 && sequence.durationSeconds == 2.25)
        precondition(sequence.frameIndex(at: -1) == 0)
        precondition(sequence.frameIndex(at: 0) == 0)
        precondition(sequence.frameIndex(at: 1 / 24) == 1)
        precondition(sequence.frameIndex(at: 1) == 24)
        precondition(sequence.frameIndex(at: 2.25) == 53)
        precondition(sequence.frameIndex(at: 100) == 53)
        for file in sequence.frames {
            let url = assets.appendingPathComponent(file)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                fatalError("Unreadable frame: \(file)")
            }
            precondition(properties[kCGImagePropertyPixelWidth] as? Int == sequence.width)
            precondition(properties[kCGImagePropertyPixelHeight] as? Int == sequence.height)
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let manifest = assets.appendingPathComponent("sequence.json")
        try FileManager.default.copyItem(at: manifest, to: temporary.appendingPathComponent("sequence.json"))
        do {
            _ = try StartupSequence.load(from: temporary)
            fatalError("Missing frames must fail validation")
        } catch is CocoaError { }
        for file in sequence.frames {
            try FileManager.default.createSymbolicLink(at: temporary.appendingPathComponent(file),
                                                       withDestinationURL: assets.appendingPathComponent(file))
        }
        _ = try StartupSequence.load(from: temporary)
        for fps in [0, -24] {
            let data = try JSONSerialization.data(withJSONObject: ["width": 1672, "height": 941,
                "fps": fps, "durationSeconds": 2.25, "frames": sequence.frames])
            try data.write(to: temporary.appendingPathComponent("sequence.json"))
            do {
                _ = try StartupSequence.load(from: temporary)
                fatalError("Invalid frame rate must fail validation")
            } catch is CocoaError { }
        }
        print("StartupSequenceTests: OK (54 asset frames, timing boundaries, missing assets, invalid fps)")
    }
}
