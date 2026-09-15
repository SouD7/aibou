import Foundation
import AppKit
import SpriteKit

enum RoomAnimationError: LocalizedError {
    case emptyFrames
    case durationCountMismatch
    case invalidDuration(index: Int)
    case invalidTotalDuration
    case missingManifest(URL)
    case missingFrame(String)
    case invalidFrameDimensions(name: String, actualWidth: Int, actualHeight: Int,
                                expectedWidth: Int, expectedHeight: Int)

    var errorDescription: String? {
        switch self {
        case .emptyFrames:
            return "RoomAnimation frames must not be empty."
        case .durationCountMismatch:
            return "RoomAnimation frames and durations must have the same count."
        case .invalidDuration(let index):
            return "RoomAnimation duration at index \(index) must be finite and greater than zero."
        case .invalidTotalDuration:
            return "RoomAnimation total duration must be finite and greater than zero."
        case .missingManifest(let url):
            return "RoomAnimation manifest is missing: \(url.path)"
        case .missingFrame(let name):
            return "RoomAnimation frame is missing or unreadable: \(name)"
        case let .invalidFrameDimensions(name, width, height, expectedWidth, expectedHeight):
            return "RoomAnimation frame \(name) is \(width)x\(height); expected \(expectedWidth)x\(expectedHeight)."
        }
    }
}

struct RoomAnimationManifest: Codable, Equatable {
    let source: String
    let frames: [String]
    let durations: [Double]

    var totalDuration: Double { durations.reduce(0, +) }

    init(source: String, frames: [String], durations: [Double]) throws {
        self.source = source; self.frames = frames; self.durations = durations
        try validate()
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(String.self, forKey: .source)
        frames = try values.decode([String].self, forKey: .frames)
        durations = try values.decode([Double].self, forKey: .durations)
        try validate()
    }

    private func validate() throws {
        guard !frames.isEmpty else { throw RoomAnimationError.emptyFrames }
        guard frames.count == durations.count else { throw RoomAnimationError.durationCountMismatch }
        for (index, duration) in durations.enumerated() where !duration.isFinite || duration <= 0 {
            throw RoomAnimationError.invalidDuration(index: index)
        }
        guard totalDuration.isFinite, totalDuration > 0 else { throw RoomAnimationError.invalidTotalDuration }
    }

    func frameIndex(at time: Double) -> Int {
        guard time.isFinite, time >= 0, !frames.isEmpty else { return 0 }
        let loopTime = time.truncatingRemainder(dividingBy: totalDuration)
        let minimumDuration = durations.min() ?? totalDuration
        let epsilon = min(minimumDuration * 0.25, max(1e-12, totalDuration * 1e-10))
        if loopTime <= epsilon || totalDuration - loopTime <= epsilon { return 0 }
        var boundary = 0.0
        for (index, duration) in durations.enumerated() {
            boundary += duration
            if loopTime < boundary - epsilon { return index }
        }
        return 0
    }

    static func load(from url: URL) throws -> RoomAnimationManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RoomAnimationError.missingManifest(url)
        }
        return try JSONDecoder().decode(RoomAnimationManifest.self, from: Data(contentsOf: url))
    }
}

final class AnimatedRoomNode: SKSpriteNode {
    let manifest: RoomAnimationManifest
    private let textures: [SKTexture]
    private(set) var frameIndex = 0

    init(directory: URL, canvas: Point2) throws {
        manifest = try RoomAnimationManifest.load(from: directory.appendingPathComponent("manifest.json"))
        let expectedWidth = Int(canvas.x.rounded())
        let expectedHeight = Int(canvas.y.rounded())
        var loaded: [SKTexture] = []
        loaded.reserveCapacity(manifest.frames.count)
        for name in manifest.frames {
            let url = directory.appendingPathComponent(name)
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw RoomAnimationError.missingFrame(name)
            }
            guard cgImage.width == expectedWidth, cgImage.height == expectedHeight else {
                throw RoomAnimationError.invalidFrameDimensions(name: name,
                    actualWidth: cgImage.width, actualHeight: cgImage.height,
                    expectedWidth: expectedWidth, expectedHeight: expectedHeight)
            }
            let texture = SKTexture(cgImage: cgImage)
            texture.filteringMode = .linear
            loaded.append(texture)
        }
        textures = loaded
        super.init(texture: loaded[0], color: .clear,
                   size: CGSize(width: canvas.x, height: canvas.y))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(time: Double, reducedMotion: Bool) {
        let nextIndex = reducedMotion ? 0 : manifest.frameIndex(at: time)
        guard nextIndex != frameIndex else { return }
        frameIndex = nextIndex
        texture = textures[nextIndex]
    }
}
