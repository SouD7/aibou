import Foundation

public enum LessonStep: Int, CaseIterable, Codable, Sendable {
    case introduction, experiment, question, reflection
}

/// Completion requires an actual experiment and a correct transfer answer.
public struct LessonSession: Equatable, Sendable {
    public let lessonID: String
    public private(set) var step: LessonStep = .introduction
    public private(set) var explored = false
    public private(set) var selectedOption: Int?
    public private(set) var answeredCorrectly = false

    public init(lessonID: String) { self.lessonID = lessonID }

    public var canAdvance: Bool {
        switch step {
        case .introduction: return true
        case .experiment: return explored
        case .question: return answeredCorrectly
        case .reflection: return false
        }
    }
    public var isComplete: Bool { step == .reflection && explored && answeredCorrectly }

    public mutating func explore() {
        guard step == .experiment else { return }
        explored = true
    }
    public mutating func answer(_ index: Int) {
        guard step == .question, let lesson = LessonCatalog.lesson(lessonID),
              lesson.challenge.options.indices.contains(index) else { return }
        selectedOption = index
        answeredCorrectly = index == lesson.challenge.correctIndex
    }
    public mutating func advance() {
        guard canAdvance, let next = LessonStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }
    public mutating func back() {
        guard let previous = LessonStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}

public struct LessonProgress: Codable, Equatable, Sendable {
    public private(set) var version = 1
    public private(set) var completedIDs: Set<String> = []
    public private(set) var lastLessonID: String?

    public init() {}

    public mutating func visit(_ id: String) {
        guard LessonCatalog.lesson(id) != nil else { return }
        lastLessonID = id
    }
    public mutating func record(_ session: LessonSession) {
        guard session.isComplete, LessonCatalog.lesson(session.lessonID) != nil else { return }
        completedIDs.insert(session.lessonID)
    }
    public static func load(from url: URL) throws -> LessonProgress {
        var value = try JSONDecoder().decode(LessonProgress.self, from: Data(contentsOf: url))
        guard value.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        value.completedIDs = value.completedIDs.filter { LessonCatalog.lesson($0) != nil }
        if let id = value.lastLessonID, LessonCatalog.lesson(id) == nil { value.lastLessonID = nil }
        return value
    }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
