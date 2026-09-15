import Foundation

/// Session-only interaction state: acknowledgements deliberately never reach disk.
struct RoomSession {
    static let poseInterval: TimeInterval = 10
    private(set) var isDemo = false
    private(set) var isConsulting = false
    private(set) var dismissedWarnings: Set<String> = []
    private(set) var nextPoseAt: Date

    init(now: Date = Date()) { nextPoseAt = now.addingTimeInterval(Self.poseInterval) }

    mutating func enterDemo() { isDemo = true; isConsulting = false }
    mutating func leaveDemo(now: Date = Date()) {
        isDemo = false
        nextPoseAt = now.addingTimeInterval(Self.poseInterval)
    }
    mutating func beginConsultation() { isConsulting = true; isDemo = false }
    mutating func endConsultation(now: Date = Date()) {
        isConsulting = false
        nextPoseAt = now.addingTimeInterval(Self.poseInterval)
    }
    mutating func acknowledge(_ id: String) {
        dismissedWarnings.insert(Self.warningID(id))
    }
    func visibleWarnings(_ warnings: [String: ComponentWarning]) -> [String: ComponentWarning] {
        warnings.filter { !dismissedWarnings.contains(Self.warningID($0.key)) }
    }
    mutating func shouldChoosePose(now: Date) -> Bool {
        guard !isDemo, !isConsulting, now >= nextPoseAt else { return false }
        nextPoseAt = now.addingTimeInterval(Self.poseInterval)
        return true
    }
    private static func warningID(_ id: String) -> String {
        ["fan-1", "fan-2", "fans"].contains(id) ? "fans" : id
    }
}
