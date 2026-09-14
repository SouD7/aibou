import Foundation
import Darwin

enum ConsultationError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

/// The protocol keeps lifecycle and UI tests independent of an account or paid inference.
@MainActor
protocol ConsultationRPC: AnyObject {
    var onNotification: ((String, [String: Any]) -> Void)? { get set }
    var onDisconnect: ((String) -> Void)? { get set }
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any]
    func notify(_ method: String, _ params: [String: Any]) throws
    func close()
    func afterExit(timeout: TimeInterval, completion: @escaping (Bool) -> Void)
}

extension ConsultationRPC {
    func afterExit(timeout: TimeInterval, completion: @escaping (Bool) -> Void) { completion(true) }
}

struct CodexJSONLines {
    private var buffer = Data()
    static let maximumLineBytes = 1_048_576
    mutating func append(_ data: Data) throws -> [[String: Any]] {
        buffer.append(data)
        var messages: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 10) {
            guard newline <= Self.maximumLineBytes else { throw ConsultationError.message("Codexの応答が上限を超えました。") }
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            guard let value = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw ConsultationError.message("Codexの応答形式が不正です。CLIを更新して再接続してください。")
            }
            messages.append(value)
        }
        guard buffer.count <= Self.maximumLineBytes else { throw ConsultationError.message("Codexの応答が上限を超えました。") }
        return messages
    }
}

enum CodexConsultationRuntime {
    static var defaultDirectory: URL { LocalArchive.directory().appendingPathComponent("Consultation", isDirectory: true) }
    static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                     "/Applications/Codex.app/Contents/Resources/codex"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
    static let disabledFeatures = ["shell_tool", "unified_exec", "code_mode", "code_mode_host", "code_mode_only",
        "apps", "plugins", "hooks", "multi_agent", "multi_agent_v2", "browser_use", "browser_use_external",
        "computer_use", "in_app_browser", "image_generation", "skill_mcp_dependency_install", "skill_search", "tool_suggest"]
    static func arguments() -> [String] {
        var result = ["app-server", "--listen", "stdio://", "-c", "forced_login_method=\"chatgpt\"",
                      "-c", "sandbox_mode=\"read-only\"", "-c", "approval_policy=\"never\"",
                      "-c", "web_search=\"disabled\"", "-c", "history.persistence=\"none\"",
                      "-c", "project_doc_max_bytes=0", "-c", "mcp_servers={}"]
        for feature in disabledFeatures { result += ["-c", "features.\(feature)=false"] }
        return result
    }
    static func environment(directory: URL) -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        // No API keys, custom API endpoints, user Codex profiles, or agent hooks are inherited.
        var result = current.filter { ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL", "SSL_CERT_FILE", "SSL_CERT_DIR"].contains($0.key) }
        result["CODEX_HOME"] = directory.appendingPathComponent("codex-home").path
        return result
    }
}

@MainActor
final class CodexRPC: ConsultationRPC {
    var onNotification: ((String, [String: Any]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let writer = DispatchQueue(label: "aibou.consultation.write")
    private var parser = CodexJSONLines()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var deadlines: [Int: DispatchWorkItem] = [:]
    private var closed = false
    private let terminated = DispatchGroup()

    init(executable: URL, directory: URL, arguments: [String]? = nil) throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ConsultationError.message("Codex CLIが見つかりません。実行ファイルを選択してください。")
        }
        let fm = FileManager.default
        let work = directory.appendingPathComponent("workspace", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: directory.appendingPathComponent("codex-home"), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        process.executableURL = executable
        process.arguments = arguments ?? CodexConsultationRuntime.arguments()
        process.environment = CodexConsultationRuntime.environment(directory: directory)
        process.currentDirectoryURL = work
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { self?.receive(data) }
        }
        // Drain stderr, but never persist it: auth responses and user data must not enter logs.
        errors.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        let terminated = terminated
        process.terminationHandler = { [weak self] process in
            terminated.leave()
            let status = process.terminationStatus
            DispatchQueue.main.async { self?.fail("Codexとの接続が終了しました（終了コード \(status)）。再接続してください。") }
        }
        terminated.enter()
        do { try process.run() } catch { terminated.leave(); close(); throw error }
    }
    func request(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        guard !closed else { throw ConsultationError.message("Codexに接続していません。") }
        nextID += 1; let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            let timeout = DispatchWorkItem { [weak self] in
                self?.fail("Codexの応答が30秒以内に届きませんでした。再接続してください。")
            }
            deadlines[id] = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
            do { try write(["id": id, "method": method, "params": params]) }
            catch { fail(error.localizedDescription) }
        }
    }
    func notify(_ method: String, _ params: [String: Any] = [:]) throws { try write(["method": method, "params": params]) }
    private func write(_ message: [String: Any]) throws {
        guard !closed else { throw ConsultationError.message("接続は終了しています。") }
        var data = try JSONSerialization.data(withJSONObject: message)
        guard data.count <= 65_536 else { throw ConsultationError.message("送信内容が大きすぎます。質問を短くしてください。") }
        data.append(10)
        let payload = data
        let handle = input.fileHandleForWriting
        writer.async { [weak self] in
            do { try handle.write(contentsOf: payload) }
            catch { DispatchQueue.main.async { self?.fail("Codexへの送信に失敗しました。再接続してください。") } }
        }
    }
    private func receive(_ data: Data) {
        guard !closed else { return }
        guard !data.isEmpty else { fail("Codexの出力が閉じられました。再接続してください。"); return }
        do {
            for message in try parser.append(data) {
                if let method = message["method"] as? String {
                    if let id = message["id"] {
                        // Consultation never grants file, command, browser, or external-tool actions.
                        try write(["id": id, "error": ["code": -32601, "message": "AIBOU consultation does not support tool requests"]])
                    } else { onNotification?(method, message["params"] as? [String: Any] ?? [:]) }
                } else if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                    deadlines.removeValue(forKey: id)?.cancel()
                    if let error = message["error"] as? [String: Any] {
                        continuation.resume(throwing: ConsultationError.message(String((error["message"] as? String ?? "Codexでエラーが発生しました。").prefix(1000))))
                    } else if let result = message["result"] as? [String: Any] { continuation.resume(returning: result) }
                    else { continuation.resume(throwing: ConsultationError.message("Codexの応答形式に対応していません。")) }
                }
            }
        } catch { fail(error.localizedDescription) }
    }
    private func fail(_ message: String) {
        guard !closed else { return }
        close()
        onDisconnect?(message)
    }
    func close() {
        guard !closed else { return }; closed = true
        deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        let waiting = pending.values; pending.removeAll()
        waiting.forEach { $0.resume(throwing: ConsultationError.message("Codexとの接続が終了しました。")) }
        output.fileHandleForReading.readabilityHandler = nil
        errors.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let child = process
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }
    func afterExit(timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        let group = terminated
        let deadline = DispatchTime.now() + max(0, timeout)
        DispatchQueue.global(qos: .utility).async {
            let exited = group.wait(timeout: deadline) == .success
            DispatchQueue.main.async { completion(exited) }
        }
    }
}
