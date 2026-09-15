import AppKit
import Foundation
import SwiftUI

private struct ConsultationIntegrationFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ConsultationIntegrationFailure(description: message) }
}

private func descendantTextViews(in view: NSView) -> [NSTextView] {
    let own = (view as? NSTextView).map { [$0] } ?? []
    return own + view.subviews.flatMap(descendantTextViews)
}

@MainActor
private func settleInterface(_ host: NSView, duration: TimeInterval = 0.08) {
    host.needsLayout = true
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    host.layoutSubtreeIfNeeded()
}

@MainActor
private final class ConsultationBoundaryState: ObservableObject {
    @Published var roomVisible = true
}

private struct ConsultationBoundaryHarness: View {
    @ObservedObject var state: ConsultationBoundaryState
    @ObservedObject var model: ConsultationModel
    @ObservedObject var store: MonitorStore

    var body: some View {
        RoomConsultationSurface(model: model,
                                store: store,
                                isVisible: state.roomVisible)
            .frame(width: 900, height: 440)
            .environment(\.colorScheme, .light)
    }
}

@MainActor
private func hostConsultationBoundary(_ model: ConsultationModel,
                                      store: MonitorStore)
    -> (NSWindow, NSHostingView<AnyView>, ConsultationBoundaryState) {
    let state = ConsultationBoundaryState()
    let root = AnyView(ConsultationBoundaryHarness(state: state, model: model, store: store))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 440)
    let window = NSWindow(contentRect: host.frame,
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    settleInterface(host)
    return (window, host, state)
}

@MainActor
private func presentMonitorConsultation(on window: NSWindow,
                                        model: ConsultationModel,
                                        store: MonitorStore) -> (NSWindow, NSHostingView<AnyView>) {
    let root = AnyView(ConsultationView(model: model, store: store)
        .frame(width: 900, height: 700)
        .environment(\.colorScheme, .light))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
    let sheet = NSWindow(contentRect: host.frame,
                         styleMask: [.titled, .closable],
                         backing: .buffered,
                         defer: false)
    sheet.contentView = host
    window.beginSheet(sheet)
    settleInterface(host)
    return (sheet, host)
}

@MainActor
private func dismissMonitorConsultation(_ sheet: NSWindow,
                                        from window: NSWindow,
                                        state: ConsultationBoundaryState,
                                        host: NSView) {
    window.endSheet(sheet)
    sheet.close()
    state.roomVisible = true
    settleInterface(host)
}

@MainActor
private func hostConsultation(_ model: ConsultationModel,
                              store: MonitorStore) -> (NSWindow, NSHostingView<AnyView>) {
    let root = AnyView(RoomConsultationView(model: model, store: store)
        .frame(width: 900, height: 440)
        .environment(\.colorScheme, .light))
    let host = NSHostingView(rootView: root)
    host.frame = NSRect(x: 0, y: 0, width: 900, height: 440)
    let window = NSWindow(contentRect: host.frame,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
    window.contentView = host
    window.orderFront(nil)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    host.layoutSubtreeIfNeeded()
    return (window, host)
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

        try expect(RoomConsultationFlow.startsComposing(messages: [], question: ""),
                   "empty room starts with a composer")
        try expect(!RoomConsultationFlow.canAddQuestion(messages: [], busy: false, question: ""),
                   "追加 is hidden before a reply")

        model.executablePath = "/fixture/codex"
        await model.connect()
        try expect(model.connected && model.signedIn, "fixture connects as ChatGPT without network access")

        model.question = "最初の質問"
        model.responseLength = .short
        let firstDraft = model.makeDraft(attachment: nil)
        await model.send(firstDraft)
        try expect(model.busy, "first question waits for an answer")
        try expect(!RoomConsultationFlow.canAddQuestion(messages: model.messages,
                                                        busy: model.busy,
                                                        question: model.question),
                   "追加 stays hidden while the avatar is answering")
        connections[0].answer("最初の回答", turn: 1)
        try expect(RoomConsultationFlow.canAddQuestion(messages: model.messages,
                                                       busy: model.busy,
                                                       question: model.question),
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
        try expect(RoomConsultationFlow.canAddQuestion(messages: model.messages,
                                                       busy: model.busy,
                                                       question: model.question),
                   "conversation can continue after explicit retry")

        try expect(RoomConsultationFlow.shouldOfferNewConversation(error: "20往復に達しました。", busy: false),
                   "turn-limit error offers a new-conversation escape")
        try expect(!RoomConsultationFlow.shouldOfferNewConversation(error: "20往復に達しました。", busy: true),
                   "new conversation cannot race an active turn")

        model.question = "終了前に入力した追加質問"
        try expect(RoomConsultationFlow.startsComposing(messages: model.messages,
                                                        question: model.question),
                   "reentering an answered conversation restores a nonempty question")
        try expect(!RoomConsultationFlow.canAddQuestion(messages: model.messages,
                                                        busy: model.busy,
                                                        question: model.question),
                   "追加 cannot clear an existing unsent question")

        let preparedBeforeExit = model.makeDraft(attachment: nil)
        do {
            let (window, firstHost) = hostConsultation(model, store: store)
            try expect(firstHost.fittingSize.width > 0 && firstHost.fittingSize.height > 0,
                       "consultation with an unsent question lays out before exit")
            window.close()
        }

        // Dropping the first host models leaving consultation mode. A confirmation
        // payload is deliberately not persisted in the model, so a recreated host
        // must retain the editable text and require a newly prepared draft.
        let turnsBeforeReentry = connections[1].requests.filter { $0.method == "turn/start" }.count
        let (reopenedWindow, reopenedHost) = hostConsultation(model, store: store)
        defer { reopenedWindow.close() }
        try expect(model.question == preparedBeforeExit.question,
                   "recreating the consultation view preserves the editable question")
        try expect(descendantTextViews(in: reopenedHost).contains { $0.string == preparedBeforeExit.question },
                   "recreated consultation visibly restores the question editor")
        try expect(connections[1].requests.filter { $0.method == "turn/start" }.count == turnsBeforeReentry,
                   "reentry never sends a previously prepared draft automatically")
        let reconfirmedDraft = model.makeDraft(attachment: nil)
        try expect(reconfirmedDraft.transmittedText == preparedBeforeExit.transmittedText,
                   "a restored question can be prepared again for explicit confirmation")

        await model.send(reconfirmedDraft)
        try expect(model.messages.last?.text == "終了前に入力した追加質問",
                   "the explicitly reconfirmed restored question can be sent")
        connections[1].answer("再開後の回答", turn: 2)
        try expect(RoomConsultationFlow.canAddQuestion(messages: model.messages,
                                                       busy: model.busy,
                                                       question: model.question),
                   "the restored send flow completes and permits another question")

        // Keep one outer window alive while switching between the exact room
        // boundary and the monitor's real consultation sheet. This catches the
        // stale view-local state that previously survived a monitor round trip.
        let (boundaryWindow, boundaryHost, boundaryState) = hostConsultationBoundary(model, store: store)
        defer { boundaryWindow.close() }
        let turnsBeforeSheetLifecycle = connections[1].requests.filter { $0.method == "turn/start" }.count
        let interruptsBeforeSheetLifecycle = connections[1].requests.filter { $0.method == "turn/interrupt" }.count

        boundaryState.roomVisible = false
        settleInterface(boundaryHost, duration: 0.35)
        let (editingSheet, editingSheetView) = presentMonitorConsultation(on: boundaryWindow,
                                                                          model: model,
                                                                          store: store)
        model.question = "モニターで編集中の質問"
        settleInterface(editingSheetView)
        try expect(descendantTextViews(in: editingSheetView).contains { $0.string == model.question },
                   "the real monitor consultation sheet edits the shared question")

        dismissMonitorConsultation(editingSheet, from: boundaryWindow,
                                   state: boundaryState, host: boundaryHost)
        try expect(descendantTextViews(in: boundaryHost).contains { $0.string == "モニターで編集中の質問" },
                   "dismissing the monitor recreates a visible room editor with its latest draft")

        model.question = ""
        boundaryState.roomVisible = false
        settleInterface(boundaryHost)
        let (newConversationSheet, _) = presentMonitorConsultation(on: boundaryWindow,
                                                                   model: model,
                                                                   store: store)
        model.newConversation()
        settleInterface(boundaryHost)
        try expect(model.messages.isEmpty, "new conversation in the monitor clears the answered chat")
        dismissMonitorConsultation(newConversationSheet, from: boundaryWindow,
                                   state: boundaryState, host: boundaryHost)
        try expect(descendantTextViews(in: boundaryHost).contains { $0.string.isEmpty },
                   "dismissing a new empty conversation recreates an empty room editor")

        model.question = "部屋で入力中の質問"
        settleInterface(boundaryHost)
        let staleDraftSnapshot = model.makeDraft(attachment: nil)

        boundaryState.roomVisible = false
        settleInterface(boundaryHost)
        try expect(descendantTextViews(in: boundaryHost).isEmpty,
                   "opening the monitor removes the complete room consultation subtree")
        let (replacementDraftSheet, replacementDraftSheetView) = presentMonitorConsultation(on: boundaryWindow,
                                                                                             model: model,
                                                                                             store: store)
        model.question = "モニター側の新しい質問"
        settleInterface(replacementDraftSheetView)
        dismissMonitorConsultation(replacementDraftSheet, from: boundaryWindow,
                                   state: boundaryState, host: boundaryHost)
        try expect(model.question != staleDraftSnapshot.question,
                   "a draft captured before opening the monitor is no longer authoritative")
        try expect(descendantTextViews(in: boundaryHost).contains { $0.string == "モニター側の新しい質問" },
                   "recreating the room cannot overwrite a newer monitor draft")
        try expect(connections[1].requests.filter { $0.method == "turn/start" }.count == turnsBeforeSheetLifecycle,
                   "sheet lifecycle changes never send a question automatically")
        try expect(connections[1].requests.filter { $0.method == "turn/interrupt" }.count == interruptsBeforeSheetLifecycle,
                   "sheet lifecycle changes never interrupt a turn")

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
