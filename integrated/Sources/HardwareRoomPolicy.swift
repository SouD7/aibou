import Foundation

enum HardwareRoomPolicy {
    static func visualState(
        panels: [MonitorTab: PanelReading],
        previous: RoomVisualState
    ) -> RoomVisualState {
        var next = previous

        if let storage = panels[.storage],
           let total = usableNumber("volumeTotal", in: storage), total > 0,
           let free = usableNumber("volumeFree", in: storage),
           free >= 0, free <= total {
            let ratio = free / total
            next = next.applying(
                optionID: ratio >= 0.70 ? "sparse" : (ratio >= 0.10 ? "normal" : "overflow"),
                for: "bookshelf"
            ) ?? next
        }

        if let cpu = panels[.cpu],
           let idle = usableNumber("idle", in: cpu), (0...100).contains(idle) {
            next = next.applying(
                optionID: idle >= 50 ? "cyan" : (idle >= 10 ? "yellow" : "red"),
                for: "compute"
            ) ?? next
        }

        if let memory = panels[.memory],
           let physical = usableNumber("physical", in: memory), physical > 0,
           let occupied = usableNumber("occupied", in: memory),
           occupied >= 0, occupied <= physical {
            let ratio = occupied / physical
            next = next.applying(
                optionID: ratio >= 0.99 ? "overflow" : (ratio >= 0.80 ? "stacked" : "normal"),
                for: "desk"
            ) ?? next
        }

        if let thermal = panels[.thermal],
           let pressure = usableText("thermal_state", in: thermal) {
            next = next.applying(optionID: pressure == "正常" ? "slow" : "fast", for: "fans") ?? next
        }

        if let battery = panels[.battery],
           let charge = usableNumber("charge_percent", in: battery), (0...100).contains(charge) {
            let lights: String
            if charge >= 75 { lights = "4" }
            else if charge >= 50 { lights = "3" }
            else if charge >= 25 { lights = "2" }
            else if charge >= 1 { lights = "1" }
            else { lights = "0" }
            next = next.applying(optionID: lights, for: "bed") ?? next
        }

        // Live monitor readings do not currently define degraded visual states for
        // these components. Demo mode can still apply red/staticNoise directly.
        next = next.applying(optionID: "cyan", for: "network") ?? next
        next = next.applying(optionID: "normal", for: "display") ?? next
        return next
    }

    static func avatarCandidates(for state: RoomVisualState) -> [AvatarPoseID] {
        var result: [AvatarPoseID] = []
        if state.bedLights <= 1 { result.append(.sleeping) }
        if state.bookshelf == .overflow { result.append(.reading) }
        if state.desk == .overflow { result.append(.writing) }
        if state.compute == .red { result.append(.cpuRest) }
        if state.network == .red { result.append(.glitch) }
        return result.isEmpty ? AvatarPoseID.allCases : result
    }

    static func warnings(for state: RoomVisualState) -> [String: ComponentWarning] {
        var result: [String: ComponentWarning] = [:]
        if state.bookshelf == .overflow {
            result["bookshelf"] = ComponentWarning(message: "起動データ領域の空きが10%未満です。")
        }
        if state.compute == .red {
            result["compute"] = ComponentWarning(message: "CPUアイドル率が10%未満です。")
        }
        if state.desk == .overflow {
            result["desk"] = ComponentWarning(message: "RAM占有量が物理メモリの99%以上です。")
        }
        if state.fans == .fast {
            result["fans"] = ComponentWarning(message: "サーマルプレッシャーが正常ではありません。")
        }
        if state.bedLights <= 1 {
            result["bed"] = ComponentWarning(message: "バッテリー残量が25%未満です。")
        }
        if state.network == .red {
            result["network"] = ComponentWarning(message: "ネットワークに警告があります。")
        }
        if state.display == .staticNoise {
            result["display"] = ComponentWarning(message: "ディスプレイに警告があります。")
        }
        return result
    }

    static func tab(for componentID: String) -> MonitorTab? {
        switch componentID {
        case "bookshelf": return .storage
        case "compute": return .cpu
        case "clock": return .clock
        case "desk", "chair": return .memory
        case "fan-1", "fan-2", "fans": return .thermal
        case "bed": return .battery
        case "network": return .network
        case "display": return .display
        case "external": return .devices
        default: return nil
        }
    }

    static func summary(
        for componentID: String,
        panels: [MonitorTab: PanelReading]
    ) -> (title: String, value: String) {
        if componentID == "external" {
            return ("外部機器一覧", externalDeviceSummary(in: panels[.devices]))
        }

        let specification: (tab: MonitorTab, metricID: String, title: String)?
        switch componentID {
        case "bookshelf": specification = (.storage, "volumeFree", "起動データ領域の空き")
        case "compute": specification = (.cpu, "idle", "アイドル")
        case "clock": specification = (.clock, "uptimeInterval", "稼働中の計測間隔")
        case "desk", "chair": specification = (.memory, "occupied", "RAM占有量")
        case "fan-1", "fan-2", "fans": specification = (.thermal, "thermal_state", "サーマルプレッシャー")
        case "bed": specification = (.battery, "charge_percent", "現在の残量")
        case "network": specification = (.network, "rxRate", "物理IF受信速度")
        case "display": specification = (.display, "display_count", "接続画面数")
        default: specification = nil
        }

        guard let specification else { return ("全体の負荷", "取得できません") }
        guard let panel = panels[specification.tab],
              let metric = panel.metrics.first(where: { $0.id == specification.metricID }) else {
            return (specification.title, "取得できません")
        }
        return (specification.title, summaryValue(for: metric))
    }

    private static func externalDeviceSummary(in panel: PanelReading?) -> String {
        guard let panel,
              let status = panel.metrics.first(where: { $0.id == "device_inventory_status" }) else {
            return "取得できません"
        }
        guard usableStatuses.contains(status.status) else { return summaryValue(for: status) }
        guard let count = status.value, count.isFinite, count >= 0, count.rounded() == count else {
            return "取得できません"
        }

        let entries = panel.rows.compactMap { row -> String? in
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let kind = row.metric("kind")
                .flatMap { usableStatuses.contains($0.status) ? $0.text : nil }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return kind.flatMap { $0.isEmpty ? nil : "\(name)（\($0)）" } ?? name
        }
        let listing = entries.isEmpty ? "接続機器なし" : entries.joined(separator: "\n")
        return status.status == .partial ? "\(listing)\n一部取得のため一覧が不完全です" : listing
    }

    private static let usableStatuses: Set<ReadingStatus> = [.measured, .derived, .estimated, .partial]

    private static func usableNumber(_ id: String, in panel: PanelReading) -> Double? {
        guard let metric = panel.metrics.first(where: { $0.id == id }),
              usableStatuses.contains(metric.status),
              let value = metric.value, value.isFinite else { return nil }
        return value
    }

    private static func usableText(_ id: String, in panel: PanelReading) -> String? {
        guard let metric = panel.metrics.first(where: { $0.id == id }),
              usableStatuses.contains(metric.status),
              let text = metric.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    private static func summaryValue(for metric: Metric) -> String {
        if !usableStatuses.contains(metric.status) {
            switch metric.status {
            case .waiting: return "計測待ち"
            case .denied: return "権限不足"
            case .unsupported: return "非対応"
            case .stale: return "過去値（更新待ち）"
            case .unavailable: return "取得できません"
            case .measured, .derived, .estimated, .partial: return "取得できません"
            }
        }
        if let text = metric.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        guard let value = metric.value, value.isFinite else { return "取得できません" }
        return metric.formatted
    }
}
