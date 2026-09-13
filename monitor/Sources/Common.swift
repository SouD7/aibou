import Foundation

enum MonitorTab: String, CaseIterable, Codable, Identifiable {
    case storage, cpu, gpu, clock, memory, thermal, battery, network, display, devices, hardware
    var id: String { rawValue }
    var title: String {
        switch self {
        case .storage: return "ストレージ"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .clock: return "クロック"
        case .memory: return "メモリ"
        case .thermal: return "ファン・温度"
        case .battery: return "バッテリー"
        case .network: return "ネットワーク"
        case .display: return "ディスプレイ"
        case .devices: return "外部機器"
        case .hardware: return "ハードウェア"
        }
    }
    var symbol: String {
        switch self {
        case .storage: return "internaldrive"
        case .cpu: return "cpu"
        case .gpu: return "rectangle.3.group"
        case .clock: return "clock"
        case .memory: return "memorychip"
        case .thermal: return "thermometer.medium"
        case .battery: return "battery.75percent"
        case .network: return "network"
        case .display: return "display"
        case .devices: return "cable.connector"
        case .hardware: return "desktopcomputer"
        }
    }
}

enum ReadingStatus: String, Codable {
    case measured, derived, estimated, waiting, denied, unsupported, unavailable, partial, stale
    var title: String {
        switch self {
        case .measured: return "実測"
        case .derived: return "差分・算出"
        case .estimated: return "推定"
        case .waiting: return "計測待ち"
        case .denied: return "権限不足"
        case .unsupported: return "非対応"
        case .unavailable: return "取得失敗"
        case .partial: return "部分取得"
        case .stale: return "過去値"
        }
    }
}

struct Metric: Codable, Identifiable {
    var id: String
    var label: String
    var value: Double?
    var text: String?
    var unit: String
    var status: ReadingStatus
    var source: String
    var detail: String
    var recordedAt: Date
    var interval: Double?

    init(_ id: String, _ label: String, value: Double? = nil, text: String? = nil,
         unit: String = "", status: ReadingStatus = .measured, source: String,
         detail: String = "", recordedAt: Date = Date(), interval: Double? = nil) {
        self.id = id; self.label = label; self.value = value; self.text = text
        self.unit = unit; self.status = status; self.source = source; self.detail = detail
        self.recordedAt = recordedAt; self.interval = interval
    }

    var formatted: String {
        if let text { return text }
        guard let value, value.isFinite else { return "—" }
        if unit == "B" || unit == "B/s" {
            if value == 0 { return unit == "B/s" ? "0 B/s" : "0 B" }
            let amount = ByteCountFormatter.string(fromByteCount: Int64(min(max(value, 0), Double(Int64.max / 2))), countStyle: .binary)
            return amount + (unit == "B/s" ? "/s" : "")
        }
        let number = abs(value) >= 1000 || ["個", "本", "px", "台"].contains(unit) || (unit.isEmpty && value.rounded() == value)
            ? String(format: "%.0f", value) : String(format: "%.2f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

struct TableColumn: Codable, Identifiable {
    var id: String
    var title: String
    var width: Double = 130
    init(_ id: String, _ title: String, width: Double = 130) {
        self.id = id; self.title = title; self.width = width
    }
}

struct ReadingRow: Codable, Identifiable {
    var id: String
    var name: String
    var metrics: [Metric]
    var note: String = ""
    var path: String? = nil
    var bundleID: String? = nil
    func metric(_ key: String) -> Metric? { metrics.first { $0.id == key } }
}

struct PanelReading: Codable, Identifiable {
    var tab: MonitorTab
    var metrics: [Metric] = []
    var columns: [TableColumn] = []
    var rows: [ReadingRow] = []
    var notes: [String] = []
    var capturedAt: Date = Date()
    var id: String { tab.rawValue }
}

struct ProcessSample: Codable, Identifiable {
    var pid: Int32
    var parentPID: Int32
    var startTime: Date
    var name: String
    var path: String
    var owner: String
    var bundleID: String?
    var cpuPercent: Double?
    var threadCount: Int?
    var residentBytes: UInt64?
    var footprintBytes: UInt64?
    var diskReadBytes: UInt64?
    var diskWriteBytes: UInt64?
    var readBytesPerSecond: Double?
    var writeBytesPerSecond: Double?
    var growthNote: String?
    /// Actual monotonic elapsed time used for this sample’s process rates.
    var measurementInterval: Double? = nil
    var id: String { "\(pid):\(startTime.timeIntervalSince1970)" }
}

struct CoreReading {
    var panels: [PanelReading]
    var processes: [ProcessSample]
    var capturedAt: Date
}

enum CounterMath {
    static func rate(previous: UInt64?, current: UInt64, seconds: Double?) -> Double? {
        guard let previous, let seconds, seconds > 0, seconds.isFinite, current >= previous else { return nil }
        return Double(current - previous) / seconds
    }
    static func cpuPercent(previous: UInt64?, current: UInt64, seconds: Double?) -> Double? {
        rate(previous: previous, current: current, seconds: seconds).map { $0 / 1_000_000_000 * 100 }
    }
}
