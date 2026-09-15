import AppKit
import Foundation
import SwiftUI

private struct ConsultationIntegrationFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ConsultationIntegrationFailure(description: message) }
}

@MainActor
private final class RoomFixtureRPC: ConsultationRPC {
    let instance: Int
    var onNotification: ((String, [String: Any]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var requests: [(method: String, params: [String: Any])] = []
    private(set) var turnCount = 0
    var failNextTurnStart = false

    init(instance: Int) {
        self.instance = instance
    }

    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        requests.append((method, params))
        switch method {
        case "account/read":
            return ["account": ["type": "chatgpt", "planType": "fixture"]]
        case "thread/start":
            return ["thread": ["id": "thread-1"]]
        case "turn/start":
            if failNextTurnStart {
                failNextTurnStart = false
                throw ConsultationError.message("fixture disconnected before acknowledgement")
            }
            turnCount += 1
            return ["turn": ["id": "turn-\(turnCount)", "status": "inProgress"]]
        case "turn/interrupt":
            complete(turn: turnCount, status: "interrupted")
            return [:]
        default:
            return [:]
        }
    }

    func notify(_ method: String, _ params: [String: Any]) throws {
        requests.append((method, params))
    }

    func close() { }

    func answer(_ text: String, turn: Int) {
        onNotification?("item/completed", [
            "threadId": "thread-1",
            "turnId": "turn-\(turn)",
            "item": ["type": "agentMessage", "id": "answer-\(instance)-\(turn)", "text": text]
        ])
        complete(turn: turn)
    }

    func complete(turn: Int, status: String = "completed") {
        onNotification?("turn/completed", [
            "threadId": "thread-1",
            "turn": ["id": "turn-\(turn)", "status": status]
        ])
    }
}

@main
struct ConsultationIntegrationTests {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibou-room-consultation-\(UUID())", isDirectory: true)
        let preferenceName = "aibou-room-consultation-\(UUID())"
        guard let preferences = UserDefaults(suiteName: preferenceName) else {
            throw ConsultationIntegrationFailure(description: "isolated preferences unavailable")
        }
        preferences.removePersistentDomain(forName: preferenceName)

        var connections: [RoomFixtureRPC] = []
        let model = ConsultationModel(directory: directory, preferences: preferences) { _, _ in
            let rpc = RoomFixtureRPC(instance: connections.count + 1)
            connections.append(rpc)
            return rpc
        }
        let store = MonitorStore(directory: directory.appendingPathComponent("monitor", isDirectory: true))
        store.pause()
        defer {
            model.disconnect()
            store.shutdown()
            preferences.removePersistentDomain(forName: preferenceName)
            try? FileManager.default.removeItem(at: directory)
        }

        try expect(RoomConsultationFlow.startsComposing(messages: []), "empty room starts with a composer")
        try expect(!RoomConsultationFlow.canAddQuestion(messages: [], busy: false), "追加 is hidden before a reply")

        model.executablePath = "/fixture/codex"
        await model.connect()
        try expect(model.connected && model.signedIn, "fixture connects as ChatGPT without network access")

        model.question = "最初の質問"
        model.responseLength = .short
        let firstDraft = model.makeDraft(attachment: nil)
        await model.send(firstDraft)
        try expect(model.busy, "first question waits for an answer")
        try expect(!RoomConsultationFlow.canAddQuestion(messages: model.messages, busy: model.busy),
                   "追加 stays hidden while the avatar is answering")
        connections[0].answer("最初の回答", turn: 1)
        try expect(RoomConsultationFlow.canAddQuestion(messages: model.messages, busy: model.busy),
                   "追加 appears after the answer")

        model.question = "追加の質問"
        model.responseLength = .detailed
        let followupDraft = model.makeDraft(attachment: nil)
        await model.send(followupDraft)
        connections[0].answer("追加の回答", turn: 2)

        let starts = connections[0].requests.filter { $0.method == "thread/start" }
        let turns = connections[0].requests.filter { $0.method == "turn/start" }
        try expect(starts.count == 1 && turns.count == 2, "follow-up stays in the same ephemeral thread")
        let firstInput = (turns[0].params["input"] as? [[String: Any]])?.first?["text"] as? String
        let secondInput = (turns[1].params["input"] as? [[String: Any]])?.first?["text"] as? String
        try expect(firstInput == firstDraft.transmittedText && firstInput?.contains("短め") == true,
                   "first confirmation payload keeps its response length")
        try expect(secondInput == followupDraft.transmittedText && secondInput?.contains("詳しめ") == true,
                   "follow-up confirmation payload uses the current monitor setting")

        model.question = "切断された質問"
        let interruptedDraft = model.makeDraft(attachment: nil)
        connections[0].failNextTurnStart = true
        await model.send(interruptedDraft)
        try expect(!model.busy && !model.connected, "disconnect unlocks the room UI")
        try expect(model.messages.last?.delivery == .unconfirmed, "uncertain delivery remains visibly unconfirmed")
        try expect(RoomConsultationFlow.needsUnansweredRecovery(messages: model.messages, busy: model.busy),
                   "an unanswered interrupted question offers explicit re-entry")

        await model.connect()
        try expect(connections.count == 2, "reconnect creates a fresh backend session")
        try expect(!connections[1].requests.contains { $0.method == "turn/start" },
                   "reconnect never automatically resends an uncertain question")
        model.question = interruptedDraft.question
        let retryDraft = model.makeDraft(attachment: nil)
        await model.send(retryDraft)
        try expect(connections[1].requests.filter { $0.method == "thread/start" }.count == 1,
                   "explicit retry starts a fresh thread")
        connections[1].answer("再接続後の回答", turn: 1)
        try expect(RoomConsultationFlow.canAddQuestion(messages: model.messages, busy: model.busy),
                   "conversation can continue after explicit retry")

        try expect(RoomConsultationFlow.shouldOfferNewConversation(error: "20往復に達しました。", busy: false),
                   "turn-limit error offers a new-conversation escape")
        try expect(!RoomConsultationFlow.shouldOfferNewConversation(error: "20往復に達しました。", busy: true),
                   "new conversation cannot race an active turn")

        let host = NSHostingView(rootView: RoomConsultationView(model: model, store: store)
            .frame(width: 900, height: 440)
            .environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 440)
        host.layoutSubtreeIfNeeded()
        try expect(host.fittingSize.width > 0 && host.fittingSize.height > 0,
                   "room consultation view lays out in its integrated overlay size")

        print("ConsultationIntegrationTests: OK (fixture only; no login or inference)")
    }
}
