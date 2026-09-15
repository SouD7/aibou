import Foundation
#if canImport(CircuitCore)
import CircuitCore
#endif

/// A presentation-only copy of a validated game's saved artwork.
/// Opening a game still goes through its own ExperienceStore; this index never writes saves.
struct ExperienceArtifactSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let gameID: String
    let gameTitle: String
    let stage: Int
    let title: String
    let savedAt: Date
}

struct ExperienceProgressSnapshot: Identifiable, Equatable, Sendable {
    enum ReadState: Equatable, Sendable { case missing, loaded, unreadable }

    let gameID: String
    let readState: ReadState
    let stage: Int
    let stageTitle: String
    let completedStages: Set<Int>
    let started: Bool
    let latestDate: Date?
    let artifacts: [ExperienceArtifactSummary]
    let readError: String?

    var id: String { gameID }
    /// True even for an unreadable file, so the UI does not misrepresent it as a fresh game.
    var hasSave: Bool { readState != .missing }
    var hasValidSave: Bool { readState == .loaded }
    var canResume: Bool { hasValidSave }
    var artifactCount: Int { artifacts.count }
    var completedCount: Int { completedStages.count }
    var gameTitle: String { ExhibitionCatalog.game(gameID)?.title ?? gameID }
}

/// Read-only bridge from twenty ExperienceRecord files to the exhibition.
/// The older circuit Workshop record remains in its existing, separate store.
enum ExperienceProgressIndex {
    private static let maximumBytes = 8 * 1_024 * 1_024

    /// Matches ExperienceStore's directory resolution, with an explicit override for tests.
    static func saveDirectory(override: URL? = nil, arguments: [String] = ProcessInfo.processInfo.arguments) -> URL {
        if let override { return override }
        if let index = arguments.firstIndex(of: "--experience-save-dir"), index + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/aibou-game-lab/experiences", isDirectory: true)
    }

    /// Returns twenty entries in catalog order, including missing/unreadable states.
    static func snapshots(directory: URL? = nil) -> [ExperienceProgressSnapshot] {
        let resolved = saveDirectory(override: directory)
        return ExhibitionCatalog.games.compactMap { snapshot(for: $0.id, directory: resolved) }
    }

    /// Unknown games return nil.
    static func snapshot(for gameID: String, directory: URL? = nil) -> ExperienceProgressSnapshot? {
        let resolved = saveDirectory(override: directory)
        switch gameID {
        case CircuitExperienceModel.gameID: return read(CircuitExperienceModel.self, directory: resolved)
        case LogicBitArtModel.gameID: return read(LogicBitArtModel.self, directory: resolved)
        case LogicMemorySwitchModel.gameID: return read(LogicMemorySwitchModel.self, directory: resolved)
        case LogicTinySwitchModel.gameID: return read(LogicTinySwitchModel.self, directory: resolved)
        case LogicInstructionModel.gameID: return read(LogicInstructionModel.self, directory: resolved)
        case LogicWorkDispatchModel.gameID: return read(LogicWorkDispatchModel.self, directory: resolved)
        case ParallelFactoryModel.gameID: return read(ParallelFactoryModel.self, directory: resolved)
        case ParallelPixelModel.gameID: return read(ParallelPixelModel.self, directory: resolved)
        case MemoryDockModel.gameID: return read(MemoryDockModel.self, directory: resolved)
        case MemoryCacheModel.gameID: return read(MemoryCacheModel.self, directory: resolved)
        case MemoryRescueModel.gameID: return read(MemoryRescueModel.self, directory: resolved)
        case MemoryStorageModel.gameID: return read(MemoryStorageModel.self, directory: resolved)
        case ParallelDisplayModel.gameID: return read(ParallelDisplayModel.self, directory: resolved)
        case ParallelPacketModel.gameID: return read(ParallelPacketModel.self, directory: resolved)
        case ParallelBoardModel.gameID: return read(ParallelBoardModel.self, directory: resolved)
        case ParallelConnectionModel.gameID: return read(ParallelConnectionModel.self, directory: resolved)
        case MemoryPCDayModel.gameID: return read(MemoryPCDayModel.self, directory: resolved)
        case MemoryBatteryModel.gameID: return read(MemoryBatteryModel.self, directory: resolved)
        case CoolingModel.gameID: return read(CoolingModel.self, directory: resolved)
        case BottleneckModel.gameID: return read(BottleneckModel.self, directory: resolved)
        default: return nil
        }
    }

    /// Newest artwork first. The supplied snapshots let the caller perform one disk read per refresh.
    static func artworks(in snapshots: [ExperienceProgressSnapshot]) -> [ExperienceArtifactSummary] {
        snapshots.flatMap(\.artifacts).sorted {
            if $0.savedAt != $1.savedAt { return $0.savedAt > $1.savedAt }
            if $0.gameID != $1.gameID { return $0.gameID < $1.gameID }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func read<M: ExperienceModel>(_ type: M.Type, directory: URL) -> ExperienceProgressSnapshot {
        let file = directory.appendingPathComponent(M.gameID + "-v1.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return empty(type, state: .missing) }
        do {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= maximumBytes else {
                return empty(type, state: .unreadable, error: "記録の形式または大きさを確認できません。元の記録は保持しています。")
            }
            let data = try Data(contentsOf: file)
            guard data.count <= maximumBytes else { return empty(type, state: .unreadable, error: "記録が大きすぎるため読み込めません。元の記録は保持しています。") }
            let record = try JSONDecoder().decode(ExperienceRecord<M>.self, from: data)
            guard record.isValid,
                  Set(record.artifacts.map(\.id)).count == record.artifacts.count,
                  record.artifacts.allSatisfy({ $0.savedAt.timeIntervalSinceReferenceDate.isFinite }) else {
                return empty(type, state: .unreadable, error: "記録の内容を確認できません。元の記録は保持しています。")
            }
            let title = ExhibitionCatalog.game(M.gameID)?.title ?? M.gameID
            let artifacts = record.artifacts.map {
                ExperienceArtifactSummary(id: $0.id, gameID: M.gameID, gameTitle: title,
                                          stage: $0.model.stage, title: "\($0.model.stage) · \($0.model.stageTitle)", savedAt: $0.savedAt)
            }.sorted { $0.savedAt > $1.savedAt }
            let dates = artifacts.map(\.savedAt) + [values.contentModificationDate].compactMap { $0 }
            let started = record.model != M(stage: record.model.stage) || record.model.stage > 1
                || !record.actions.isEmpty || !record.undo.isEmpty || !record.comparisons.isEmpty
                || !record.completedStages.isEmpty || !record.artifacts.isEmpty
            return ExperienceProgressSnapshot(gameID: M.gameID, readState: .loaded,
                                              stage: record.model.stage, stageTitle: record.model.stageTitle,
                                              completedStages: record.completedStages, started: started,
                                              latestDate: dates.max(), artifacts: artifacts, readError: nil)
        } catch {
            return empty(type, state: .unreadable, error: "前の記録を読み込めません。元の記録は保持しています。")
        }
    }

    private static func empty<M: ExperienceModel>(_ type: M.Type, state: ExperienceProgressSnapshot.ReadState,
                                                   error: String? = nil) -> ExperienceProgressSnapshot {
        ExperienceProgressSnapshot(gameID: M.gameID, readState: state, stage: 1, stageTitle: M(stage: 1).stageTitle,
                                   completedStages: [], started: false, latestDate: nil, artifacts: [], readError: error)
    }
}
