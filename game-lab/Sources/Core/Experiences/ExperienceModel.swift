import Foundation

public struct ExperienceMetric: Codable, Equatable, Identifiable {
    public var label: String
    public var value: String
    public var detail: String
    public var id: String { label }
    public init(_ label: String, _ value: String, detail: String = "") {
        self.label = label; self.value = value; self.detail = detail
    }
}

public protocol ExperienceModel: Codable, Equatable {
    associatedtype Action
    static var gameID: String { get }
    init(stage: Int)
    var stage: Int { get }
    var stageTitle: String { get }
    var goal: String { get }
    var guide: String { get }
    var hints: [String] { get }
    var isComplete: Bool { get }
    var metrics: [ExperienceMetric] { get }
    var isValid: Bool { get }
    mutating func send(_ action: Action)
}
public extension ExperienceModel {
    var isValid: Bool { (1...5).contains(stage) }
}

public struct ExperienceArtifact<M: ExperienceModel>: Codable, Equatable, Identifiable {
    public var id: UUID
    public var savedAt: Date
    public var model: M
    public init(model: M) { id = UUID(); savedAt = Date(); self.model = model }
}
public struct ExperienceReflection<M: ExperienceModel>: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var savedAt = Date()
    public var before: M
    public var after: M?
    public var prediction: String
    public var reason: String
    public var discovery = ""
    public init(before: M, prediction: String, reason: String) {
        self.before = before; self.prediction = prediction; self.reason = reason
    }
}
public struct ExperienceRecord<M: ExperienceModel>: Codable {
    public var version = 1
    public var gameID = M.gameID
    public var model: M
    public var undo: [M] = []
    public var completedStages: Set<Int> = []
    public var artifacts: [ExperienceArtifact<M>] = []
    public var comparisons: [M] = []
    public var actions: [String] = []
    public var hintLevels: [String: Int]? = [:]
    public var reflections: [ExperienceReflection<M>]? = []
    public init(model: M) { self.model = model }
    public var isValid: Bool {
        version == 1 && gameID == M.gameID && model.isValid && undo.count <= 100
        && undo.allSatisfy(\.isValid) && artifacts.count <= 50
        && artifacts.allSatisfy { $0.model.isValid && $0.model.isComplete }
        && completedStages.allSatisfy { (1...5).contains($0) }
        && comparisons.count <= 10 && comparisons.allSatisfy(\.isValid)
        && actions.count <= 1000
        && (hintLevels ?? [:]).allSatisfy { Int($0.key).map { (1...5).contains($0) } == true && (0...3).contains($0.value) }
        && (reflections ?? []).count <= 50
        && (reflections ?? []).allSatisfy { $0.before.isValid && ($0.after?.isValid ?? true) && $0.prediction.count <= 2000 && $0.reason.count <= 2000 && $0.discovery.count <= 2000 }
    }
}
