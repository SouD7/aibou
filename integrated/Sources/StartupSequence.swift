import Foundation

struct StartupSequence: Decodable {
    let width: Int
    let height: Int
    let fps: Double
    let durationSeconds: Double
    let frames: [String]

    static func load(from directory: URL) throws -> StartupSequence {
        let sequence = try JSONDecoder().decode(Self.self, from: Data(contentsOf: directory.appendingPathComponent("sequence.json")))
        guard sequence.width > 0, sequence.height > 0,
              sequence.fps.isFinite, sequence.fps > 0,
              sequence.durationSeconds.isFinite, sequence.durationSeconds > 0,
              !sequence.frames.isEmpty,
              abs(Double(sequence.frames.count) / sequence.fps - sequence.durationSeconds) < 0.001,
              sequence.frames.allSatisfy({ !$0.contains("/") && $0.hasSuffix(".png") &&
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return sequence
    }

    func frameIndex(at elapsed: TimeInterval) -> Int {
        min(frames.count - 1, Int((max(0, min(elapsed, durationSeconds)) * fps).rounded(.down)))
    }
}
