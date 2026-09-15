import Foundation
import SwiftUI

@main @MainActor
struct ExperienceStoreChecks {
    enum Failure: Error { case check(String) }
    static var count = 0
    static func check(_ value: Bool, _ label: String) throws {
        guard value else { throw Failure.check(label) }; count += 1
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-experience-contract-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cooling-workshop-v1.json")
        let store = ExperienceStore(CoolingModel(stage:1),saveURL:url)
        store.predict("速くすると熱がたまる",reason:"発熱が放熱より大きい")
        store.hintLevel = 2
        for _ in 0..<4 { store.send(.step) }
        store.rememberComparison()
        store.send(.fast(true))
        for _ in 0..<4 { store.send(.step) }
        try check(store.model.isComplete,"both controlled runs complete")
        store.recordDiscovery("仕事も増えるが熱は8残った")
        try check(store.saveArtifact(),"artifact persisted")
        let original = store.artifacts[0]
        let reopened = ExperienceStore(CoolingModel(stage:1),saveURL:url)
        try check(reopened.model == store.model,"exact model resumes")
        try check(reopened.reflections == store.reflections,"prediction and explanation resume")
        try check(reopened.record.hintLevels?["1"] == 2,"hint use survives actions/relaunch")
        try check(reopened.reflections[0].before.tick == 0 && reopened.reflections[0].after?.heat == 8,"before/after remain independent")
        reopened.selectStage(3)
        try check(reopened.artifacts[0] == original,"new stage retains immutable completed work")
        reopened.send(.step); let progressed = reopened.model
        reopened.undo(); try check(reopened.model.tick == 0,"undo restores model")
        reopened.send(.step); try check(reopened.model == progressed,"repeated action deterministic")
        let index = ExperienceProgressIndex.snapshot(for:"cooling-workshop",directory:directory)
        try check(index?.artifactCount == 1 && index?.completedStages == [1] && index?.stage == 3,"exhibition progress matches saved game")
        try check(ExperienceProgressIndex.snapshots(directory:directory).count == 20,"all twenty entries indexed")
        let bad = directory.appendingPathComponent("bottleneck-detective-v1.json")
        let bytes = Data("{not-valid-json".utf8); try bytes.write(to:bad)
        let damaged = ExperienceStore(BottleneckModel(stage:1),saveURL:bad)
        try check(damaged.blockedSave && !damaged.saveError.isEmpty,"corrupt save disclosed")
        damaged.send(.step)
        try check(try Data(contentsOf:bad) == bytes,"editing cannot overwrite unreadable save")
        try check(ExperienceProgressIndex.snapshot(for:"bottleneck-detective",directory:directory)?.readState == .unreadable,"index keeps unreadable distinct from missing")
        damaged.preserveUnreadableAndStart()
        let backup = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).first { $0.lastPathComponent.contains("-unreadable-") }
        try check(try backup.map { try Data(contentsOf:$0) } == bytes,"recovery retains exact source bytes")
        try check(!damaged.blockedSave && damaged.saveError.isEmpty,"explicit recovery resumes saving")
        let blocked = ExperienceStore(CoolingModel(stage:1),saveURL:directory)
        blocked.send(.step)
        try check(!blocked.saveError.isEmpty,"directory/write failure visible")
        print("ExperienceStore: \(count) checks passed with disposable saves only")
    }
}
