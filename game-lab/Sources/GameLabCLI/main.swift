import CircuitCore
import Foundation

enum CLIError: Error, LocalizedError {
    case usage
    case replayTooLarge
    var errorDescription: String? {
        switch self {
        case .usage: return "Usage: GameLabCLI demo <output-directory> | replay <replay.json> [snapshot.json] | snapshot [seed]"
        case .replayTooLarge: return "Replay file exceeds the 2 MB limit."
        }
    }
}

func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}

func save<T: Encodable>(_ value: T, to url: URL) throws {
    var data = try encoder().encode(value)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
}

func printJSON<T: Encodable>(_ value: T) throws {
    FileHandle.standardOutput.write(try encoder().encode(value))
    FileHandle.standardOutput.write(Data([0x0A]))
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw CLIError.usage }
    switch command {
    case "demo":
        guard arguments.count == 2 else { throw CLIError.usage }
        let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var session = CircuitSession(seed: 42)
        // A known wrong gate, its correction, a live input change, and the optional prediction.
        try session.apply(.selectGate(.or))
        for link in CircuitLink.allCases { try session.apply(.toggleLink(link)) }
        try session.apply(.verify)
        guard session.state.verification == .failed else { fatalError("Demo fixture mismatch") }
        try session.apply(.selectGate(.and))
        for _ in 0..<4 { try session.apply(.step) }
        try session.apply(.setInputs(InputPair(a: true, b: true)))
        try session.apply(.predict(session.state.mission.evaluate(session.state.prediction.inputs)))
        let replayURL = directory.appendingPathComponent("demo-replay.json")
        let snapshotURL = directory.appendingPathComponent("demo-state.json")
        try save(session.replayDocument(), to: replayURL)
        try save(session.state, to: snapshotURL)
        let restored = try CircuitSession.replay(data: Data(contentsOf: replayURL))
        guard restored.state == session.state else { fatalError("Replay verification failed") }
        print("Created \(replayURL.path)")
        print("Created \(snapshotURL.path)")
        print("Replay verified: \(session.actions.count) actions, \(session.state.checks.count) passing truth-table rows.")
    case "replay":
        guard arguments.count == 2 || arguments.count == 3 else { throw CLIError.usage }
        let inputURL = URL(fileURLWithPath: arguments[1])
        let fileSize = try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize <= 2_000_000 else { throw CLIError.replayTooLarge }
        let session = try CircuitSession.replay(data: Data(contentsOf: inputURL))
        if arguments.count == 3 { try save(session.state, to: URL(fileURLWithPath: arguments[2])) }
        else { try printJSON(session.state) }
    case "snapshot":
        guard arguments.count <= 2 else { throw CLIError.usage }
        let seed: UInt64
        if arguments.count == 2 {
            guard let supplied = UInt64(arguments[1]) else { throw CLIError.usage }
            seed = supplied
        } else { seed = 1 }
        try printJSON(CircuitSession(seed: seed).state)
    default: throw CLIError.usage
    }
} catch {
    FileHandle.standardError.write(Data("GameLabCLI: \(error.localizedDescription)\n".utf8))
    exit(1)
}
