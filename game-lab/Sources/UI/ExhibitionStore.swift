import Foundation
import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

@MainActor
final class ExhibitionStore: ObservableObject {
    @Published private(set) var route: ExhibitionRoute = .lobby
    @Published private(set) var visitedGameIDs: Set<String> = []
    @Published private(set) var saveError = ""
    @Published private(set) var saveMessage = ""
    @Published private(set) var experienceProgress: [ExperienceProgressSnapshot] = []

    private var progress = ExhibitionProgress()
    private let saveURL: URL
    private var damagedSave = false

    init(saveURL: URL? = nil) {
        let args = ProcessInfo.processInfo.arguments
        let override: URL? = args.firstIndex(of: "--exhibition-save").flatMap { index in
            index + 1 < args.count ? URL(fileURLWithPath: args[index + 1]) : nil
        }
        self.saveURL = saveURL ?? override ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/aibou-game-lab/exhibition-v1.json")
        refreshExperienceProgress()
        guard FileManager.default.fileExists(atPath: self.saveURL.path) else { return }
        do {
            progress = try ExhibitionProgress.load(from: self.saveURL)
            visitedGameIDs = progress.visitedGameIDs
            route = progress.lastAreaID.map(ExhibitionRoute.area) ?? .lobby
            saveMessage = "前回の展示室に戻りました"
        } catch {
            damagedSave = true
            saveError = "展示館の記録を読み込めませんでした。移動するときに元の記録を別名で残します。ゲームの作品は別に保存されています。"
        }
    }

    var currentAreaID: ExhibitionAreaID? {
        switch route {
        case .lobby: return nil
        case .area(let id): return id
        case .entry(let id), .playing(let id): return ExhibitionCatalog.game(id)?.areaID
        }
    }

    func goToLobby() {
        refreshExperienceProgress()
        route = .lobby
        progress.navigate(to: nil)
        persist()
    }

    func visitArea(_ id: ExhibitionAreaID) {
        refreshExperienceProgress()
        route = .area(id)
        progress.navigate(to: id)
        persist()
    }

    func openGame(_ id: String) {
        refreshExperienceProgress()
        guard ExhibitionCatalog.game(id) != nil else { return }
        progress.visit(id)
        visitedGameIDs = progress.visitedGameIDs
        route = .entry(id)
        persist()
    }

    @discardableResult
    func startGame(_ id: String) -> Bool {
        guard ExhibitionCatalog.game(id)?.isPlayable == true else { return false }
        progress.visit(id)
        visitedGameIDs = progress.visitedGameIDs
        route = .playing(id)
        persist()
        return true
    }

    func goBack() {
        switch route {
        case .lobby: break
        case .area: goToLobby()
        case .entry(let id), .playing(let id):
            if let area = ExhibitionCatalog.game(id)?.areaID { visitArea(area) }
            else { goToLobby() }
        }
    }

    func status(for game: ExhibitionGame, workshop: WorkshopSnapshot) -> ExhibitionGameStatus {
        if let progress = experienceProgress.first(where: { $0.gameID == game.id }) {
            if progress.artifactCount > 0 { return .completed }
            if progress.started { return .inProgress }
        }
        return .resolve(game: game, visited: visitedGameIDs.contains(game.id), workshop: workshop)
    }

    func refreshExperienceProgress() { experienceProgress = ExperienceProgressIndex.snapshots() }
    func progress(for gameID: String) -> ExperienceProgressSnapshot? { experienceProgress.first { $0.gameID == gameID } }

    func retrySave() { persist() }

    private func persist() {
        do {
            if damagedSave {
                let backup = saveURL.deletingLastPathComponent()
                    .appendingPathComponent("exhibition-unreadable-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: saveURL, to: backup)
                damagedSave = false
            }
            try progress.save(to: saveURL)
            saveError = ""
            saveMessage = "このMacに保存済み"
        } catch {
            saveError = "展示館の記録を保存できませんでした。画面を開いている間は、このまま探索できます。"
            saveMessage = "未保存"
        }
    }
}
