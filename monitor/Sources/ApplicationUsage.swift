import Foundation
import Darwin

struct ApplicationProcessGroup {
    var processes: [ProcessSample]
    var inheritedIDs: Set<String>

    /// Exact installation path is the anchor; another app with the same bundle ID is not included.
    static func make(app: LauncherApplication, processes: [ProcessSample]) -> ApplicationProcessGroup {
        let root = app.url.resolvingSymlinksInPath().standardizedFileURL.path
        var normalized: [String: String] = [:]
        func path(_ process: ProcessSample) -> String {
            if process.path.isEmpty { return "" }
            if let cached = normalized[process.path] { return cached }
            let value = URL(fileURLWithPath: process.path).resolvingSymlinksInPath().standardizedFileURL.path
            normalized[process.path] = value
            return value
        }
        var included = Set(processes.filter { path($0).hasPrefix(root + "/") }.map(\.id))
        let direct = included
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        // Iterative traversal also handles helper processes reparented to launchd via direct paths.
        var changed = true
        while changed {
            changed = false
            for process in processes where !included.contains(process.id) {
                guard let parent = byPID[process.parentPID], included.contains(parent.id),
                      process.startTime >= parent.startTime else { continue }
                // Launching a separate GUI application does not make it part of the parent's budget.
                let otherPath = path(process)
                if otherPath.split(separator: "/").contains(where: { $0.lowercased().hasSuffix(".app") }) { continue }
                included.insert(process.id); changed = true
            }
        }
        return ApplicationProcessGroup(processes: processes.filter { included.contains($0.id) },
                                       inheritedIDs: included.subtracting(direct))
    }

    func metrics(recordedAt: Date?, inventoryStatus: ReadingStatus, running: Bool, now: Date = Date()) -> [Metric] {
        let date = recordedAt ?? now
        let stale = recordedAt != nil && (!running || (recordedAt.map { now.timeIntervalSince($0) > 10 } ?? false))
        func total(_ id: String, _ label: String, unit: String, values: [Double?]) -> Metric {
            let usable = values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
            let sum = usable.reduce(0, +)
            let valid = !usable.isEmpty && sum.isFinite
            let status: ReadingStatus = !valid ? (recordedAt == nil ? .waiting : .unavailable) : stale ? .stale
                : usable.count != processes.count || inventoryStatus != .measured ? .partial
                : inheritedIDs.isEmpty ? .derived : .estimated
            return Metric(id, label, value: valid ? sum : nil, unit: unit, status: status,
                source: "既存モニタのプロセス値を合算", detail: "取得値 \(usable.count)/\(processes.count)プロセス。読取制限・短命なプロセス・共有サービスは完全には帰属できません。",
                recordedAt: date)
        }
        return [total("app.cpu", "CPU合計", unit: "%", values: processes.map(\.cpuPercent)),
                total("app.memory", "メモリ合計（フットプリント）", unit: "B", values: processes.map { $0.footprintBytes.map { Double($0) } }),
                total("app.resident", "常駐メモリ合計", unit: "B", values: processes.map { $0.residentBytes.map { Double($0) } })]
    }
}

enum ApplicationNetworkUsage {
    static func identity(_ pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let date = Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
        return "\(pid):\(date.timeIntervalSince1970)"
    }

    static func aggregate(panel: PanelReading, group: ApplicationProcessGroup, stableIDs: Set<String>, running: Bool = true, now: Date = Date()) -> [Metric] {
        var rows: [Int32: ReadingRow] = [:], duplicates: Set<Int32> = []
        for row in panel.rows {
            guard !row.name.contains("<->"), let suffix = row.name.range(of: #"\.[0-9]+$"#, options: .regularExpression),
                  let pid = Int32(row.name[suffix].dropFirst()), pid > 0 else { continue }
            if rows[pid] != nil { duplicates.insert(pid) }
            rows[pid] = row
        }
        return [("receiveRate", "受信速度合計", "B/s"), ("sendRate", "送信速度合計", "B/s"),
                ("bytes_in", "受信量合計（今回の1秒）", "B"), ("bytes_out", "送信量合計（今回の1秒）", "B")].map { key, label, unit in
            let values = group.processes.compactMap { process -> Double? in
                guard stableIDs.contains(process.id), !duplicates.contains(process.pid), let row = rows[process.pid],
                      let metric = row.metric(key), [.measured, .derived].contains(metric.status),
                      let value = metric.value, value.isFinite, value >= 0 else { return nil }
                // Even byte deltas require a second nettop sample, never the initial lifetime counters.
                guard row.metric(key == "bytes_out" || key == "sendRate" ? "sendRate" : "receiveRate")?.status == .derived else { return nil }
                return value
            }
            let sum = values.reduce(0, +)
            let value = values.isEmpty || !sum.isFinite ? nil : sum
            let status: ReadingStatus = value == nil ? (panel.metrics.first { $0.id == "nettop.status" }?.status ?? .unavailable)
                : values.count == group.processes.count ? (group.inheritedIDs.isEmpty ? .derived : .estimated) : .partial
            let displayedStatus: ReadingStatus = value != nil && (!running || now.timeIntervalSince(panel.capturedAt) > 10) ? .stale : status
            return Metric("app.network.\(key)", label, value: value, unit: unit, status: displayedStatus,
                source: "nettop・プロセス集計行のみ", detail: "通信値 \(values.count)/\(group.processes.count)プロセス。開始時刻を計測前後で照合し、接続行は加算しません。行がない場合は通信0と断定しません。" + (panel.metrics.first { $0.id == "nettop.status" }?.detail ?? ""),
                recordedAt: panel.capturedAt, interval: 1)
        }
    }
}
