import Foundation

enum DiagnosticRule: String, Codable, CaseIterable {
    case manual, thermalPressure, cpuBusy, coreBusy, swapAllocated
    case batteryLow, batteryCritical, chargingPaused, storageLow
}

struct DiagnosticCase: Identifiable {
    let id: String
    let category: String
    let title: String
    let symptoms: [String]
    let causes: [String]
    let actions: [String]
    let checks: [String]
    let limitation: String
    let rule: DiagnosticRule
    let sources: [String]
}

enum DiagnosticState: String, Codable {
    case matched, observing, notMatched, unknown, manual
    var title: String {
        switch self {
        case .matched: return "観測条件に該当"
        case .observing: return "継続確認中"
        case .notMatched: return "今回の条件に該当せず"
        case .unknown: return "情報不足"
        case .manual: return "手動確認"
        }
    }
}

struct DiagnosticEvidence: Codable, Identifiable {
    var id: String
    var condition: String
    /// nil is unknown, never a negative observation.
    var met: Bool?
    var detail: String
    var source: String?
    var recordedAt: Date?
}

struct DiagnosticResult: Codable, Identifiable {
    var id: String
    var state: DiagnosticState
    var evidence: [DiagnosticEvidence]
}

/// A bounded, in-memory rule evaluator. Thresholds are product heuristics, not hardware limits.
/// Keeps continuity per logical core plus host CPU; no process history or automatic actions.
struct DiagnosticEngine {
    static let freshness: TimeInterval = 10
    static let maximumGap: TimeInterval = 6
    static let sustainedSeconds: TimeInterval = 20
    private struct Run {
        var start: Date
        var last: Date
        var identity: String
    }
    private var runs: [String: Run] = [:]
    private var segment: String?

    mutating func reset() { runs.removeAll(); segment = nil }

    /// Continuity requires a running producer with a stable segment (owned by MonitorStore).
    /// One-shot snapshots reset continuity; evaluate can still assess their instantaneous rules.
    mutating func ingest(_ snapshot: ObservationSnapshot, now: Date) {
        guard snapshot.collection.state == .running,
              Self.collectionIssue(snapshot, now: now) == nil else { reset(); return }
        if segment != snapshot.collection.segmentID { runs.removeAll() }
        segment = snapshot.collection.segmentID
        var next: [String: Run] = [:]
        let coreIDs = snapshot.categories.first { $0.category == .cpu }?.metrics.map(\.metricID).filter {
            $0.hasPrefix("core") && Int($0.dropFirst(4)) != nil
        } ?? []
        for id in ["idle"] + coreIDs {
            let rule: DiagnosticRule = id == "idle" ? .cpuBusy : .coreBusy
            let evidence = Self.conditions(rule, snapshot: snapshot, now: now, selectedCore: id)
            guard let item = evidence.first, item.met == true, let time = item.recordedAt else { continue }
            if let run = runs[id] {
                let gap = time.timeIntervalSince(run.last)
                if gap == 0 { next[id] = run; continue } // Replayed values never prove duration.
                if gap > 0 && gap <= Self.maximumGap {
                    next[id] = Run(start: run.start, last: time, identity: id); continue
                }
            }
            next[id] = Run(start: time, last: time, identity: id)
        }
        runs = next
    }

    func evaluate(_ snapshot: ObservationSnapshot, now: Date = Date(),
                  catalog: [DiagnosticCase] = DiagnosticCatalog.cases) -> [DiagnosticResult] {
        catalog.map { entry in
            guard entry.rule != .manual else {
                return DiagnosticResult(id: entry.id, state: .manual, evidence: [])
            }
            if let issue = Self.collectionIssue(snapshot, now: now) {
                return DiagnosticResult(id: entry.id, state: .unknown, evidence: [
                    DiagnosticEvidence(id: "collection", condition: "新しい計測値を取得している", met: nil, detail: issue)
                ])
            }
            let longestCore = entry.rule == .coreBusy ? runs.values.filter { run in
                guard run.identity != "idle" else { return false }
                let current = Self.conditions(.coreBusy, snapshot: snapshot, now: now, selectedCore: run.identity).first
                return current?.met == true && current?.recordedAt == run.last
            }.max { $0.last.timeIntervalSince($0.start) < $1.last.timeIntervalSince($1.start) } : nil
            var evidence = Self.conditions(entry.rule, snapshot: snapshot, now: now, selectedCore: longestCore?.identity)
            if [.cpuBusy, .coreBusy].contains(entry.rule), evidence.first?.met == true {
                let run = evidence.first.flatMap { runs[$0.id] }
                let duration = run.flatMap { run -> Double? in
                    guard snapshot.collection.state == .running, segment == snapshot.collection.segmentID,
                          run.last == evidence.first?.recordedAt,
                          run.identity == evidence.first?.id else { return nil }
                    return run.last.timeIntervalSince(run.start)
                } ?? 0
                let confirmed = duration >= Self.sustainedSeconds
                evidence.append(DiagnosticEvidence(id: "duration", condition: "20秒以上、連続して観測",
                    met: confirmed, detail: String(format: "確認済み %.0f秒 / 20秒（計測間隔6秒超でリセット）", duration)))
                return DiagnosticResult(id: entry.id, state: confirmed ? .matched : .observing, evidence: evidence)
            }
            let state: DiagnosticState
            if evidence.contains(where: { $0.met == false }) { state = .notMatched }
            else if evidence.isEmpty || evidence.contains(where: { $0.met == nil }) { state = .unknown }
            else { state = .matched }
            return DiagnosticResult(id: entry.id, state: state, evidence: evidence)
        }
    }

    private static func collectionIssue(_ snapshot: ObservationSnapshot, now: Date) -> String? {
        guard snapshot.schemaVersion == 2 else { return "未対応の観測データ形式です。" }
        guard [.running, .snapshot].contains(snapshot.collection.state) else { return "基本監視停止中です。再開後の値で判定します。" }
        guard let last = snapshot.collection.lastSampleAt else { return "初回計測を待っています。" }
        if snapshot.collection.state == .running &&
            (snapshot.collection.segmentID == nil || snapshot.collection.sampleSegmentID != snapshot.collection.segmentID) {
            return "監視を再開した区間の計測を待っています。"
        }
        let age = now.timeIntervalSince(last)
        guard age >= 0 && age <= freshness else { return "計測値が10秒以上古いか、時刻が不整合です。" }
        return nil
    }

    private static func conditions(_ rule: DiagnosticRule, snapshot: ObservationSnapshot, now: Date,
                                   selectedCore: String? = nil) -> [DiagnosticEvidence] {
        func metric(_ category: ObservationCategory, _ id: String) -> ObservationMetric? {
            snapshot.categories.first { $0.category == category }?.metrics.first { $0.metricID == id }
        }
        func usable(_ m: ObservationMetric?) -> Bool {
            guard let m, [.measured, .derived].contains(m.status) else { return false }
            let age = now.timeIntervalSince(m.recordedAt)
            return age >= 0 && age <= freshness
        }
        func number(_ m: ObservationMetric?, range: ClosedRange<Double>) -> Double? {
            guard usable(m), let n = m?.value, n.isFinite, range.contains(n) else { return nil }
            return n
        }
        func evidence(_ m: ObservationMetric?, id: String, condition: String, met: Bool?, value: String? = nil) -> DiagnosticEvidence {
            let missingReason: String
            if let m {
                if ![ObservationStatus.measured, .derived].contains(m.status) {
                    missingReason = "取得状態: \(ReadingStatus(rawValue: m.status.rawValue)?.title ?? m.status.rawValue)。\(m.detail)"
                } else if now.timeIntervalSince(m.recordedAt) < 0 {
                    missingReason = "取得時刻が現在より先のため評価できません。"
                } else if now.timeIntervalSince(m.recordedAt) > freshness {
                    missingReason = "10秒を超える古い値のため評価できません。"
                } else { missingReason = "必要な値・計測間隔が欠けているか、想定する範囲・形式ではありません。" }
            } else { missingReason = "必要な観測項目がありません。この機種・取得元で値が提供されているか確認してください。" }
            return DiagnosticEvidence(id: id, condition: condition, met: met,
                detail: met == nil ? missingReason : (value ?? m?.text ?? ""),
                source: m?.source, recordedAt: m?.recordedAt)
        }
        func numeric(_ category: ObservationCategory, _ id: String, condition: String,
                     range: ClosedRange<Double> = 0...Double.greatestFiniteMagnitude,
                     test: (Double) -> Bool) -> DiagnosticEvidence {
            let m = metric(category, id), value = number(m, range: range)
            return evidence(m, id: id, condition: condition, met: value.map(test),
                value: value.map { String(format: "%.2f %@", $0, m?.unit ?? "") })
        }
        func textCondition(_ category: ObservationCategory, _ id: String, condition: String,
                           allowed: [String], matches: [String]) -> DiagnosticEvidence {
            let m = metric(category, id)
            let text = usable(m) ? m?.text : nil
            return evidence(m, id: id, condition: condition,
                met: text.flatMap { allowed.contains($0) ? matches.contains($0) : nil })
        }
        switch rule {
        case .manual: return []
        case .thermalPressure:
            return [textCondition(.thermal, "thermal_state", condition: "OSの熱状態が「高い」または「重大」",
                allowed: ["正常", "やや高い", "高い", "重大"], matches: ["高い", "重大"])]
        case .cpuBusy, .coreBusy:
            let metrics = snapshot.categories.first { $0.category == .cpu }?.metrics ?? []
            let candidates = metrics.filter { m in
                rule == .cpuBusy ? m.metricID == "idle" :
                    (m.metricID.hasPrefix("core") && Int(m.metricID.dropFirst(4)) != nil &&
                        (selectedCore == nil || selectedCore == m.metricID))
            }
            let valid = candidates.compactMap { m -> (ObservationMetric, Double)? in
                guard let n = number(m, range: 0...100), let interval = m.interval,
                      interval.isFinite, interval > 0, interval <= maximumGap else { return nil }
                return (m, rule == .cpuBusy ? 100 - n : n)
            }
            let highest = valid.max { $0.1 < $1.1 }
            let threshold = rule == .cpuBusy ? 90.0 : 95.0
            let complete = !candidates.isEmpty && valid.count == candidates.count
            let met: Bool? = highest.map { $0.1 >= threshold } == true ? true : (complete ? false : nil)
            return [evidence(highest?.0, id: highest?.0.metricID ?? rule.rawValue,
                condition: rule == .cpuBusy ? "全論理コア合計のCPU使用率が90%以上" : "同じ論理コアの使用率が95%以上",
                met: met, value: highest.map { String(format: "%@ 使用率 %.1f%%", $0.0.metricID, $0.1) })]
        case .swapAllocated:
            return [numeric(.memory, "swapUsed", condition: "スワップ領域が使用されている（負荷の参考情報）", test: { $0 > 0 })]
        case .batteryLow, .batteryCritical:
            let threshold = rule == .batteryCritical ? 5.0 : 20.0
            return [numeric(.battery, "charge_percent", condition: "バッテリー残量が\(Int(threshold))%以下", range: 0...100, test: { $0 <= threshold }),
                textCondition(.battery, "external_power", condition: "外部電源が未接続", allowed: ["接続", "未接続"], matches: ["未接続"])]
        case .chargingPaused:
            return [textCondition(.battery, "external_power", condition: "外部電源に接続中", allowed: ["接続", "未接続"], matches: ["接続"]),
                textCondition(.battery, "charging", condition: "充電していない（満充電や最適化も含む）",
                    allowed: ["充電中", "充電していない"], matches: ["充電していない"])]
        case .storageLow:
            let free = metric(.storage, "volumeFree"), total = metric(.storage, "volumeTotal")
            let f = number(free, range: 0...Double.greatestFiniteMagnitude)
            let t = number(total, range: 1...Double.greatestFiniteMagnitude)
            let valid = f != nil && t != nil && f! <= t!
            let low = valid ? (f! < 10 * 1_073_741_824 || f! / t! < 0.1) : nil
            let value = valid ? String(format: "起動データ領域の空き %.1f GiB / %.1f%%", f! / 1_073_741_824, f! / t! * 100) : nil
            return [evidence(free, id: "volumeFree", condition: "空き容量が10 GiB未満、または総容量の10%未満", met: low, value: value)]
        }
    }
}
