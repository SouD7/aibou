import Foundation
import Darwin

struct CommandOutput {
    var text: String
    var code: Int32
    var timedOut: Bool
    var truncated: Bool
    var cancelled = false
    /// nil when no direct process was launched; says nothing about elevated descendants.
    var directProcessExited: Bool? = nil
}

private final class CommandBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var overflow = false
    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        let available = max(0, 8_000_000 - bytes.count)
        bytes.append(data.prefix(available))
        overflow = overflow || data.count > available
    }
    func read() -> (String, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (String(decoding: bytes, as: UTF8.self), overflow)
    }
}

/// Fixed executable/argv only. Both streams are drained while running; no sensitive temporary files.
struct CommandOperation: Hashable, Sendable {
    fileprivate let id = UUID()
}

final class CommandRunner: @unchecked Sendable {
    private let executionLock = NSLock()
    private let lock = NSLock()
    private var running: Process?
    private let activeRuns = DispatchGroup()
    private var runningWake: DispatchSemaphore?
    private var runningCancelled = false
    private var pending = Set<CommandOperation>()
    private var terminated = false
    func reserveOperation() -> CommandOperation? {
        lock.lock(); defer { lock.unlock() }
        guard !terminated else { return nil }
        let operation = CommandOperation(); pending.insert(operation); return operation
    }
    func cancel() { stop(permanently: false) }
    func shutdown() { stop(permanently: true) }
    /// Call off the main thread after shutdown; pending launches have already been invalidated.
    func waitForDirectProcess(until deadline: DispatchTime) -> Bool {
        activeRuns.wait(timeout: deadline) == .success
    }
    private func stop(permanently: Bool) {
        lock.lock(); defer { lock.unlock() }
        terminated = terminated || permanently
        pending.removeAll()
        if let process = running, process.isRunning, !runningCancelled {
            runningCancelled = true
            process.terminate()
            runningWake?.signal()
        }
    }
    func run(_ path: String, _ arguments: [String], timeout: Double = 8) -> CommandOutput {
        guard let operation = reserveOperation() else { return Self.cancelledOutput }
        return run(operation, path, arguments, timeout: timeout)
    }
    private static var cancelledOutput: CommandOutput {
        CommandOutput(text: "計測を中断しました", code: -999, timedOut: false, truncated: false, cancelled: true)
    }
    func run(_ operation: CommandOperation, _ path: String, _ arguments: [String], timeout: Double = 8) -> CommandOutput {
        executionLock.lock()
        defer { executionLock.unlock() }
        let process = Process(), pipe = Pipe(), buffer = CommandBuffer()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C", "LANG": "C"]) { _, new in new }
        process.standardOutput = pipe; process.standardError = pipe
        let finished = DispatchSemaphore(value: 0), drained = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        // Cancellation and process launch share one boundary. A pending token is single-use.
        lock.lock()
        guard !terminated, pending.remove(operation) != nil else { lock.unlock(); return Self.cancelledOutput }
        activeRuns.enter()
        defer { activeRuns.leave() }
        running = process
        runningWake = finished; runningCancelled = false
        do { try process.run() } catch {
            running = nil; runningWake = nil; lock.unlock()
            return CommandOutput(text: error.localizedDescription, code: -1, timedOut: false, truncated: false)
        }
        lock.unlock()
        defer { lock.lock(); if running === process { running = nil; runningWake = nil }; lock.unlock() }
        try? pipe.fileHandleForWriting.close()
        DispatchQueue.global(qos: .utility).async {
            while let data = try? pipe.fileHandleForReading.read(upToCount: 16_384), !data.isEmpty { buffer.append(data) }
            drained.signal()
        }
        let waitExpired = finished.wait(timeout: .now() + timeout) == .timedOut
        lock.lock(); let cancelled = runningCancelled; lock.unlock()
        let timedOut = waitExpired && !cancelled
        if (timedOut || cancelled), process.isRunning {
            if process.isRunning { process.terminate() }
            let graceDeadline = DispatchTime.now() + 1
            // A concurrent cancel also wakes this semaphore; only task state confirms exit.
            while process.isRunning, finished.wait(timeout: graceDeadline) == .success { }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        _ = drained.wait(timeout: .now() + 1)
        try? pipe.fileHandleForReading.close()
        let result = buffer.read()
        let exited = !process.isRunning
        return CommandOutput(text: cancelled ? "計測を中断しました" : result.0,
                             code: cancelled ? -999 : (exited ? process.terminationStatus : -1),
                             timedOut: timedOut, truncated: result.1, cancelled: cancelled,
                             directProcessExited: exited)
    }
}

enum CSVReader {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        let chars = Array(text); var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r") && !quoted {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []; field = ""
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

final class NetworkDetailCollector {
    let runner = CommandRunner()
    func sample(processes: [ProcessSample]) -> PanelReading {
        guard let operation = runner.reserveOperation() else { return Self.parse(CommandOutput(text: "終了済み", code: -999, timedOut: false, truncated: false), processes: processes) }
        return sample(operation: operation, processes: processes)
    }
    func sample(operation: CommandOperation, processes: [ProcessSample]) -> PanelReading {
        // Two samples: the second -d sample measures the observed interval, not socket lifetime.
        let output = runner.run(operation, "/usr/bin/nettop", ["-L", "2", "-s", "1", "-n", "-x", "-d",
            "-J", "bytes_in,bytes_out,packets_in,packets_out,re-tx,rtt_avg,rtt_var,state"], timeout: 6)
        return Self.parse(output, processes: processes)
    }

    static func parse(_ output: CommandOutput, processes: [ProcessSample] = []) -> PanelReading {
        let source = "macOS nettop (-d、1秒区間・最終サンプル)"
        var panel = PanelReading(tab: .network)
        panel.notes = ["明示的な詳細計測。接続先は起動中だけ保持します。TCP RTT・再送はアプリの応答時間・失敗数ではありません。",
                       "nettopはOS版・権限に依存します。bytesはこの1秒区間の差分。短命な接続や未公開の列は取得できません。"]
        guard output.code == 0, !output.timedOut, !output.truncated else {
            let denied = output.text.localizedCaseInsensitiveContains("failed") || output.text.localizedCaseInsensitiveContains("permitted")
            panel.metrics = [Metric("nettop.status", "プロセス別通信の取得", status: denied ? .denied : .unavailable,
                source: source, detail: output.timedOut ? "6秒で計測を中断しました" : String(output.text.prefix(1200)))]
            return panel
        }
        let csv = CSVReader.parse(output.text)
        var header: [String] = [], data: [[String]] = []
        var batches: [(header: [String], rows: [[String]])] = []
        for line in csv {
            if line.contains("bytes_in") && line.contains("bytes_out") {
                if !header.isEmpty, !data.isEmpty { batches.append((header, data)); data = [] }
                header = line.map { $0.trimmingCharacters(in: .whitespaces) }
            } else if !header.isEmpty, line.count >= header.count { data.append(line) }
        }
        if !header.isEmpty, !data.isEmpty { batches.append((header, data)) }
        guard let lastBatch = batches.last else {
            panel.metrics = [Metric("nettop.status", "プロセス別通信の取得", status: .unavailable, source: source,
                                    detail: "認識できるCSVヘッダーがありません。このOSの出力形式を確認してください。")]
            return panel
        }
        header = lastBatch.header
        let last = lastBatch.rows
        // nettop may emit a single header followed by timestamped process rows for each sample.
        // Keep only the last timestamp group if that representation is used.
        let datePattern = #"^\d{2}:\d{2}:\d{2}"#
        let stampIndex = last.first?.indices.first { index in
            last.contains { $0[index].range(of: datePattern, options: .regularExpression) != nil }
        }
        let lastStamp = stampIndex.flatMap { index in last.reversed().first { $0[index].range(of: datePattern, options: .regularExpression) != nil }?[index] }
        var active = lastStamp == nil, selected: [[String]] = []
        for line in last {
            if let index = stampIndex, line[index].range(of: datePattern, options: .regularExpression) != nil { active = line[index] == lastStamp }
            if active { selected.append(line) }
        }
        let known: [(String, String, String)] = [("bytes_in", "受信差分", "B"), ("bytes_out", "送信差分", "B"),
            ("packets_in", "受信パケット", "個"), ("packets_out", "送信パケット", "個"), ("re-tx", "TCP再送（元の値）", ""),
            ("rtt_avg", "TCP RTT（元の値）", ""), ("rtt_var", "RTT変動（元の値）", ""), ("state", "接続状態", "")]
        panel.columns = [TableColumn("owner", "アプリ / 親元", width: 180)] + known.filter { header.contains($0.0) }.map { TableColumn($0.0, $0.1) }
        panel.columns += [TableColumn("receiveRate", "受信速度"), TableColumn("sendRate", "送信速度")]
        var owner = "未特定", processLabel = "", serial = 0
        for line in selected {
            let labelIndex = header.firstIndex(where: { $0 == "process" || $0 == "name" }) ?? (header.first == "" ? 0 : 1)
            guard line.indices.contains(labelIndex) else { continue }
            let label = line[labelIndex].trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            let isConnection = label.contains("<->")
            let pid: Int32? = isConnection ? nil : label.range(of: #"\.(\d+)$"#, options: .regularExpression).flatMap {
                Int32(label[$0].dropFirst())
            }
            if let pid {
                let process = processes.first { $0.pid == pid }
                owner = process?.owner ?? "PID \(pid)（帰属未確認）"
                processLabel = label
            }
            var metrics = [Metric("owner", "親元", text: owner, status: .estimated, source: source,
                                  detail: "nettopのPIDと現在のプロセス一覧を照合。計測中に終了・PID再利用した対象は確定できません。")]
            for (key, title, unit) in known {
                guard let idx = header.firstIndex(of: key), line.indices.contains(idx) else { continue }
                let raw = line[idx].trimmingCharacters(in: .whitespaces)
                let parsed = Double(raw)
                let numeric = parsed?.isFinite == true ? parsed : nil
                let hasValue = unit.isEmpty ? !raw.isEmpty : numeric != nil
                metrics.append(Metric(key, title, value: unit.isEmpty ? nil : numeric,
                    text: unit.isEmpty ? raw : nil, unit: unit,
                    status: hasValue ? (key == "state" ? .measured : .derived) : .unavailable,
                    source: source, detail: "nettopの\(key)。RTT等は出力の単位表記を保持します。", interval: 1))
                if key == "bytes_in" || key == "bytes_out" {
                    metrics.append(Metric(key == "bytes_in" ? "receiveRate" : "sendRate", key == "bytes_in" ? "受信速度" : "送信速度",
                        value: (batches.count >= 2 || lastStamp != nil) ? numeric : nil, unit: "B/s",
                        status: (batches.count >= 2 || lastStamp != nil) && numeric != nil ? .derived : (numeric == nil ? .unavailable : .waiting),
                        source: source, detail: "nettopの1秒delta。初回のみの出力から速度を作りません。", interval: 1))
                }
            }
            serial += 1
            panel.rows.append(ReadingRow(id: "nettop-\(serial)", name: label, metrics: metrics,
                note: pid == nil ? "\(processLabel.isEmpty ? "帰属未特定" : processLabel) の接続。計測区間の観測結果" : "プロセス集計（接続行と二重加算しない）"))
        }
        panel.metrics = [Metric("nettop.rows", "プロセス・接続行", value: Double(panel.rows.count), unit: "個", source: source)]
        return panel
    }
}

final class PowerDetailCollector {
    static let administratorStopLimitation = "終了・時間切れ時は認証コマンドに停止を要求します。認証先のpowermetricsの終了は確認できないため、単発計測が完了する場合があります。"
    private struct LeafContext {
        var pid: Int32?
        var name: String?
    }
    private struct PowerLeaf {
        var path: String
        var value: Any
        var context: LeafContext
    }

    let runner = CommandRunner()
    func sample(administrator: Bool, processes: [ProcessSample] = []) -> [PanelReading] {
        guard let operation = runner.reserveOperation() else { return Self.parse(CommandOutput(text: "終了済み", code: -999, timedOut: false, truncated: false), processes: processes) }
        return sample(operation: operation, administrator: administrator, processes: processes)
    }
    func sample(operation: CommandOperation, administrator: Bool, processes: [ProcessSample] = []) -> [PanelReading] {
        let args = ["--samplers", "tasks,cpu_power,gpu_power,thermal", "-n", "1", "-i", "1000", "--show-process-gpu", "-f", "plist"]
        let result: CommandOutput
        if administrator {
            // No user-controlled text is interpolated. OS authentication is invoked only by the UI action.
            let command = "/usr/bin/powermetrics " + args.joined(separator: " ")
            result = runner.run(operation, "/usr/bin/osascript", ["-e", "do shell script \"\(command)\" with administrator privileges"], timeout: 120)
        } else { result = runner.run(operation, "/usr/bin/powermetrics", args, timeout: 5) }
        return Self.panels(for: result, administrator: administrator, processes: processes)
    }

    static func panels(for output: CommandOutput, administrator: Bool, processes: [ProcessSample] = []) -> [PanelReading] {
        var panels = parse(output, processes: processes)
        if administrator {
            for index in panels.indices {
                panels[index].notes.append(administratorStopLimitation)
                if output.timedOut || output.cancelled {
                    let direct = output.directProcessExited == true ? "認証コマンドの終了を確認しました。" : "認証コマンドの終了は未確認です。"
                    panels[index].notes.append(direct + "認証先のpowermetricsの終了は未確認です。")
                }
            }
        }
        return panels
    }

    static func parse(_ output: CommandOutput, processes: [ProcessSample] = []) -> [PanelReading] {
        let source = "macOS powermetrics（1秒サンプル）"
        let tabs: [MonitorTab] = [.gpu, .clock, .thermal]
        guard output.code == 0, !output.timedOut, !output.truncated else {
            let denied = output.text.localizedCaseInsensitiveContains("superuser") || output.text.contains("-128") || output.text.contains("privilege")
            return tabs.map { tab in
                PanelReading(tab: tab, metrics: [Metric("power.status", "追加計測", status: denied ? .denied : .unavailable,
                    source: source, detail: output.timedOut ? "計測または認証が時間内に終了しませんでした" : String(output.text.prefix(1200)))])
            }
        }
        let clean = output.text.replacingOccurrences(of: "\0", with: "")
        guard let start = clean.range(of: "<?xml"), let end = clean.range(of: "</plist>", options: .backwards),
              start.lowerBound < end.upperBound,
              let data = String(clean[start.lowerBound..<end.upperBound]).data(using: .utf8),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return tabs.map { PanelReading(tab: $0, metrics: [Metric("power.status", "追加計測", status: .unavailable,
                source: source, detail: "認識できるplistがありません。OSの出力変更・対応サンプラーを確認してください。")]) }
        }
        var leaves: [PowerLeaf] = []
        var leafLimitReached = false, depthLimitReached = false
        func flatten(_ value: Any, path: String, depth: Int, context: LeafContext) {
            guard depth < 15 else { depthLimitReached = true; return }
            guard leaves.count < 12_000 else { leafLimitReached = true; return }
            if let dict = value as? [String: Any] {
                var nested = context
                nested.pid = Self.processPID(in: dict) ?? nested.pid
                nested.name = Self.processName(in: dict) ?? nested.name
                for key in dict.keys.sorted() {
                    flatten(dict[key]!, path: path.isEmpty ? key : "\(path).\(key)", depth: depth + 1, context: nested)
                }
            } else if let array = value as? [Any] {
                for (index, child) in array.enumerated() {
                    // The index is a path component only; it never establishes process identity.
                    flatten(child, path: "\(path)[\(index)]", depth: depth + 1, context: context)
                }
            } else { leaves.append(PowerLeaf(path: path, value: value, context: context)) }
        }
        flatten(object, path: "", depth: 0, context: LeafContext())
        let limitReasons = [leafLimitReached ? "12,000フィールドの解析上限" : nil,
                            depthLimitReached ? "深さ15の解析上限" : nil].compactMap { $0 }
        let partial = !limitReasons.isEmpty
        let limitDetail = limitReasons.joined(separator: "・") + "に達したため部分取得です。未読部分の対応フィールドの有無は判断できません。"
        return tabs.map { tab in
            let matches = leaves.filter { leaf in
                let key = leaf.path.lowercased()
                switch tab {
                case .gpu: return key.contains("gpu")
                case .clock: return key.contains("freq") || key.contains("hz") || key.contains("pstate")
                case .thermal: return key.contains("thermal") || key.contains("temperature") || key.contains("fan")
                default: return false
                }
            }
            var columns = [TableColumn("raw", "取得元の値", width: 220)]
            if tab == .gpu {
                columns += [TableColumn("process", "プロセス", width: 170), TableColumn("pid", "PID", width: 80),
                            TableColumn("parent", "親PID", width: 80), TableColumn("owner", "親元", width: 160)]
            }
            var panel = PanelReading(tab: tab, columns: columns)
            for leaf in matches {
                // Preserve the original field and unit. A raw GPU time is never a fabricated percentage.
                var metrics = [Self.rawMetric(for: leaf, source: source)]
                var rowName = leaf.path
                var note = "powermetricsの元フィールド。GPU占有率への換算は行っていません。"
                if tab == .gpu {
                    let matched = leaf.context.pid.flatMap { pid in processes.first { $0.pid == pid } }
                    let displayedName = leaf.context.name ?? matched?.name
                    if let displayedName { rowName = "\(displayedName) — \(leaf.path)" }
                    metrics += [
                        Metric("process", "プロセス", text: displayedName,
                               status: displayedName == nil ? .unavailable : (leaf.context.name == nil ? .estimated : .measured),
                               source: leaf.context.name == nil ? "現在のプロセス一覧" : source,
                               detail: leaf.context.name == nil ? "powermetricsに名称がなく、PIDから補完" : "powermetricsの同じtask辞書", interval: 1),
                        Metric("pid", "PID", value: leaf.context.pid.map(Double.init),
                               status: leaf.context.pid == nil ? .unavailable : .measured, source: source,
                               detail: "powermetricsの同じtask辞書。配列番号はPIDとして扱いません。", interval: 1),
                        Metric("parent", "親PID", value: matched.map { Double($0.parentPID) },
                               status: matched == nil ? .unavailable : .estimated, source: "現在のプロセス一覧",
                               detail: "powermetricsのPIDとの照合値。", interval: 1),
                        Metric("owner", "親元", text: matched?.owner,
                               status: matched == nil ? .unavailable : .estimated, source: "現在のプロセス一覧",
                               detail: "PIDだけで照合。powermetricsに起動時刻がないため、終了・PID再利用を完全には除外できません。", interval: 1)
                    ]
                    note += leaf.context.pid == nil
                        ? " task辞書にPIDがなく、配列番号や名称だけでは帰属させていません。"
                        : " PID照合には起動時刻がなく、再利用の可能性を完全には除外できません。"
                }
                panel.rows.append(ReadingRow(id: leaf.path, name: rowName, metrics: metrics, note: note))
            }
            panel.metrics = [Metric("power.fields", "追加計測フィールド", value: Double(matches.count), unit: "個",
                status: partial ? .partial : (matches.isEmpty ? .unsupported : .measured), source: source,
                detail: partial ? limitDetail : (matches.isEmpty ? "この機種・サンプラーの出力に対応フィールドがありません" : "取得時点の1秒間の値。再計測するまで更新されません。"))]
            panel.notes = ["OSによる推定電力・周波数・GPU時間等の補助計測。元のフィールド名と単位を保持し、意味が未確定の値を別指標に変換しません。"]
            if partial { panel.notes.append(limitDetail) }
            return panel
        }
    }

    private static func processPID(in dictionary: [String: Any]) -> Int32? {
        for key in ["pid", "process_id", "processID", "task_pid"] {
            if let number = dictionary[key] as? NSNumber {
                let value = number.doubleValue
                if value.isFinite, value >= 0, value <= Double(Int32.max), value.rounded() == value { return Int32(value) }
            } else if let text = dictionary[key] as? String, let value = Int32(text), value >= 0 { return value }
        }
        return nil
    }

    private static func processName(in dictionary: [String: Any]) -> String? {
        for key in ["command", "process_name", "processName", "name"] {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func rawMetric(for leaf: PowerLeaf, source: String) -> Metric {
        let key = leaf.path.split(separator: ".").last.map(String.init) ?? leaf.path
        let lower = key.lowercased()
        let explicitUnits: [(String, String)] = [("_ns", "ns"), ("_us", "µs"), ("_ms", "ms"),
                                                  ("_hz", "Hz"), ("_mw", "mW"), ("_w", "W")]
        let unit = explicitUnits.first { lower.hasSuffix($0.0) }?.1 ?? ""
        let number = (leaf.value as? NSNumber)?.doubleValue
        let finite = number?.isFinite == true ? number : nil
        return Metric("raw", leaf.path, value: unit.isEmpty ? nil : finite,
                      text: unit.isEmpty || finite == nil ? String(describing: leaf.value) : nil,
                      unit: unit, status: finite == nil && !unit.isEmpty ? .unavailable : .measured,
                      source: source,
                      detail: unit.isEmpty ? "元のplistフィールド。キーに単位がないため未確定。\(leaf.path)" : "キーに明記された単位を保持。\(leaf.path)",
                      interval: 1)
    }
}
