import Foundation

private func diagnosticExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "AIBOU.DiagnosticTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

func runDiagnosticTests() throws {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func fixture(at time: Date, idle: Double = 5, core: Double = 98, thermal: String = "高い",
                 status: ReadingStatus = .derived, segment: String = "test") -> ObservationSnapshot {
        ObservationSnapshot(panels: [
            PanelReading(tab: .cpu, metrics: [
                Metric("idle", "Idle", value: idle, unit: "%", status: status, source: "test", recordedAt: time, interval: 2),
                Metric("core0", "Core 0", value: core, unit: "%", status: status, source: "test", recordedAt: time, interval: 2)
            ], capturedAt: time),
            PanelReading(tab: .thermal, metrics: [Metric("thermal_state", "Thermal", text: thermal, source: "test", recordedAt: time)], capturedAt: time),
            PanelReading(tab: .memory, metrics: [Metric("swapUsed", "Swap", value: 1024, unit: "B", source: "test", recordedAt: time)], capturedAt: time),
            PanelReading(tab: .battery, metrics: [
                Metric("charge_percent", "Charge", value: 4, unit: "%", source: "test", recordedAt: time),
                Metric("external_power", "Power", text: "未接続", source: "test", recordedAt: time),
                Metric("charging", "Charging", text: "充電していない", source: "test", recordedAt: time)
            ], capturedAt: time),
            PanelReading(tab: .storage, metrics: CoreSampler.volumeMetrics(total: 500 * 1_073_741_824, free: 5 * 1_073_741_824, at: time), capturedAt: time)
        ], processes: [], capturedAt: time,
        collection: ObservationCollection(state: .running, segmentID: segment, sampleSegmentID: segment, lastSampleAt: time))
    }
    func state(_ rule: DiagnosticRule, _ engine: DiagnosticEngine, _ snapshot: ObservationSnapshot, at time: Date) -> DiagnosticState? {
        guard let id = DiagnosticCatalog.cases.first(where: { $0.rule == rule })?.id else { return nil }
        return engine.evaluate(snapshot, now: time).first { $0.id == id }?.state
    }
    var engine = DiagnosticEngine()
    var snapshot = fixture(at: start)
    engine.ingest(snapshot, now: start)
    try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: start) == .observing, "one CPU sample must not establish sustained load")
    for rule in [DiagnosticRule.thermalPressure, .swapAllocated, .batteryLow, .batteryCritical, .storageLow] {
        try diagnosticExpect(state(rule, engine, snapshot, at: start) == .matched, "fixture should match \(rule)")
    }
    try diagnosticExpect(state(.chargingPaused, engine, snapshot, at: start) == .notMatched, "disconnected AC is not a charging pause")
    for offset in stride(from: 2, through: 20, by: 2) {
        let time = start.addingTimeInterval(Double(offset))
        snapshot = fixture(at: time); engine.ingest(snapshot, now: time)
    }
    try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: start.addingTimeInterval(20)) == .matched, "20s host load should match")
    try diagnosticExpect(state(.coreBusy, engine, snapshot, at: start.addingTimeInterval(20)) == .matched, "20s same-core load should match")
    try diagnosticExpect(state(.thermalPressure, engine, snapshot, at: start.addingTimeInterval(31)) == .unknown, "stale values are not current diagnoses")

    let pausedTime = start.addingTimeInterval(20)
    var paused = snapshot; paused.collection.state = .paused
    try diagnosticExpect(state(.cpuBusy, engine, paused, at: pausedTime) == .unknown, "paused values cannot match")
    paused.collection.state = .stopped
    try diagnosticExpect(state(.batteryLow, engine, paused, at: pausedTime) == .unknown, "stopped values cannot match")
    paused.collection.state = .running; paused.collection.segmentID = "new"
    try diagnosticExpect(state(.thermalPressure, engine, paused, at: pausedTime) == .unknown, "old segment cannot match on resume")
    let resumeTime = start.addingTimeInterval(22)
    snapshot = fixture(at: resumeTime, segment: "new"); engine.ingest(snapshot, now: resumeTime)
    try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: resumeTime) == .observing, "resume resets duration")
    let gapTime = start.addingTimeInterval(40)
    snapshot = fixture(at: gapTime, segment: "new"); engine.ingest(snapshot, now: gapTime)
    try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: gapTime) == .observing, "missing samples reset duration")
    for _ in 0..<30 { engine.ingest(snapshot, now: gapTime) }
    try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: gapTime) == .observing, "duplicate samples never advance duration")

    engine.reset()
    for offset in stride(from: 0, through: 20, by: 2) {
        let time = start.addingTimeInterval(Double(offset))
        snapshot = fixture(at: time)
        let cpuIndex = snapshot.categories.firstIndex { $0.category == .cpu }!
        snapshot.categories[cpuIndex].metrics.append(ObservationMetric(Metric("core1", "Core 1",
            value: offset % 4 == 0 ? 99 : 96, unit: "%", status: .derived, source: "test", recordedAt: time, interval: 2)))
        engine.ingest(snapshot, now: time)
    }
    try diagnosticExpect(state(.coreBusy, engine, snapshot, at: start.addingTimeInterval(20)) == .matched,
                         "a continuously busy core must remain tracked when another core overtakes it")
    for offset in stride(from: 0, through: 20, by: 2) {
        let time = start.addingTimeInterval(Double(offset))
        snapshot = fixture(at: time)
        snapshot.collection = ObservationCollection(state: .snapshot, lastSampleAt: time)
        engine.ingest(snapshot, now: time)
        try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: time) == .observing,
                             "standalone snapshots must not establish monitoring continuity")
    }

    for status in [ReadingStatus.waiting, .denied, .unsupported, .unavailable, .partial, .stale, .estimated] {
        snapshot = fixture(at: start, status: status); engine.ingest(snapshot, now: start)
        try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: start) == .unknown, "bad CPU status \(status) must remain unknown")
    }
    for invalid in [Double.nan, Double.infinity, -1, 101] {
        snapshot = fixture(at: start, idle: invalid)
        try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: start) == .unknown, "invalid CPU value must remain unknown")
    }
    snapshot = fixture(at: start, idle: 75, core: 20, thermal: "正常"); engine.ingest(snapshot, now: start)
    try diagnosticExpect(state(.cpuBusy, engine, snapshot, at: start) == .notMatched, "low CPU resets trigger")
    try diagnosticExpect(state(.thermalPressure, engine, snapshot, at: start) == .notMatched, "nominal thermal should not match")
    snapshot = fixture(at: start, thermal: "不明")
    try diagnosticExpect(state(.thermalPressure, engine, snapshot, at: start) == .unknown, "unrecognized thermal must remain unknown")
    try diagnosticExpect(state(.thermalPressure, engine, snapshot, at: start.addingTimeInterval(-1)) == .unknown, "future readings must be rejected")
    snapshot.categories = []
    try diagnosticExpect(state(.batteryLow, engine, snapshot, at: start) == .unknown, "no battery is not a healthy battery")
    try diagnosticExpect(state(.storageLow, engine, snapshot, at: start) == .unknown, "missing capacity must be unknown")

    // All manual-only problems remain manual even with matching thermal or memory observations.
    let manualResults = engine.evaluate(fixture(at: start), now: start).filter { result in
        DiagnosticCatalog.cases.first { $0.id == result.id }?.rule == .manual
    }
    try diagnosticExpect(manualResults.allSatisfy { $0.state == .manual && $0.evidence.isEmpty }, "manual faults must never be inferred from unrelated metrics")
    try diagnosticExpect(DiagnosticCatalog.cases.count >= 60, "catalog should cover at least 60 distinct cases")
    try diagnosticExpect(Set(DiagnosticCatalog.cases.map(\.id)).count == DiagnosticCatalog.cases.count, "catalog IDs must be unique")
    for rule in DiagnosticRule.allCases where rule != .manual {
        try diagnosticExpect(DiagnosticCatalog.cases.filter { $0.rule == rule }.count == 1, "one catalog entry per automatic rule")
    }
    for item in DiagnosticCatalog.cases {
        try diagnosticExpect(!item.title.isEmpty && !item.symptoms.isEmpty && !item.causes.isEmpty && !item.actions.isEmpty && !item.checks.isEmpty && !item.limitation.isEmpty, "incomplete catalog case: \(item.id)")
        try diagnosticExpect(!item.sources.isEmpty && item.sources.allSatisfy { URL(string: $0)?.host == "support.apple.com" || URL(string: $0)?.host == "developer.apple.com" }, "official source required: \(item.id)")
    }
    for invalid in [CoreSampler.volumeMetrics(total: nil, free: nil, at: start),
                    CoreSampler.volumeMetrics(total: 10, free: 20, at: start),
                    CoreSampler.volumeMetrics(total: .nan, free: 0, at: start)] {
        try diagnosticExpect(invalid.allSatisfy { $0.status == .unavailable && $0.value == nil }, "invalid capacity must not become zero")
    }
    let encoded = try JSONEncoder().encode(engine.evaluate(fixture(at: start), now: start))
    let decoded = try JSONDecoder().decode([DiagnosticResult].self, from: encoded)
    try diagnosticExpect(decoded.count == DiagnosticCatalog.cases.count, "diagnostic results should roundtrip for future consumers")
}
