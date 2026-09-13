import Foundation

struct HistoryFrame: Codable, Identifiable {
    var date: Date
    var segment: String
    var values: [String: Double]
    var id: Date { date }
}

struct HistoryLedger: Codable {
    var version = 1
    var frames: [HistoryFrame] = []
    static let retention: TimeInterval = 24 * 60 * 60
    static let maximumFrames = 8641

    private static let allowedMetricIDs: [MonitorTab: Set<String>] = [
        .cpu: ["logicalCores", "processCount", "threadCount", "user", "system", "idle"],
        .memory: ["physical", "occupied", "wired", "uncompressed", "compressed", "fileCache", "swapTotal", "swapUsed"],
        .battery: ["charge_percent", "time_remaining", "full_charge_capacity", "battery_voltage", "battery_current", "battery_power", "adapter_rated_power"],
        .network: ["rxBytes", "txBytes", "rxRate", "txRate"],
        .thermal: ["fan_rpm", "fan_min_rpm", "fan_max_rpm", "cpu_temperature", "gpu_temperature"],
        .clock: ["uptimeInterval", "continuousInterval", "sleepGap", "jitter", "wallStep"],
        .storage: ["deviceRead", "deviceWrite", "deviceReadRate", "deviceWriteRate", "deviceErrors"],
        .gpu: ["power.fields"]
    ]

    /// Full validation belongs to archive restoration, never the periodic sampling path.
    mutating func sanitizeAfterLoading(now: Date) {
        let byteKeys: Set<String> = ["memory.occupied", "memory.wired", "memory.uncompressed", "memory.compressed", "memory.fileCache"]
        for index in frames.indices {
            frames[index].values = frames[index].values.filter { key, value in
                let parts = key.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, let tab = MonitorTab(rawValue: String(parts[0])),
                      Self.isAllowed(String(parts[1]), tab: tab) else { return false }
                return value.isFinite && !(byteKeys.contains(key) && value > 0 && value < 1)
            }
        }
        frames.removeAll { $0.date > now.addingTimeInterval(60) }
        frames.sort { $0.date < $1.date }
        prune(now: now)
    }

    /// Frames stay chronological. Find the expired prefix without visiting every value.
    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        var lower = 0, upper = frames.count
        while lower < upper {
            let mid = (lower + upper) / 2
            if frames[mid].date < cutoff { lower = mid + 1 } else { upper = mid }
        }
        let remove = max(lower, frames.count - Self.maximumFrames)
        if remove > 0 { frames.removeFirst(remove) }
        // A wall-clock correction starts a fresh chronological range.
        if let last = frames.last, last.date > now.addingTimeInterval(60) {
            frames.removeAll { $0.date > now }
        }
    }

    func series(for key: String, maximumGap: TimeInterval = 15) -> [HistoryChartPoint] {
        var result: [HistoryChartPoint] = []
        var last: HistoryFrame?, run = 0
        for frame in frames {
            guard let value = frame.values[key], value.isFinite else { last = nil; continue }
            if last == nil || last!.segment != frame.segment || frame.date.timeIntervalSince(last!.date) > maximumGap {
                run += 1
            }
            result.append(HistoryChartPoint(date: frame.date, value: value, segment: "\(frame.segment):\(run)"))
            last = frame
        }
        return result
    }

    mutating func append(panels: [PanelReading], segment: String, now: Date = Date()) {
        prune(now: now)
        // Ten-second aggregate history: process rows, paths, destinations and static inventory are excluded.
        if let last = frames.last, last.segment == segment, now.timeIntervalSince(last.date) >= 0, now.timeIntervalSince(last.date) < 10 { return }
        if let last = frames.last, last.date >= now { frames.removeAll { $0.date >= now } }
        let allowed: Set<MonitorTab> = [.cpu, .memory, .battery, .network, .thermal, .gpu, .clock, .storage]
        var values: [String: Double] = [:]
        for panel in panels where allowed.contains(panel.tab) {
            for metric in panel.metrics where Self.isAllowed(metric.id, tab: panel.tab) && [.measured, .derived, .estimated].contains(metric.status) {
                if let value = metric.value, value.isFinite, now.timeIntervalSince(metric.recordedAt) < 10 {
                    values["\(panel.tab.rawValue).\(metric.id)"] = value
                }
            }
        }
        guard !values.isEmpty else { return }
        frames.append(HistoryFrame(date: now, segment: segment, values: values))
        if frames.count > Self.maximumFrames { frames.removeFirst(frames.count - Self.maximumFrames) }
    }

    private static func isAllowed(_ id: String, tab: MonitorTab) -> Bool {
        if tab == .cpu, id.range(of: #"^core\d+$"#, options: .regularExpression) != nil { return true }
        return allowedMetricIDs[tab]?.contains(id) == true
    }
}

struct HistoryChartPoint: Identifiable {
    var date: Date
    var value: Double
    var segment: String
    var id: String { "\(segment):\(date.timeIntervalSince1970)" }
}

enum LocalArchive {
    static func directory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIBOU Monitor", isDirectory: true)
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func read<T: Decodable>(_ type: T.Type, from url: URL, maximumBytes: Int = 32_000_000) throws -> T {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw NSError(domain: "AIBOU", code: 1, userInfo: [NSLocalizedDescriptionKey: "保存ファイルが上限を超えています"] ) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
}
