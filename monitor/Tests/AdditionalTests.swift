import Foundation

private enum AdditionalTestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String { if case .assertion(let message) = self { return message }; return "failure" }
}

private func additionalExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw AdditionalTestFailure.assertion(message) }
}

private final class CommandResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CommandOutput?
    func set(_ value: CommandOutput) { lock.lock(); stored = value; lock.unlock() }
    func get() -> CommandOutput? { lock.lock(); defer { lock.unlock() }; return stored }
}

func runAdditionalTests() throws {
    try testCSVReaderAndNettopBatches()
    try testNettopFirstSampleAndMissingValues()
    try testPowerMetricsParsing()
    try testPowerParsingLimits()
    try testCommandTimeoutCancelAndLargeOutput()
    try testHistoryRetentionAndPrivacy()
}

private func testCSVReaderAndNettopBatches() throws {
    let csv = """
    ,state,packets_in,bytes_in,packets_out,bytes_out,re-tx,rtt_avg,rtt_var,
    old.99,,1,10,2,20,0,,,
    ,state,packets_in,bytes_in,packets_out,bytes_out,re-tx,rtt_avg,rtt_var,
    apsd.575,,1226,159651,1334,388296,15572,,,
    "tcp6 [fe80::1]:123<->[2001:db8::2]:443,flow",Established,4,300,5,400,1,24.56 ms,14.50 ms,
    """
    let process = ProcessSample(pid: 575, parentPID: 1, startTime: Date(timeIntervalSince1970: 1),
                                name: "apsd", path: "/usr/libexec/apsd", owner: "システム", bundleID: nil,
                                cpuPercent: nil, threadCount: nil, residentBytes: nil, footprintBytes: nil,
                                diskReadBytes: nil, diskWriteBytes: nil, readBytesPerSecond: nil,
                                writeBytesPerSecond: nil, growthNote: nil)
    let panel = NetworkDetailCollector.parse(CommandOutput(text: csv, code: 0, timedOut: false, truncated: false), processes: [process])
    try additionalExpect(panel.rows.count == 2, "only the final repeated-header nettop sample should be retained")
    let aggregate = try panel.rows.first.unwrapAdditional("nettop process row missing")
    try additionalExpect(aggregate.name == "apsd.575", "blank first header column must be used as process label")
    try additionalExpect(aggregate.metric("owner")?.text == "システム", "PID must be attributed to the current process inventory")
    try additionalExpect(aggregate.metric("receiveRate")?.value == 159_651, "second delta sample should become a one-second receive rate")
    let connection = try panel.rows.last.unwrapAdditional("IPv6 connection row missing")
    try additionalExpect(connection.name.contains("2001:db8::2"), "quoted IPv6 destination was damaged by CSV parsing")
    try additionalExpect(connection.metric("owner")?.text == "システム", "connection row should inherit its process attribution")
    try additionalExpect(connection.metric("rtt_avg")?.text == "24.56 ms", "RTT source unit must be preserved")
}

private func testNettopFirstSampleAndMissingValues() throws {
    let firstOnly = """
    ,state,bytes_in,bytes_out,
    sample.10,,200,300,
    """
    let first = NetworkDetailCollector.parse(CommandOutput(text: firstOnly, code: 0, timedOut: false, truncated: false))
    try additionalExpect(first.rows.first?.metric("receiveRate")?.status == .waiting, "first sample must not fabricate a byte rate")
    try additionalExpect(first.rows.first?.metric("receiveRate")?.value == nil, "first sample rate must be absent")
    let stamped = "time,process,bytes_in,bytes_out,\n12:00:01.000,sample.10,200,300,\n"
    let stampedFirst = NetworkDetailCollector.parse(CommandOutput(text: stamped, code: 0, timedOut: false, truncated: false))
    try additionalExpect(stampedFirst.rows.first?.metric("receiveRate")?.status == .waiting, "one timestamp is not evidence of a second sample")
    let stampedSecond = NetworkDetailCollector.parse(CommandOutput(text: stamped + "12:00:02.000,sample.10,40,50,\n", code: 0, timedOut: false, truncated: false))
    try additionalExpect(stampedSecond.rows.count == 1 && stampedSecond.rows.first?.metric("receiveRate")?.value == 40, "two timestamp groups use only final delta")

    let malformed = """
    ,state,bytes_in,bytes_out,
    sample.10,,1,2,
    ,state,bytes_in,bytes_out,
    sample.10,,nan,not-a-number,
    """
    let bad = NetworkDetailCollector.parse(CommandOutput(text: malformed, code: 0, timedOut: false, truncated: false))
    try additionalExpect(bad.rows.first?.metric("bytes_in")?.status == .unavailable, "NaN source value must be unavailable")
    try additionalExpect(bad.rows.first?.metric("receiveRate")?.value == nil, "NaN must never enter a metric")
    try additionalExpect(bad.rows.first?.metric("bytes_out")?.status == .unavailable, "malformed numeric column must be unavailable")
}

private func testPowerMetricsParsing() throws {
    let fixture: [String: Any] = [
        "processor": ["clusters": [["frequency_hz": 2_400_000_000]]],
        "gpu": ["active_time_ns": 123_456, "process_name": "fixture"],
        "tasks": [
            ["pid": 575, "command": "apsd", "gpu_time_ns": 42_000],
            ["command": "no-pid", "gpu_time_ns": 7_000]
        ],
        "thermal": ["pressure": "Nominal"]
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0)
    let output = CommandOutput(text: "prefix\n" + String(decoding: data, as: UTF8.self) + "\nsuffix", code: 0, timedOut: false, truncated: false)
    let process = ProcessSample(pid: 575, parentPID: 1, startTime: Date(timeIntervalSince1970: 1),
                                name: "apsd", path: "/usr/libexec/apsd", owner: "システム", bundleID: nil,
                                cpuPercent: nil, threadCount: nil, residentBytes: nil, footprintBytes: nil,
                                diskReadBytes: nil, diskWriteBytes: nil, readBytesPerSecond: nil,
                                writeBytesPerSecond: nil, growthNote: nil)
    let panels = PowerDetailCollector.parse(output, processes: [process])
    try additionalExpect(Set(panels.map(\.tab)) == Set([.gpu, .clock, .thermal]), "powermetrics parser returned the wrong panels")
    let gpu = try panels.first(where: { $0.tab == .gpu }).unwrapAdditional("GPU power panel missing")
    try additionalExpect(gpu.rows.contains { $0.name.contains("active_time_ns") }, "raw GPU time field was lost")
    try additionalExpect(!gpu.rows.contains { $0.name.localizedCaseInsensitiveContains("percent") }, "GPU percentage must not be fabricated")
    let attributed = try gpu.rows.first(where: { $0.name.hasPrefix("apsd —") }).unwrapAdditional("task GPU field lost process context")
    try additionalExpect(attributed.metric("pid")?.value == 575, "GPU task PID was not preserved")
    try additionalExpect(attributed.metric("parent")?.value == 1, "GPU task parent PID was not joined")
    try additionalExpect(attributed.metric("owner")?.text == "システム", "GPU task owner was not joined")
    try additionalExpect(attributed.metric("raw")?.unit == "ns", "explicit GPU source unit was not preserved")
    try additionalExpect(attributed.note.contains("起動時刻"), "PID reuse limitation must be shown")
    let noPID = try gpu.rows.first(where: { $0.name.hasPrefix("no-pid —") }).unwrapAdditional("PID-less GPU task missing")
    try additionalExpect(noPID.metric("pid")?.value == nil && noPID.metric("owner")?.text == nil,
                         "array index or process name must not be used as process identity")
    try additionalExpect(noPID.note.contains("配列番号"), "PID-less attribution limitation must be shown")
    try additionalExpect(panels.allSatisfy { $0.notes.first?.contains("元のフィールド名") == true }, "raw-field limitation must remain visible")

    let invalid = PowerDetailCollector.parse(CommandOutput(text: "not plist", code: 0, timedOut: false, truncated: false))
    try additionalExpect(invalid.allSatisfy { $0.metrics.first?.status == .unavailable }, "invalid powermetrics output must fail honestly")
    let reversed = PowerDetailCollector.parse(CommandOutput(text: "</plist> junk <?xml", code: 0, timedOut: false, truncated: false))
    try additionalExpect(reversed.allSatisfy { $0.metrics.first?.status == .unavailable }, "reversed plist markers must not trap or parse")
}

private func testPowerParsingLimits() throws {
    func parse(_ object: Any) throws -> [PanelReading] {
        let data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        return PowerDetailCollector.parse(CommandOutput(text: String(decoding: data, as: UTF8.self), code: 0, timedOut: false, truncated: false))
    }
    let exact: [String: Any] = ["aaa": Array(repeating: 1, count: 11_999), "gpu_time_ns": 123]
    let full = try parse(exact)
    try additionalExpect(full.first { $0.tab == .gpu }?.metrics.first?.status == .measured, "exact leaf limit with no omitted fields is complete")
    let over: [String: Any] = ["aaa": Array(repeating: 1, count: 12_000), "gpu_time_ns": 123]
    let missing = try parse(over)
    try additionalExpect(missing.allSatisfy { $0.metrics.first?.status == .partial }, "parse limit must never be misreported as unsupported")
    try additionalExpect(missing.allSatisfy { $0.metrics.first?.detail.contains("12,000") == true }, "leaf limit reason must be visible")
    let retained = try parse(["aaa_gpu_time_ns": 123, "zzz": Array(repeating: 1, count: 12_000)])
    let gpu = retained.first { $0.tab == .gpu }!
    try additionalExpect(gpu.metrics.first?.status == .partial && gpu.rows.first?.metric("raw")?.value == 123,
                         "retain individual measured values while flagging the incomplete collection")
    var nested: Any = ["gpu_time_ns": 456]
    for _ in 0..<15 { nested = ["container": nested] }
    let deep = try parse(nested)
    try additionalExpect(deep.allSatisfy { $0.metrics.first?.status == .partial }, "depth limit must be reported even with zero matched fields")
    try additionalExpect(deep.allSatisfy { $0.metrics.first?.detail.contains("深さ") == true }, "depth limit reason must be visible")
}

private func testCommandTimeoutCancelAndLargeOutput() throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-cancel-before-start-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    let pendingRunner = CommandRunner()
    let pending = pendingRunner.reserveOperation()!
    pendingRunner.cancel()
    let refused = pendingRunner.run(pending, "/usr/bin/touch", [marker.path])
    try additionalExpect(refused.code != 0 && !FileManager.default.fileExists(atPath: marker.path), "cancelled pending operation must never launch")
    let next = pendingRunner.reserveOperation()!
    try additionalExpect(pendingRunner.run(next, "/usr/bin/touch", [marker.path]).code == 0, "a newly reserved operation must work after cancel")
    try FileManager.default.removeItem(at: marker)
    try additionalExpect(pendingRunner.run(next, "/usr/bin/touch", [marker.path]).code != 0, "an operation token must be single-use")
    let beforeShutdown = pendingRunner.reserveOperation()!
    pendingRunner.shutdown()
    try additionalExpect(pendingRunner.reserveOperation() == nil, "shutdown must reject future reservations")
    let shutdownRefused = pendingRunner.run(beforeShutdown, "/usr/bin/touch", [marker.path])
    try additionalExpect(shutdownRefused.code != 0 && !FileManager.default.fileExists(atPath: marker.path), "shutdown must reject already reserved operations")
    let timeoutRunner = CommandRunner()
    let started = Date()
    let timed = timeoutRunner.run("/bin/sleep", ["2"], timeout: 0.05)
    try additionalExpect(timed.timedOut, "command timeout was not reported")
    try additionalExpect(Date().timeIntervalSince(started) < 1.5, "timed-out command was not terminated promptly")

    let cancelRunner = CommandRunner(), resultBox = CommandResultBox(), completed = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: .utility).async {
        resultBox.set(cancelRunner.run("/bin/sleep", ["5"], timeout: 3))
        completed.signal()
    }
    Thread.sleep(forTimeInterval: 0.1)
    cancelRunner.cancel()
    try additionalExpect(completed.wait(timeout: .now() + 1) == .success, "cancel did not terminate the running command")
    try additionalExpect(resultBox.get()?.timedOut == false, "explicit cancellation was mislabeled as timeout")

    let stubbornRunner = CommandRunner(), stubbornBox = CommandResultBox(), stubbornDone = DispatchSemaphore(value: 0)
    defer { stubbornRunner.shutdown() }
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    DispatchQueue.global(qos: .utility).async {
        stubbornBox.set(stubbornRunner.run(executable, ["--ignore-term-fixture", marker.path], timeout: 120))
        stubbornDone.signal()
    }
    let readyDeadline = Date().addingTimeInterval(3)
    while !FileManager.default.fileExists(atPath: marker.path), Date() < readyDeadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    try additionalExpect(FileManager.default.fileExists(atPath: marker.path), "signal-ignoring fixture did not start")
    try additionalExpect(!stubbornRunner.waitForDirectProcess(until: .now()), "cleanup wait must see a running direct process")
    stubbornRunner.shutdown()
    try additionalExpect(stubbornDone.wait(timeout: .now() + 3) == .success,
                         "shutdown must escalate direct task cancellation without waiting 120 seconds")
    try additionalExpect(stubbornBox.get()?.cancelled == true && stubbornBox.get()?.timedOut == false &&
                         stubbornBox.get()?.directProcessExited == true,
                         "cancellation must distinguish the request from confirmed direct task exit")
    try additionalExpect(stubbornRunner.waitForDirectProcess(until: .now()), "finished cleanup must release its termination wait")

    try FileManager.default.removeItem(at: marker)
    let racingRunner = CommandRunner(), racingBox = CommandResultBox(), racingDone = DispatchSemaphore(value: 0)
    defer { racingRunner.shutdown() }
    DispatchQueue.global(qos: .utility).async {
        racingBox.set(racingRunner.run(executable, ["--ignore-term-fixture", marker.path], timeout: 0.3))
        racingDone.signal()
    }
    let racingDeadline = Date().addingTimeInterval(3)
    while !FileManager.default.fileExists(atPath: marker.path), Date() < racingDeadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    try additionalExpect(FileManager.default.fileExists(atPath: marker.path), "timeout/cancel fixture did not start")
    Thread.sleep(forTimeInterval: 0.4)
    racingRunner.cancel() // Wake the timeout's grace wait; this is not a process-exit signal.
    try additionalExpect(racingDone.wait(timeout: .now() + 3) == .success && racingBox.get()?.directProcessExited == true,
                         "cancel during timeout escalation must not skip direct task termination")

    let large = CommandRunner().run("/usr/bin/yes", [], timeout: 0.1)
    try additionalExpect(large.timedOut, "large-output fixture should reach its timeout")
    try additionalExpect(large.truncated, "large pipe output should be bounded and marked truncated")
    try additionalExpect(large.text.utf8.count <= 8_000_000, "command buffer exceeded its byte cap")
    try additionalExpect(timed.directProcessExited == true && timed.cancelled == false,
                         "timeout must report direct task exit independently of cancellation")
    try additionalExpect(refused.cancelled && refused.directProcessExited == nil,
                         "a refused launch must not claim an observed process exit")
    let adminTimeout = PowerDetailCollector.panels(for: timed, administrator: true)
    try additionalExpect(adminTimeout.allSatisfy { panel in
        panel.notes.contains { $0.contains("認証コマンドの終了を確認") && $0.contains("powermetricsの終了は未確認") }
    }, "admin timeout must not equate direct process exit with elevated descendant exit")
}

private func testHistoryRetentionAndPrivacy() throws {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let sensitiveRow = ReadingRow(id: "42", name: "SecretProcess", metrics: [
        Metric("destination", "接続先", text: "2001:db8::secret", source: "fixture", recordedAt: now)
    ], path: "/Users/person/secret.txt", bundleID: "private.bundle")
    let panel = PanelReading(tab: .network, metrics: [
        Metric("rxRate", "受信速度", value: 123, unit: "B/s", status: .derived, source: "fixture", recordedAt: now),
        Metric("/Users/person/secret.txt", "path", value: 999, source: "fixture", recordedAt: now),
        Metric("destination:2001:db8::secret", "destination", value: 888, source: "fixture", recordedAt: now)
    ], rows: [sensitiveRow], capturedAt: now)
    var ledger = HistoryLedger(frames: [
        HistoryFrame(date: now.addingTimeInterval(-86_401), segment: "old", values: ["cpu.user": 1]),
        HistoryFrame(date: now.addingTimeInterval(120), segment: "future", values: ["cpu.user": 2])
    ])
    ledger.append(panels: [panel], segment: "live", now: now)
    try additionalExpect(ledger.frames.count == 1, "24-hour and future-frame pruning failed")
    let values = try (ledger.frames.first?.values).unwrapAdditional("history frame missing")
    try additionalExpect(values == ["network.rxRate": 123], "history allowlist retained a path, destination, or unknown field")
    let encoded = try JSONEncoder().encode(ledger)
    let json = String(decoding: encoded, as: UTF8.self)
    try additionalExpect(!json.contains("SecretProcess") && !json.contains("secret.txt") && !json.contains("db8"),
                         "history serialization leaked process, path, or destination data")

    ledger.append(panels: [panel], segment: "live", now: now.addingTimeInterval(5))
    try additionalExpect(ledger.frames.count == 1, "ten-second history aggregation was not enforced")
    ledger.append(panels: [panel], segment: "after-resume", now: now.addingTimeInterval(5))
    try additionalExpect(ledger.frames.count == 2, "a new observation segment should not be suppressed")
}

private extension Optional {
    func unwrapAdditional(_ message: String) throws -> Wrapped {
        guard let value = self else { throw AdditionalTestFailure.assertion(message) }
        return value
    }
}
