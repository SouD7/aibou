import Foundation

enum ObservationCategory: String, Codable, CaseIterable {
    case storage, cpu, gpu, clock, memory, thermal, battery, network, display, devices, hardware

    init(_ tab: MonitorTab) {
        self = ObservationCategory(rawValue: tab.rawValue)!
    }
}

enum ObservationStatus: String, Codable {
    case measured, derived, estimated, waiting, denied, unsupported, unavailable, partial, stale

    init(_ status: ReadingStatus) {
        self = ObservationStatus(rawValue: status.rawValue)!
    }
}

struct ObservationMetric: Codable {
    var metricID: String
    var value: Double?
    var text: String?
    var unit: String
    var status: ObservationStatus
    var source: String
    var detail: String
    var recordedAt: Date
    var interval: Double?

    init(_ metric: Metric) {
        metricID = metric.id
        value = metric.value
        text = metric.text
        unit = metric.unit
        status = ObservationStatus(metric.status)
        source = metric.source
        detail = metric.detail
        recordedAt = metric.recordedAt
        interval = metric.interval
    }
}

struct ObservationRow: Codable {
    var rowID: String
    var name: String
    var path: String?
    var bundleID: String?
    var metrics: [ObservationMetric]

    init(_ row: ReadingRow) {
        rowID = row.id
        name = row.name
        path = row.path
        bundleID = row.bundleID
        metrics = row.metrics.map(ObservationMetric.init)
    }
}

struct ObservationCategorySnapshot: Codable {
    var category: ObservationCategory
    var metrics: [ObservationMetric]
    var rows: [ObservationRow]

    init(_ panel: PanelReading) {
        category = ObservationCategory(panel.tab)
        metrics = panel.metrics.map(ObservationMetric.init)
        rows = panel.rows.map(ObservationRow.init)
    }
}

struct ObservationProcessIdentity: Codable, Hashable {
    var pid: Int32
    var startTime: Date
}

struct ObservationProcess: Codable {
    var identity: ObservationProcessIdentity
    var parentPID: Int32
    var name: String
    var path: String
    var owner: String
    var bundleID: String?
    var growthEvidence: String?
    var metrics: [ObservationMetric]

    init(_ process: ProcessSample, capturedAt: Date) {
        let interval = process.measurementInterval
        identity = ObservationProcessIdentity(pid: process.pid, startTime: process.startTime)
        parentPID = process.parentPID
        name = process.name
        path = process.path
        owner = process.owner
        bundleID = process.bundleID
        growthEvidence = process.growthNote
        metrics = [
            Self.metric("cpu.percent", value: process.cpuPercent, unit: "%",
                        status: process.cpuPercent == nil ? .waiting : .derived,
                        source: "proc_pid_rusage/proc_pidinfo", capturedAt: capturedAt, interval: interval),
            Self.metric("threads.count", value: process.threadCount.map { Double($0) }, unit: "count",
                        status: process.threadCount == nil ? .unavailable : .measured,
                        source: "proc_pidinfo(PROC_PIDTASKINFO)", capturedAt: capturedAt),
            Self.metric("memory.residentBytes", value: process.residentBytes.map { Double($0) }, unit: "B",
                        status: process.residentBytes == nil ? .unavailable : .measured,
                        source: "proc_pid_rusage/proc_taskinfo", capturedAt: capturedAt),
            Self.metric("memory.footprintBytes", value: process.footprintBytes.map { Double($0) }, unit: "B",
                        status: process.footprintBytes == nil ? .unavailable : .measured,
                        source: "proc_pid_rusage", capturedAt: capturedAt),
            Self.metric("disk.readBytes", value: process.diskReadBytes.map { Double($0) }, unit: "B",
                        status: process.diskReadBytes == nil ? .unavailable : .measured,
                        source: "proc_pid_rusage(RUSAGE_INFO_V2)", capturedAt: capturedAt),
            Self.metric("disk.writeBytes", value: process.diskWriteBytes.map { Double($0) }, unit: "B",
                        status: process.diskWriteBytes == nil ? .unavailable : .measured,
                        source: "proc_pid_rusage(RUSAGE_INFO_V2)", capturedAt: capturedAt),
            Self.metric("disk.readBytesPerSecond", value: process.readBytesPerSecond, unit: "B/s",
                        status: Self.rateStatus(value: process.readBytesPerSecond, cumulative: process.diskReadBytes),
                        source: "libproc counter delta", capturedAt: capturedAt, interval: interval),
            Self.metric("disk.writeBytesPerSecond", value: process.writeBytesPerSecond, unit: "B/s",
                        status: Self.rateStatus(value: process.writeBytesPerSecond, cumulative: process.diskWriteBytes),
                        source: "libproc counter delta", capturedAt: capturedAt, interval: interval)
        ]
    }

    private static func rateStatus(value: Double?, cumulative: UInt64?) -> ObservationStatus {
        if value != nil { return .derived }
        return cumulative == nil ? .unavailable : .waiting
    }

    private static func metric(_ id: String, value: Double?, unit: String,
                               status: ObservationStatus, source: String,
                               capturedAt: Date, interval: Double? = nil) -> ObservationMetric {
        ObservationMetric(metricID: id, value: value, text: nil, unit: unit, status: status,
                          source: source, detail: "", recordedAt: capturedAt, interval: interval)
    }
}

enum ObservationCollectionState: String, Codable {
    case snapshot, running, paused, stopped
}

struct ObservationCollection: Codable {
    var state: ObservationCollectionState
    /// Current basic monitoring segment; changes on resume, even before the next sample.
    var segmentID: String?
    /// Segment of the retained basic values; can differ from segmentID while resuming.
    var sampleSegmentID: String?
    var lastSampleAt: Date?
}

struct ObservationSnapshot: Codable {
    var schemaVersion: Int
    var capturedAt: Date
    var collection: ObservationCollection
    var categories: [ObservationCategorySnapshot]
    var processes: [ObservationProcess]

    init(panels: [PanelReading], processes: [ProcessSample], capturedAt: Date,
         collection: ObservationCollection? = nil) {
        schemaVersion = 2
        self.capturedAt = capturedAt
        self.collection = collection ?? ObservationCollection(state: .snapshot, lastSampleAt: capturedAt)
        categories = Self.mergedCategories(panels)
        self.processes = processes.map { ObservationProcess($0, capturedAt: capturedAt) }
    }

    init(core: CoreReading, additionalPanels: [PanelReading] = []) {
        self.init(panels: core.panels + additionalPanels,
                  processes: core.processes,
                  capturedAt: core.capturedAt)
    }

    private static func mergedCategories(_ panels: [PanelReading]) -> [ObservationCategorySnapshot] {
        var byCategory: [ObservationCategory: ObservationCategorySnapshot] = [:]
        for panel in panels {
            let incoming = ObservationCategorySnapshot(panel)
            if var existing = byCategory[incoming.category] {
                existing.metrics = mergeMetrics(existing.metrics, incoming.metrics)
                existing.rows = mergeRows(existing.rows, incoming.rows)
                byCategory[incoming.category] = existing
            } else {
                byCategory[incoming.category] = incoming
            }
        }
        return ObservationCategory.allCases.compactMap { byCategory[$0] }
    }

    private static func mergeMetrics(_ existing: [ObservationMetric],
                                     _ incoming: [ObservationMetric]) -> [ObservationMetric] {
        var result = existing
        var indices = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.element.metricID, $0.offset) })
        for metric in incoming {
            if let index = indices[metric.metricID] { result[index] = metric }
            else { indices[metric.metricID] = result.count; result.append(metric) }
        }
        return result
    }

    private static func mergeRows(_ existing: [ObservationRow],
                                  _ incoming: [ObservationRow]) -> [ObservationRow] {
        var result = existing
        var indices = Dictionary(uniqueKeysWithValues: result.enumerated().map { ($0.element.rowID, $0.offset) })
        for row in incoming {
            if let index = indices[row.rowID] {
                var merged = result[index]
                merged.metrics = mergeMetrics(merged.metrics, row.metrics)
                if merged.path == nil { merged.path = row.path }
                if merged.bundleID == nil { merged.bundleID = row.bundleID }
                result[index] = merged
            } else { indices[row.rowID] = result.count; result.append(row) }
        }
        return result
    }
}

private extension ObservationMetric {
    init(metricID: String, value: Double?, text: String?, unit: String,
         status: ObservationStatus, source: String, detail: String,
         recordedAt: Date, interval: Double?) {
        self.metricID = metricID
        self.value = value
        self.text = text
        self.unit = unit
        self.status = status
        self.source = source
        self.detail = detail
        self.recordedAt = recordedAt
        self.interval = interval
    }
}
