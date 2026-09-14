import Foundation
import AppKit
import SwiftUI

private func consultationExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw ConsultationError.message("Consultation test: " + message) }
}

@MainActor
private final class FixtureConsultationRPC: ConsultationRPC {
    var onNotification: ((String, [String: Any]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var requests: [(String, [String: Any])] = []
    var closed = false
    var accountType = "chatgpt"
    var turnCount = 0
    var earlyCompletion = false
    var failMethod: String?
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        requests.append((method, params))
        if failMethod == method { throw ConsultationError.message("fixture failure") }
        switch method {
        case "account/read": return ["account": ["type": accountType, "planType": "plus"]]
        case "account/login/start": return ["loginId": "login-1", "authUrl": "https://auth.openai.com/authorize?fixture=1"]
        case "thread/start": return ["thread": ["id": "thread-1"]]
        case "turn/start":
            turnCount += 1
            let id = "turn-\(turnCount)"
            if earlyCompletion { complete(id) }
            return ["turn": ["id": id, "status": "inProgress", "items": []]]
        case "turn/interrupt": complete("turn-\(turnCount)", status: "interrupted"); return [:]
        default: return [:]
        }
    }
    func notify(_ method: String, _ params: [String: Any]) throws { requests.append((method, params)) }
    func close() { closed = true }
    func delta(_ text: String, turn: String = "turn-1", thread: String = "thread-1") {
        onNotification?("item/agentMessage/delta", ["threadId": thread, "turnId": turn, "itemId": turn + "-answer", "delta": text])
    }
    func complete(_ id: String, status: String = "completed") {
        onNotification?("turn/completed", ["threadId": "thread-1", "turn": ["id": id, "status": status, "items": []]])
    }
}

@MainActor
func runConsultationTests() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let old = now.addingTimeInterval(-40)
    let collection = ObservationCollection(state: .paused, segmentID: "new", sampleSegmentID: "old", lastSampleAt: old)
    let panel = PanelReading(tab: .cpu, metrics: [
        Metric("idle", "Idle", value: 8, unit: "%", status: .partial, source: "/private/SECRET", detail: "SECRET", recordedAt: old),
        Metric("not-allowed", "Other", text: "SECRET", source: "fixture")
    ], rows: [ReadingRow(id: "SECRET", name: "SECRET", metrics: [], path: "/SECRET")], capturedAt: old)
    let thermal = PanelReading(tab: .thermal, metrics: [Metric("thermal_state", "熱", text: "重大", source: "fixture", recordedAt: old)])
    let memory = PanelReading(tab: .memory, metrics: [Metric("swapUsed", "swap", value: .nan, source: "fixture", recordedAt: old)])
    let attachment = ConsultationAttachment.make(collection: collection, panels: [panel, thermal, memory], now: now)
    let json = try attachment.json()
    try consultationExpect(!json.contains("SECRET") && !json.contains("not-allowed"), "private rows, detail, and arbitrary metrics excluded")
    try consultationExpect(attachment.collection.state == .paused && attachment.collection.sampleSegmentID == "old", "collection provenance preserved")
    try consultationExpect(attachment.readings.first?.status == .partial && attachment.readings.first?.recordedAt == old, "partial and stale time preserved")
    try consultationExpect(attachment.readings.last?.value == nil && json.contains("重大"), "nonfinite number omitted; critical thermal retained")
    let draft = ConsultationDraft(question: "重いです", attachment: json)
    try consultationExpect(draft.transmittedText.contains(json), "preview bytes passed unchanged")
    let expectedLengths: [(ConsultationResponseLength, String, String)] = [
        (.short, "短め", "100字程度"),
        (.standard, "標準", "200字程度"),
        (.detailed, "詳しめ", "400字程度")
    ]
    try consultationExpect(ConsultationResponseLength.allCases.count == expectedLengths.count, "three response lengths are available")
    for (length, label, guidanceFragment) in expectedLengths {
        let payload = ConsultationDraft(question: "質問-\(label)", attachment: json, responseLength: length).transmittedText
        try consultationExpect(length.label == label && length.guidance.contains(guidanceFragment), "\(label) label and guidance")
        try consultationExpect(payload.contains("今回の回答の長さ：\(label)") && payload.contains(length.guidance), "\(label) guidance included in payload")
        try consultationExpect(payload.contains("質問-\(label)") && payload.contains(json), "\(label) payload preserves question and attachment")
    }

    let preferencesName = "aibou-consultation-tests-\(UUID().uuidString)"
    guard let preferences = UserDefaults(suiteName: preferencesName) else {
        throw ConsultationError.message("Consultation test: isolated preferences unavailable")
    }
    preferences.removePersistentDomain(forName: preferencesName)
    defer { preferences.removePersistentDomain(forName: preferencesName) }
    let preferenceModel = ConsultationModel(directory: FileManager.default.temporaryDirectory, preferences: preferences)
    try consultationExpect(preferenceModel.responseLength == .standard, "missing response length defaults to standard")
    preferenceModel.responseLength = .detailed
    try consultationExpect(preferences.string(forKey: "consultationResponseLength") == ConsultationResponseLength.detailed.rawValue,
                           "response length persists")
    let restoredModel = ConsultationModel(directory: FileManager.default.temporaryDirectory, preferences: preferences)
    try consultationExpect(restoredModel.responseLength == .detailed, "persisted response length restores")
    preferences.set("future-value", forKey: "consultationResponseLength")
    let fallbackModel = ConsultationModel(directory: FileManager.default.temporaryDirectory, preferences: preferences)
    try consultationExpect(fallbackModel.responseLength == .standard, "unknown response length falls back to standard")
    fallbackModel.question = "確認画面の質問"
    fallbackModel.responseLength = .detailed
    let previewDraft = fallbackModel.makeDraft(attachment: json)
    fallbackModel.question = "確認後の質問"
    fallbackModel.responseLength = .short
    try consultationExpect(previewDraft.question == "確認画面の質問" && previewDraft.responseLength == .detailed,
                           "preview fixes question and response length")
    try consultationExpect(previewDraft.transmittedText.contains("詳しめ") && previewDraft.transmittedText.contains(json),
                           "preview payload remains unchanged after settings change")

    var parser = CodexJSONLines()
    let wire = Data("{\"method\":\"delta\",\"params\":{\"delta\":\"日本語\"}}\n{\"id\":1,\"result\":{}}\n".utf8)
    var received: [[String: Any]] = []
    for byte in wire { received += try parser.append(Data([byte])) }
    try consultationExpect(received.count == 2 && (received[0]["params"] as? [String: String])?["delta"] == "日本語", "JSONL split UTF8 frames")
    do { _ = try parser.append(Data(repeating: 65, count: CodexJSONLines.maximumLineBytes + 1)); throw NSError(domain: "oversize accepted", code: 1) }
    catch is ConsultationError { }
    var malformed = CodexJSONLines()
    do { _ = try malformed.append(Data("[]\n".utf8)); throw NSError(domain: "invalid frame accepted", code: 1) }
    catch is ConsultationError { }
    try consultationExpect(ConsultationModel.validLoginURL(URL(string: "https://auth.openai.com/authorize")!), "official login URL")
    try consultationExpect(!ConsultationModel.validLoginURL(URL(string: "https://auth.openai.com.attacker.test/")!), "lookalike login denied")
    try consultationExpect(!ConsultationModel.validLoginURL(URL(string: "file:///tmp/login")!), "local URL denied")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-consultation-test-\(UUID())")
    let environment = CodexConsultationRuntime.environment(directory: directory)
    try consultationExpect(environment["OPENAI_API_KEY"] == nil && environment["CODEX_API_KEY"] == nil && environment["CODEX_HOME"] == directory.appendingPathComponent("codex-home").path, "isolated auth environment")
    try consultationExpect(CodexConsultationRuntime.arguments().contains("forced_login_method=\"chatgpt\"") && CodexConsultationRuntime.arguments().contains("features.shell_tool=false"), "subscription-only and shell disabled")

    preferences.removePersistentDomain(forName: preferencesName)
    let rpc = FixtureConsultationRPC()
    let model = ConsultationModel(directory: directory, preferences: preferences, factory: { _, _ in rpc })
    model.executablePath = "/fixture/codex"
    await model.connect()
    try consultationExpect(model.connected && model.signedIn, "handshake and ChatGPT login state")
    await model.send(draft)
    try consultationExpect(model.busy && rpc.requests.filter { $0.0 == "thread/start" }.count == 1, "starts one ephemeral thread")
    let threadParams = rpc.requests.first { $0.0 == "thread/start" }!.1
    try consultationExpect(threadParams["ephemeral"] as? Bool == true && threadParams["sandbox"] as? String == "read-only", "thread safety policy")
    let instructions = threadParams["developerInstructions"] as? String ?? ""
    try consultationExpect(instructions.contains("親しみのある、落ち着いた「です・ます」調") && instructions.contains("結論から伝え") && instructions.contains("1〜2個"),
                           "thread instructions define tone, conclusion-first structure, and next actions")
    try consultationExpect(instructions.contains("明示的に頼んだ場合") && instructions.contains("最新の指定"),
                           "thread instructions expand only on request and use the latest turn setting")
    let input = rpc.requests.last { $0.0 == "turn/start" }!.1["input"] as? [[String: Any]]
    try consultationExpect(input?.first?["text"] as? String == draft.transmittedText, "exact preview is submitted")
    rpc.delta("wrong thread", thread: "foreign")
    rpc.delta("最初")
    rpc.delta("の回答")
    rpc.onNotification?("item/completed", ["threadId": "thread-1", "turnId": "turn-1",
        "item": ["type": "agentMessage", "id": "turn-1-answer", "text": "最初の回答"]])
    rpc.complete("turn-1")
    try consultationExpect(!model.busy && model.messages.last?.text == "最初の回答", "stream reconciled without duplicates")
    model.question = "続き"
    model.responseLength = .short
    let followup = model.makeDraft(attachment: nil)
    model.responseLength = .detailed
    await model.send(followup)
    let followupInput = rpc.requests.last { $0.0 == "turn/start" }!.1["input"] as? [[String: Any]]
    try consultationExpect(followupInput?.first?["text"] as? String == followup.transmittedText && followup.transmittedText.contains("短め"),
                           "same-thread followup sends the previewed length unchanged")
    rpc.delta("late old turn")
    try consultationExpect(model.messages.last?.isUser == true, "old-turn events ignored")
    try consultationExpect(rpc.requests.filter { $0.0 == "thread/start" }.count == 1, "followup uses same thread")
    await model.interrupt()
    try consultationExpect(!model.busy && model.status.contains("中断"), "interrupt completion unlocks composer")
    model.newConversation()
    try consultationExpect(model.messages.isEmpty, "new conversation clears context")
    rpc.earlyCompletion = true
    model.question = "早い回答"
    model.responseLength = .detailed
    let newConversationDraft = model.makeDraft(attachment: nil)
    await model.send(newConversationDraft)
    try consultationExpect(!model.busy, "completion before turn/start response does not re-lock")
    try consultationExpect(rpc.requests.filter { $0.0 == "thread/start" }.count == 2, "new conversation starts a new thread")
    let newConversationInput = rpc.requests.last { $0.0 == "turn/start" }!.1["input"] as? [[String: Any]]
    try consultationExpect(newConversationInput?.first?["text"] as? String == newConversationDraft.transmittedText
                           && newConversationDraft.transmittedText.contains("詳しめ"),
                           "new conversation uses the current response length")
    model.disconnect()
    try consultationExpect(rpc.closed && !model.connected, "disconnect closes runtime")

    let api = FixtureConsultationRPC(); api.accountType = "apiKey"
    let apiModel = ConsultationModel(directory: directory, factory: { _, _ in api })
    await apiModel.connect(); await apiModel.send(draft)
    try consultationExpect(!apiModel.signedIn && !api.requests.contains { $0.0 == "turn/start" }, "API auth never consumes inference")
    await apiModel.login()
    try consultationExpect(apiModel.loginURL != nil, "login URL ready for browser")
    await apiModel.cancelLogin()
    try consultationExpect(apiModel.loginURL == nil && api.requests.contains { $0.0 == "account/login/cancel" }, "cancel login")
    apiModel.disconnect()

    let failed = FixtureConsultationRPC(); failed.failMethod = "turn/start"
    let failedModel = ConsultationModel(directory: directory, factory: { _, _ in failed })
    await failedModel.connect(); await failedModel.send(draft)
    try consultationExpect(!failedModel.busy && !failedModel.connected && !failedModel.error.isEmpty, "send failure clears state")
    try consultationExpect(failedModel.messages.last?.delivery == .unconfirmed, "failed send is visibly unconfirmed")
    let dropped = FixtureConsultationRPC()
    let droppedModel = ConsultationModel(directory: directory, factory: { _, _ in dropped })
    await droppedModel.connect(); await droppedModel.send(draft)
    dropped.onDisconnect?("fixture pipe closed")
    try consultationExpect(!droppedModel.busy && !droppedModel.connected && droppedModel.error.contains("pipe"), "unexpected EOF unlocks UI")

    var connections: [FixtureConsultationRPC] = []
    let reconnecting = ConsultationModel(directory: directory, factory: { _, _ in
        let connection = FixtureConsultationRPC(); connection.earlyCompletion = true
        connections.append(connection); return connection
    })
    await reconnecting.connect()
    for _ in 0..<20 { await reconnecting.send(ConsultationDraft(question: "fixture", attachment: nil)) }
    await reconnecting.send(draft)
    try consultationExpect(connections[0].turnCount == 20, "current thread is limited to 20 accepted turns")
    reconnecting.disconnect(); await reconnecting.connect(); await reconnecting.send(draft)
    try consultationExpect(connections[1].turnCount == 1 && reconnecting.messages.last?.delivery == .accepted,
                           "old visible messages do not consume the new thread quota")
    reconnecting.disconnect()

    // Real Process/pipe integration with an isolated fake app server. No account or inference.
    defer { try? FileManager.default.removeItem(at: directory) }
    let binary = URL(fileURLWithPath: CommandLine.arguments[0])
    let processRPC = try CodexRPC(executable: binary, directory: directory, arguments: ["--consultation-rpc-fixture"])
    let result = try await processRPC.request("fixture/echo", ["text": "日本語"])
    try consultationExpect(result["echo"] as? String == "日本語", "Process JSONL round trip and server-request rejection")
    processRPC.close()
    do { _ = try await processRPC.request("after-close", [:]); throw NSError(domain: "closed request accepted", code: 1) }
    catch is ConsultationError { }
    let stubborn = try CodexRPC(executable: binary, directory: directory, arguments: ["--consultation-rpc-fixture", "--ignore-consultation-term"])
    _ = try await stubborn.request("fixture/echo", ["text": "ready"])
    let shutdownStart = ContinuousClock().now
    stubborn.close()
    let exited = await withCheckedContinuation { continuation in
        stubborn.afterExit(timeout: 2.5) { continuation.resume(returning: $0) }
    }
    try consultationExpect(exited && shutdownStart.duration(to: .now) < .seconds(3), "SIGTERM-ignoring child must be reaped within bounded shutdown")
    print("Consultation tests passed (fixtures; no paid inference).")
}

/// Runs in a child test process, handling a server-initiated request before a split response.
func runConsultationRPCFixture() throws {
    func emit(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object); data.append(10)
        let split = data.count / 2
        try FileHandle.standardOutput.write(contentsOf: data.prefix(split))
        try FileHandle.standardOutput.write(contentsOf: data.suffix(from: split))
    }
    guard let line = readLine(), let data = line.data(using: .utf8),
          let request = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = request["id"] else { return }
    try emit(["id": "server-approval", "method": "item/commandExecution/requestApproval", "params": [:]])
    guard let response = readLine(), let responseData = response.data(using: .utf8),
          let refusal = try JSONSerialization.jsonObject(with: responseData) as? [String: Any], refusal["error"] != nil else { return }
    let params = request["params"] as? [String: Any] ?? [:]
    let ignoreTerm = CommandLine.arguments.contains("--ignore-consultation-term")
    if ignoreTerm { signal(SIGTERM, SIG_IGN); alarm(5) }
    try emit(["id": id, "result": ["echo": params["text"] as? String ?? ""]])
    if ignoreTerm { while true { Darwin.pause() } }
    while readLine() != nil { }
}

@MainActor
func runCodexConsultationHandshake(executable: URL) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-codex-handshake-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let rpc = try CodexRPC(executable: executable, directory: directory)
    defer { rpc.close() }
    _ = try await rpc.request("initialize", ["clientInfo": ["name": "aibou_monitor_test", "version": "1.0.0"], "capabilities": ["experimentalApi": false]])
    try rpc.notify("initialized", [:])
    let account = try await rpc.request("account/read", ["refreshToken": false])
    try consultationExpect(account["account"] is NSNull, "isolated CLI must not inherit an account")
    print("Codex App Server handshake passed; isolated account=null; no login or inference requested.")
    let settings = try await rpc.request("config/read", ["includeLayers": false])
    let config = settings["config"] as? [String: Any] ?? [:]
    try consultationExpect(config["forced_login_method"] as? String == "chatgpt", "runtime enforces ChatGPT auth")
    let features = config["features"] as? [String: Any] ?? [:]
    try consultationExpect(features["shell_tool"] as? Bool == false && features["apps"] as? Bool == false, "runtime tool restrictions loaded")
    rpc.close()
    let model = ConsultationModel(directory: directory)
    model.executablePath = executable.path
    await model.connect()
    defer { model.disconnect() }
    try consultationExpect(model.connected && !model.signedIn, "real model handshake state: \(model.error)")
    print("ConsultationModel real CLI connection passed; waiting for ChatGPT login.")
}

@MainActor
func renderConsultationPreview(to destination: URL) async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-consultation-preview-\(UUID())")
    let store = MonitorStore(directory: directory)
    store.pause()
    let rpc = FixtureConsultationRPC()
    let model = ConsultationModel(directory: directory, factory: { _, _ in rpc })
    await model.connect()
    await model.send(ConsultationDraft(question: "最近動作が重いです。どこを確認すればよいですか？", attachment: nil))
    rpc.delta("今の質問には観測値が添付されていません。CPU使用率、メモリ、空き容量を確認すると原因候補を絞れます。\n\n「今回のモニタ集計情報を添付」を選び、重いと感じているときの値を送ってください。")
    rpc.complete("turn-1")
    let view = NSHostingView(rootView: ScrollView { ConsultationView(model: model, store: store) }
        .frame(width: 1000, height: 950)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light))
    view.appearance = NSAppearance(named: .aqua)
    view.frame = NSRect(x: 0, y: 0, width: 1000, height: 950)
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw ConsultationError.message("preview bitmap unavailable") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ConsultationError.message("preview PNG unavailable") }
    try data.write(to: destination)
    model.disconnect(); store.shutdown()
    await withCheckedContinuation { continuation in store.afterPendingSaves { continuation.resume() } }
    try? FileManager.default.removeItem(at: directory)
    print("Consultation UI fixture rendered without using a real account.")
}
