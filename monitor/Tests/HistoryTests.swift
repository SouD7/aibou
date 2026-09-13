import Foundation

func runHistoryTests() throws {
    func check(_ ok: Bool, _ message: String) throws {
        if !ok { throw NSError(domain: "HistoryRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    let now = Date(timeIntervalSince1970: 2_000_000)
    let frames = [
        HistoryFrame(date: now, segment: "a", values: ["cpu.user": 1]),
        HistoryFrame(date: now.addingTimeInterval(10), segment: "a", values: ["cpu.system": 2]),
        HistoryFrame(date: now.addingTimeInterval(20), segment: "a", values: ["cpu.user": 3]),
        HistoryFrame(date: now.addingTimeInterval(30), segment: "a", values: ["cpu.user": 4]),
        HistoryFrame(date: now.addingTimeInterval(50), segment: "a", values: ["cpu.user": 5]),
        HistoryFrame(date: now.addingTimeInterval(60), segment: "b", values: ["cpu.user": 6])
    ]
    let points = HistoryLedger(frames: frames).series(for: "cpu.user")
    try check(points.count == 5, "missing values must not become zero samples")
    try check(points[0].segment != points[1].segment, "a missing metric must break its line")
    try check(points[1].segment == points[2].segment, "adjacent valid samples must remain connected")
    try check(points[2].segment != points[3].segment, "one missing 10-second frame (20-second gap) must break the line")
    try check(points[3].segment != points[4].segment, "pause/resume segment must break the line")
    var restored = HistoryLedger(frames: [frames[3], frames[0],
        HistoryFrame(date: now.addingTimeInterval(-90_000), segment: "old", values: [:]),
        HistoryFrame(date: now, segment: "invalid", values: ["memory.wired": 1e-310, "cpu.user": .infinity])])
    restored.sanitizeAfterLoading(now: now.addingTimeInterval(30))
    try check(restored.frames.count == 3, "restoration must remove expired frames")
    try check(restored.frames.map(\.date) == restored.frames.map(\.date).sorted(), "restored frames must be sorted")
    try check(restored.frames.allSatisfy { $0.values.values.allSatisfy(\.isFinite) }, "nonfinite archived readings must be removed")
    try check(restored.frames.allSatisfy { $0.values["memory.wired"] == nil }, "old conversion corruption must be removed on load")
    var foreign = HistoryLedger(frames: [HistoryFrame(date: now, segment: "fixture", values: [
        "cpu.user": 12, "cpu.core12": 9, "gpu.power.fields": 3,
        "cpu.process.secret": 42, "network.destination": 1, "unknown.value": 2,
        "cpu.core1.extra": 3, "cpu": 4
    ])])
    foreign.sanitizeAfterLoading(now: now)
    try check(foreign.frames[0].values == ["cpu.user": 12, "cpu.core12": 9, "gpu.power.fields": 3],
              "restoration must apply the same aggregate allowlist, including dotted IDs")
    var full = HistoryLedger(frames: (0..<9000).map { HistoryFrame(date: now.addingTimeInterval(Double($0-8999)*10), segment: "a", values: ["cpu.user": 1]) })
    full.prune(now: now)
    try check(full.frames.count <= HistoryLedger.maximumFrames && full.frames.first!.date >= now.addingTimeInterval(-86400), "history retention must stay bounded")
}
