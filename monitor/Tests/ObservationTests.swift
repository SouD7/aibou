import Foundation

private func observationExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "AIBOU.ObservationTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func runObservationTests() throws {
    let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let metric = Metric("cpu.user", "ユーザー利用", value: 12.5, unit: "%", status: .derived,
                        source: "fixture source", detail: "fixture detail",
                        recordedAt: capturedAt, interval: 2)
    let row = ReadingRow(id: "42:1700000000", name: "Fixture Process", metrics: [
        Metric("resident", "常駐量", value: 123_456, unit: "B", source: "fixture row source",
               recordedAt: capturedAt)
    ], note: "display-only note", path: "/Applications/Fixture.app/Contents/MacOS/Fixture",
       bundleID: "example.fixture")
    let cpuPanel = PanelReading(tab: .cpu, metrics: [metric],
                                columns: [TableColumn("resident", "表示列", width: 777)],
                                rows: [row], notes: ["display-only panel note"], capturedAt: capturedAt)
    let supplemental = PanelReading(tab: .cpu, metrics: [
        Metric("cpu.extra", "追加表示", text: "ok", status: .measured,
               source: "supplemental", recordedAt: capturedAt)
    ], capturedAt: capturedAt)
    let process = ProcessSample(pid: 42, parentPID: 1, startTime: capturedAt,
                                name: "Fixture Process", path: row.path!, owner: "App: Fixture",
                                bundleID: "example.fixture", cpuPercent: 25, threadCount: 3,
                                residentBytes: 123_456, footprintBytes: 234_567,
                                diskReadBytes: 5_000_000_000, diskWriteBytes: nil,
                                readBytesPerSecond: 2_048, writeBytesPerSecond: nil,
                                growthNote: "ten-minute evidence", measurementInterval: 2.375)
    let core = CoreReading(panels: [cpuPanel], processes: [process], capturedAt: capturedAt)
    let snapshot = ObservationSnapshot(core: core, additionalPanels: [supplemental])

    try observationExpect(snapshot.schemaVersion == 2 && snapshot.capturedAt == capturedAt,
                          "snapshot identity fields were not preserved")
    try observationExpect(snapshot.collection.state == .snapshot && snapshot.collection.lastSampleAt == capturedAt &&
                          snapshot.collection.segmentID == nil,
                          "standalone samples must not invent an ongoing monitoring session")
    try observationExpect(snapshot.categories.count == 1 && snapshot.categories[0].category == .cpu,
                          "panels of one category should merge into one stable category")
    try observationExpect(snapshot.categories[0].metrics.map(\.metricID) == ["cpu.user", "cpu.extra"],
                          "stable metric IDs should survive projection and category merging")
    try observationExpect(snapshot.categories[0].rows[0].path == row.path,
                          "row identity and path should survive projection")
    try observationExpect(snapshot.processes[0].identity == ObservationProcessIdentity(pid: 42, startTime: capturedAt),
                          "process identity must include PID and start time")
    let diskRead = snapshot.processes[0].metrics.first { $0.metricID == "disk.readBytes" }
    try observationExpect(diskRead?.value == 5_000_000_000 && diskRead?.status == .measured,
                          "process metrics must preserve numeric values above 4 GiB")
    for id in ["cpu.percent", "disk.readBytesPerSecond", "disk.writeBytesPerSecond"] {
        let projected = snapshot.processes[0].metrics.first { $0.metricID == id }
        try observationExpect(projected?.interval == 2.375, "actual process interval was lost: \(id)")
    }
    try observationExpect(snapshot.processes[0].metrics.first { $0.metricID == "memory.residentBytes" }?.interval == nil,
                          "instantaneous memory values must not invent a rate window")
    var firstSample = process
    firstSample.measurementInterval = nil; firstSample.cpuPercent = nil
    let initial = ObservationSnapshot(panels: [], processes: [firstSample], capturedAt: capturedAt)
    try observationExpect(initial.processes[0].metrics.first?.interval == nil, "first sample has no rate window")
    let diskWrite = snapshot.processes[0].metrics.first { $0.metricID == "disk.writeBytes" }
    try observationExpect(diskWrite?.value == nil && diskWrite?.status == .unavailable,
                          "missing process values must remain unavailable rather than zero")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let jsonData = try encoder.encode(snapshot)
    let json = String(decoding: jsonData, as: UTF8.self)
    for forbidden in ["label", "columns", "width", "formatted", "symbol", "display-only note", "display-only panel note"] {
        try observationExpect(!json.contains(forbidden), "observation JSON leaked display metadata: \(forbidden)")
    }
    for required in ["metricID", "cpu.user", "fixture source", "recordedAt", "interval", "rowID", "example.fixture"] {
        try observationExpect(json.contains(required), "observation JSON omitted semantic field: \(required)")
    }

    let decoded = try JSONDecoder().decode(ObservationSnapshot.self, from: jsonData)
    try observationExpect(decoded.collection.state == .snapshot && decoded.collection.lastSampleAt == capturedAt,
                          "collection metadata must round-trip")
    try observationExpect(decoded.processes.first?.identity.pid == 42 &&
                          decoded.categories.first?.metrics.first?.value == 12.5,
                          "observation snapshot must round-trip through Codable")
}
