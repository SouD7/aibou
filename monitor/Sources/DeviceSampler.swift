import Foundation
import CoreGraphics
import IOKit
import IOKit.ps

final class DeviceSampler {
    enum Acquisition<Value> {
        case success(Value)
        case partial(Value, String)
        case failure(String)

        var value: Value? {
            switch self {
            case .success(let value), .partial(let value, _): return value
            case .failure: return nil
            }
        }
        var status: ReadingStatus {
            switch self {
            case .success: return .measured
            case .partial: return .partial
            case .failure: return .unavailable
            }
        }
        var detail: String {
            switch self {
            case .success: return ""
            case .partial(_, let detail), .failure(let detail): return detail
            }
        }
        var isComplete: Bool {
            if case .success = self { return true }
            return false
        }
    }

    struct RegistryEntry {
        var id: UInt64
        var properties: [String: Any]
    }

    typealias RegistryReader = (_ className: String, _ limit: Int) -> Acquisition<[RegistryEntry]>
    typealias PowerSourceReader = () -> Acquisition<[[String: Any]]>

    private struct Cache {
        var date: Date
        var expiresAt: ContinuousClock.Instant
        var devices: Acquisition<[ReadingRow]>
        var hardware: Acquisition<[ReadingRow]>
    }

    private let lock = NSLock()
    private var cache: Cache?
    private let inventoryTTL: Duration = .seconds(30)
    private let registryReader: RegistryReader
    private let powerSourceReader: PowerSourceReader
    private let wallClock: () -> Date
    private let continuousClock: () -> ContinuousClock.Instant

    init(registryReader: @escaping RegistryReader = DeviceSampler.liveRegistryEntries,
         powerSourceReader: @escaping PowerSourceReader = DeviceSampler.livePowerSources,
         wallClock: @escaping () -> Date = { Date() },
         continuousClock: @escaping () -> ContinuousClock.Instant = { ContinuousClock().now }) {
        self.registryReader = registryReader
        self.powerSourceReader = powerSourceReader
        self.wallClock = wallClock
        self.continuousClock = continuousClock
    }

    func sample() -> [PanelReading] {
        let now = wallClock()
        let inventory = cachedInventory(at: now)
        return [
            thermalPanel(at: now),
            batteryPanel(at: now),
            displayPanel(at: now),
            PanelReading(tab: .devices,
                         metrics: [acquisitionMetric("device_inventory_status", "外部機器一覧", inventory.devices,
                                                     count: inventory.devices.value?.count, source: "IORegistry", at: inventory.date)],
                         columns: [TableColumn("kind", "接続方式"), TableColumn("vendor", "メーカー"), TableColumn("location", "接続位置")],
                         rows: inventory.devices.value ?? [],
                         notes: ["IORegistryを30秒ごとに再列挙します。接続・切断は前回一覧との差として呼び出し側で判定できます。シリアル番号は収集しません。"],
                         capturedAt: inventory.date),
            PanelReading(tab: .hardware,
                         metrics: [acquisitionMetric("hardware_inventory_status", "ハードウェア一覧", inventory.hardware,
                                                     count: inventory.hardware.value?.count, source: "sysctl / IORegistry", at: inventory.date)],
                         columns: [TableColumn("value", "値", width: 260), TableColumn("source", "取得元", width: 170)],
                         rows: inventory.hardware.value ?? [],
                         notes: ["macOSが公開する機種情報です。非公開の部品型番は推測しません。"],
                         capturedAt: inventory.date)
        ]
    }

    private func acquisitionMetric<T>(_ id: String, _ label: String, _ result: Acquisition<T>,
                                      count: Int? = nil, source: String, at now: Date) -> Metric {
        Metric(id, label, value: count.map(Double.init), unit: count == nil ? "" : "件",
               status: result.status, source: source, detail: result.detail, recordedAt: now)
    }

    private func thermalPanel(at now: Date) -> PanelReading {
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = "正常"
        case .fair: state = "やや高い"
        case .serious: state = "高い"
        case .critical: state = "重大"
        @unknown default: state = "不明"
        }
        var metrics = [
            Metric("thermal_state", "サーマルプレッシャー", text: state,
                   source: "ProcessInfo.thermalState", detail: "OSが判定した熱状態。温度ではありません。", recordedAt: now)
        ]
        let fanResult = Self.platformFanValues(from: registryReader("IOPlatformFan", 16))
        let fanValues = fanResult.value ?? (nil, nil, nil)
        metrics.append(acquisitionMetric("fan_registry_status", "ファン情報取得", fanResult,
                                         source: "IORegistry IOPlatformFan", at: now))
        if let current = fanValues.current {
            metrics.append(Metric("fan_rpm", "ファン回転数", value: current, unit: "RPM", source: "IOPlatformFan",
                                  detail: "IOPlatformFanが公開した16.16固定小数値。主に一部Intel Macで利用できます。", recordedAt: now))
            if let minimum = fanValues.minimum {
                metrics.append(Metric("fan_min_rpm", "ファン最小回転数", value: minimum, unit: "RPM", source: "IOPlatformFan", recordedAt: now))
            }
            if let maximum = fanValues.maximum {
                metrics.append(Metric("fan_max_rpm", "ファン最大回転数", value: maximum, unit: "RPM", source: "IOPlatformFan", recordedAt: now))
            }
        } else {
            metrics.append(Metric("fan_rpm", "ファン回転数", unit: "RPM",
                                  status: fanResult.isComplete ? .unsupported : fanResult.status,
                                  source: "IOPlatformFan", detail: fanResult.isComplete ? "IOPlatformFanに利用可能な値がありません。ファン非搭載とは断定しません。" : fanResult.detail, recordedAt: now))
        }
        let temperatureResult = Self.platformTemperatures(from: registryReader("IOPlatformSensor", 128))
        let temperatures = temperatureResult.value ?? [:]
        metrics.append(acquisitionMetric("temperature_registry_status", "温度センサー情報取得", temperatureResult,
                                         count: temperatureResult.value?.count, source: "IORegistry IOPlatformSensor", at: now))
        for (id, label) in [("cpu_temperature", "CPU温度"), ("gpu_temperature", "GPU温度")] {
            if let value = temperatures[id] {
                metrics.append(Metric(id, label, value: value, unit: "°C", source: "IOPlatformSensor",
                                      detail: "IOPlatformSensorが名前付きで公開した16.16固定小数値。", recordedAt: now))
            } else {
                metrics.append(Metric(id, label, unit: "°C",
                                      status: temperatureResult.isComplete ? .unsupported : temperatureResult.status,
                                      source: "IOPlatformSensor", detail: temperatureResult.isComplete ? "対応する公開センサー値が見つかりません。" : temperatureResult.detail, recordedAt: now))
            }
        }
        return PanelReading(
            tab: .thermal,
            metrics: metrics,
            notes: ["温度やRPMをOSの熱状態から推定していません。"],
            capturedAt: now
        )
    }

    private func batteryPanel(at now: Date) -> PanelReading {
        var metrics: [Metric] = []
        let powerSources = powerSourceReader()
        let snapshot = powerSources.value.flatMap(Self.internalBattery(from:))
        metrics.append(acquisitionMetric("power_source_status", "電源情報取得", powerSources,
                                         count: powerSources.value?.count, source: "IOPowerSources", at: now))
        if let snapshot {
            if let current = snapshot.number("Current Capacity"), let maximum = snapshot.number("Max Capacity"), maximum > 0 {
                metrics.append(Metric("charge_percent", "現在の残量", value: current / maximum * 100, unit: "%",
                                      source: "IOPowerSources", detail: "Current Capacity / Max Capacity", recordedAt: now))
            }
            if let charging = snapshot.bool("Is Charging") {
                metrics.append(Metric("charging", "充電状態", text: charging ? "充電中" : "充電していない",
                                      source: "IOPowerSources", recordedAt: now))
            }
            if let connected = snapshot.bool("External Connected") {
                metrics.append(Metric("external_power", "外部電源", text: connected ? "接続" : "未接続",
                                      source: "IOPowerSources", recordedAt: now))
            }
            if let minutes = snapshot.number("Time to Empty"), minutes >= 0 {
                metrics.append(Metric("time_remaining", "推定残り時間", value: minutes, unit: "分", status: .estimated,
                                      source: "IOPowerSources", detail: "OSによる推定値", recordedAt: now))
            }
        } else {
            metrics.append(Metric("charge_percent", "現在の残量", unit: "%",
                                  status: powerSources.isComplete ? .unsupported : powerSources.status,
                                  source: "IOPowerSources", detail: powerSources.isComplete ? "内蔵バッテリーが見つかりません。デスクトップMacでは正常です。" : powerSources.detail, recordedAt: now))
        }

        let batteryRegistry = registryReader("AppleSmartBattery", 1)
        metrics.append(acquisitionMetric("battery_registry_status", "バッテリー詳細取得", batteryRegistry,
                                         count: batteryRegistry.value?.count, source: "IORegistry AppleSmartBattery", at: now))
        if let battery = batteryRegistry.value?.first?.properties {
            let maxCapacity = battery.number(forAny: ["AppleRawMaxCapacity"])
            if let maxCapacity {
                metrics.append(Metric("full_charge_capacity", "満充電容量", value: maxCapacity, unit: "mAh",
                                      source: "AppleSmartBattery/AppleRawMaxCapacity", detail: "AppleRawMaxCapacityとして公開された絶対容量。", recordedAt: now))
            } else {
                metrics.append(Metric("full_charge_capacity", "満充電容量", unit: "mAh", status: .unavailable,
                                      source: "AppleSmartBattery", detail: "絶対容量と確認できるAppleRawMaxCapacityがありません。MaxCapacityは百分率の場合があるため代用しません。", recordedAt: now))
            }
            if let voltage = battery.number(forAny: ["Voltage"]) {
                metrics.append(Metric("battery_voltage", "バッテリー電圧", value: voltage / 1000, unit: "V",
                                      source: "AppleSmartBattery", detail: "Voltage (mV) をVへ換算", recordedAt: now))
                if let currentNumber = battery.numberObject(forAny: ["InstantAmperage", "Amperage"]),
                   let signedCurrent = Self.signedHardwareInteger(currentNumber) {
                    metrics.append(Metric("battery_current", "バッテリー電流", value: signedCurrent / 1000, unit: "A",
                                          source: "AppleSmartBattery", detail: "電池側の瞬時電流。符号は充放電方向を表します。", recordedAt: now))
                    metrics.append(Metric("battery_power", "バッテリー側電力", value: voltage / 1000 * signedCurrent / 1000, unit: "W", status: .derived,
                                          source: "AppleSmartBattery", detail: "電圧×電流の算出値。ACアダプタの定格ではありません。", recordedAt: now))
                }
            }
            if let watts = battery.adapterWatts {
                metrics.append(Metric("adapter_rated_power", "電源アダプタ定格", value: watts, unit: "W",
                                      source: "AppleSmartBattery/AdapterDetails", detail: "アダプタが申告した定格値。実際の供給電力ではありません。", recordedAt: now))
            }
        }
        metrics.append(Metric("power_density", "電力供給密度", status: .unsupported, source: "公開APIなし",
                              detail: "面積の定義と公開測定値がないため算出しません。", recordedAt: now))
        metrics.append(Metric("vrm_temperature", "VRM温度", unit: "°C", status: .unsupported, source: "公開APIなし",
                              detail: "機種横断で安定した公開APIがありません。", recordedAt: now))
        return PanelReading(tab: .battery, metrics: metrics, capturedAt: now)
    }

    private func displayPanel(at now: Date) -> PanelReading {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return PanelReading(tab: .display,
                                metrics: [Metric("display_count", "接続画面数", unit: "台", status: .unavailable,
                                                 source: "CoreGraphics", detail: "画面一覧を取得できませんでした。", recordedAt: now)],
                                capturedAt: now)
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return PanelReading(tab: .display, notes: ["CoreGraphicsから画面一覧を取得できませんでした。"], capturedAt: now)
        }
        let registryDisplayResult = registryReader("IODisplayConnect", 256)
        let registryDisplays = registryDisplayResult.value?.map(\.properties) ?? []
        let rows = ids.prefix(Int(count)).map { id -> ReadingRow in
            let mode = CGDisplayCopyDisplayMode(id)
            let width = mode.map { Double($0.pixelWidth) }
            let height = mode.map { Double($0.pixelHeight) }
            let refresh = mode.flatMap { $0.refreshRate > 0 ? $0.refreshRate : nil }
            let sizeMM = CGDisplayScreenSize(id)
            let vendorID = Int(CGDisplayVendorNumber(id))
            let productID = Int(CGDisplayModelNumber(id))
            let registryDisplay = registryDisplays.first {
                Int($0.number(forAny: ["DisplayVendorID"]) ?? -1) == vendorID &&
                Int($0.number(forAny: ["DisplayProductID"]) ?? -1) == productID
            }
            let edid = registryDisplay?["IODisplayEDID"] as? Data
            let edidText = edid.flatMap(Self.edidSummary)
            var metrics = [
                Metric("resolution", "画素解像度", text: width.flatMap { w in height.map { "\(Int(w)) × \(Int($0))" } }, unit: "px",
                       status: width == nil ? .unavailable : .measured, source: "CoreGraphics", recordedAt: now),
                Metric("points", "論理解像度", text: mode.map { "\($0.width) × \($0.height)" },
                       status: mode == nil ? .unavailable : .measured, source: "CoreGraphics", detail: "macOSの論理座標（ポイント）", recordedAt: now),
                Metric("refresh_rate", "設定リフレッシュレート", value: refresh, unit: "Hz",
                       status: refresh == nil ? .unavailable : .measured, source: "CoreGraphics", detail: refresh == nil ? "可変または未申告です。実表示FPSではありません。" : "現在の表示モード", recordedAt: now),
                Metric("physical_width", "物理幅", value: sizeMM.width, unit: "mm", source: "CoreGraphics", recordedAt: now),
                Metric("vendor", "ベンダーID", text: String(format: "0x%04X", vendorID), source: "CoreGraphics", recordedAt: now),
                Metric("product", "製品ID", text: String(format: "0x%04X", productID), source: "CoreGraphics", recordedAt: now),
                Metric("edid", "EDID", text: edidText,
                       status: edidText == nil ? (registryDisplayResult.isComplete ? .unavailable : registryDisplayResult.status) : .measured,
                       source: "IORegistry IODisplayEDID",
                       detail: edidText == nil ? (registryDisplayResult.isComplete ? "EDIDが公開されていません。" : registryDisplayResult.detail) : "ヘッダ・版・先頭ブロックのチェックサムだけを検証し、生データやシリアル番号は保持しません。", recordedAt: now),
                Metric("frame_rate", "実表示フレームレート", unit: "fps", status: .unsupported, source: "公開APIなし", detail: "設定Hzを実測FPSとして代用しません。", recordedAt: now)
            ]
            if CGDisplayIsBuiltin(id) != 0 {
                metrics.append(Metric("connection", "接続", text: "内蔵", source: "CoreGraphics", recordedAt: now))
            }
            return ReadingRow(id: "display-\(id)", name: CGDisplayIsBuiltin(id) != 0 ? "内蔵ディスプレイ" : "外部ディスプレイ", metrics: metrics)
        }
        return PanelReading(tab: .display,
                            metrics: [Metric("display_count", "接続画面数", value: Double(count), unit: "台", source: "CoreGraphics", recordedAt: now),
                                      acquisitionMetric("display_registry_status", "画面詳細取得", registryDisplayResult,
                                                        count: registryDisplays.count, source: "IORegistry IODisplayConnect", at: now)],
                            columns: [TableColumn("resolution", "画素解像度"), TableColumn("refresh_rate", "設定Hz"), TableColumn("connection", "接続")],
                            rows: rows, notes: ["画素解像度と論理解像度を分離しています。"], capturedAt: now)
    }

    private func cachedInventory(at now: Date) -> Cache {
        lock.lock()
        defer { lock.unlock() }
        let instant = continuousClock()
        if let cache, instant < cache.expiresAt {
            return cache
        }
        let result = Cache(date: now, expiresAt: instant.advanced(by: inventoryTTL),
                           devices: Self.externalDeviceRows(at: now, registryReader: registryReader),
                           hardware: Self.hardwareRows(at: now, registryReader: registryReader))
        cache = result
        return result
    }

    static func externalDeviceRows(at now: Date, registryReader: RegistryReader) -> Acquisition<[ReadingRow]> {
        let classes = [("IOUSBHostDevice", "USB"), ("IOThunderboltDevice", "Thunderbolt")]
        var rows: [ReadingRow] = []
        var seenEntryIDs = Set<UInt64>()
        var issues: [String] = []
        var failedClasses = 0
        for (className, transport) in classes {
            let acquisition = registryReader(className, 256)
            if case .failure(let detail) = acquisition {
                failedClasses += 1
                issues.append("\(transport): \(detail)")
            } else if case .partial(_, let detail) = acquisition {
                issues.append("\(transport): \(detail)")
            }
            for entry in acquisition.value ?? [] {
                guard seenEntryIDs.insert(entry.id).inserted else { continue }
                let properties = entry.properties
                let name = properties.string(forAny: ["USB Product Name", "Product Name", "IOName", "name"]) ?? className
                let vendor = properties.string(forAny: ["USB Vendor Name", "Manufacturer", "Vendor Name"]) ?? "不明"
                let location = properties.number(forAny: ["locationID"]).map { String(format: "0x%08X", UInt32($0)) } ?? "—"
                rows.append(ReadingRow(id: "ioregistry-\(entry.id)", name: name, metrics: [
                    Metric("kind", "接続方式", text: transport, source: "IORegistry", recordedAt: now),
                    Metric("vendor", "メーカー", text: vendor, source: "IORegistry", recordedAt: now),
                    Metric("location", "接続位置", text: location, source: "IORegistry", detail: "IORegistry locationID。シリアル番号ではありません。", recordedAt: now)
                ]))
            }
        }
        rows.sort {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        if failedClasses == classes.count { return .failure(issues.joined(separator: "; ")) }
        if !issues.isEmpty { return .partial(rows, issues.joined(separator: "; ")) }
        return .success(rows)
    }

    private static func hardwareRows(at now: Date, registryReader: RegistryReader) -> Acquisition<[ReadingRow]> {
        var facts: [(String, String, String, String)] = []
        func add(_ id: String, _ name: String, _ value: String?, _ source: String) {
            guard let value, !value.isEmpty else { return }
            facts.append((id, name, value, source))
        }
        add("model", "Macモデル識別子", sysctlString("hw.model"), "sysctl hw.model")
        add("machine", "CPUアーキテクチャ", sysctlString("hw.machine"), "sysctl hw.machine")
        add("cpu_brand", "CPU", sysctlString("machdep.cpu.brand_string") ?? sysctlString("hw.optional.arm64").map { $0 == "1" ? "Apple Silicon" : nil } ?? nil, "sysctl")
        if let bytes = sysctlUInt64("hw.memsize") {
            add("memory", "物理メモリ", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary), "sysctl hw.memsize")
        }
        add("logical_cpu", "論理CPU数", String(ProcessInfo.processInfo.processorCount), "ProcessInfo")
        add("active_cpu", "稼働可能CPU数", String(ProcessInfo.processInfo.activeProcessorCount), "ProcessInfo")
        add("os", "macOS", ProcessInfo.processInfo.operatingSystemVersionString, "ProcessInfo")
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let size = (attrs[.systemSize] as? NSNumber)?.int64Value {
            add("disk", "起動ボリューム容量", ByteCountFormatter.string(fromByteCount: size, countStyle: .binary), "FileManager")
        }
        let gpuResult = registryReader("IOAccelerator", 1)
        if let gpu = gpuResult.value?.first?.properties,
           let model = gpu.string(forAny: ["model", "IOName", "CFBundleIdentifier"]) {
            add("gpu", "GPU/アクセラレータ", model, "IORegistry IOAccelerator")
        }
        let rows = facts.map { id, name, value, source in
            ReadingRow(id: id, name: name, metrics: [
                Metric("value", "値", text: value, source: source, recordedAt: now),
                Metric("source", "取得元", text: source, source: source, recordedAt: now)
            ])
        }
        switch gpuResult {
        case .success: return .success(rows)
        case .partial(_, let detail), .failure(let detail): return .partial(rows, "IOAccelerator: \(detail)")
        }
    }

    static func internalBattery(from sources: [[String: Any]]) -> [String: Any]? {
        sources.first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }
    }

    static func livePowerSources() -> Acquisition<[[String: Any]]> {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return .failure("IOPSCopyPowerSourcesInfoが失敗しました。")
        }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .failure("IOPSCopyPowerSourcesListが失敗しました。")
        }
        var result: [[String: Any]] = []
        var omitted = 0
        for source in list {
            guard let raw = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                omitted += 1
                continue
            }
            result.append(raw)
        }
        return omitted == 0 ? .success(result) : .partial(result, "\(omitted)件の電源詳細を取得できませんでした。")
    }

    static func liveRegistryEntries(matching className: String, limit: Int = 256) -> Acquisition<[RegistryEntry]> {
        guard let matching = IOServiceMatching(className) else {
            return .failure("\(className)のmatching dictionaryを作成できませんでした。")
        }
        var iterator: io_iterator_t = 0
        let matchingResult = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard matchingResult == KERN_SUCCESS else {
            return .failure("\(className)の列挙に失敗しました (kern_return_t=\(matchingResult))。")
        }
        defer { IOObjectRelease(iterator) }
        var result: [RegistryEntry] = []
        var omitted = 0
        while result.count < limit {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var entryID: UInt64 = 0
            var unmanaged: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS,
               IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] {
                result.append(RegistryEntry(id: entryID, properties: dictionary))
            } else {
                omitted += 1
            }
        }
        if result.count == limit {
            let extra = IOIteratorNext(iterator)
            if extra != 0 {
                IOObjectRelease(extra)
                return .partial(result, "列挙上限\(limit)件に達しました。")
            }
        }
        return omitted == 0 ? .success(result) : .partial(result, "\(omitted)件のentry IDまたはpropertiesを取得できませんでした。")
    }

    static func decodeFixed16_16(_ raw: Double) -> Double? {
        guard raw.isFinite, raw >= 0, raw <= Double(UInt32.max) else { return nil }
        return raw / 65_536
    }

    static func signedHardwareInteger(_ number: NSNumber) -> Double? {
        let encoding = String(cString: number.objCType)
        let unsigned = number.uint64Value
        // IORegistry may bridge an unsigned 32-bit CFNumber as a signed 64-bit NSNumber.
        // Values this large are not plausible milliamps, so preserve the producer's
        // common two's-complement representation before consulting objCType.
        if unsigned > UInt64(Int32.max), unsigned <= UInt64(UInt32.max) {
            return Double(Int32(bitPattern: UInt32(unsigned)))
        }
        if unsigned > UInt64(Int64.max) {
            return Double(Int64(bitPattern: unsigned))
        }
        switch encoding {
        case "I": return Double(Int32(bitPattern: number.uint32Value))
        case "Q": return Double(Int64(bitPattern: number.uint64Value))
        default:
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }
    }

    static func edidSummary(_ data: Data) -> String? {
        guard data.count >= 128 else { return nil }
        let bytes = [UInt8](data.prefix(128))
        guard Array(bytes.prefix(8)) == [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00] else { return nil }
        let checksumOK = bytes.reduce(0) { (Int($0) + Int($1)) & 0xff } == 0
        return "EDID \(bytes[18]).\(bytes[19]) / checksum \(checksumOK ? "OK" : "不一致")"
    }

    private static func platformFanValues(from acquisition: Acquisition<[RegistryEntry]>) -> Acquisition<(current: Double?, minimum: Double?, maximum: Double?)> {
        let fans = acquisition.value?.map(\.properties) ?? []
        func firstPlausible(_ keys: [String]) -> Double? {
            for fan in fans {
                if let raw = fan.number(forAny: keys), let value = decodeFixed16_16(raw), value >= 100, value <= 20_000 { return value }
            }
            return nil
        }
        let values = (firstPlausible(["current-value", "target-value"]),
                      firstPlausible(["min-value"]), firstPlausible(["max-value"]))
        switch acquisition {
        case .success: return .success(values)
        case .partial(_, let detail): return .partial(values, detail)
        case .failure(let detail): return .failure(detail)
        }
    }

    private static func platformTemperatures(from acquisition: Acquisition<[RegistryEntry]>) -> Acquisition<[String: Double]> {
        var result: [String: Double] = [:]
        for sensor in acquisition.value?.map(\.properties) ?? [] {
            let identity = [sensor.string(forAny: ["sensor-id", "location", "type", "name"]),
                            sensor.string(forAny: ["zone"])].compactMap { $0 }.joined(separator: " ").lowercased()
            guard identity.contains("temp"), let raw = sensor.number(forAny: ["current-value"]),
                  let value = decodeFixed16_16(raw), (-20...150).contains(value) else { continue }
            if identity.contains("cpu") { result["cpu_temperature"] = value }
            if identity.contains("gpu") { result["gpu_temperature"] = value }
        }
        switch acquisition {
        case .success: return .success(result)
        case .partial(_, let detail): return .partial(result, detail)
        case .failure(let detail): return .failure(detail)
        }
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return nil }
            return String(cString: base)
        }
    }

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

private extension Dictionary where Key == String, Value == Any {
    func number(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func bool(_ key: String) -> Bool? { (self[key] as? NSNumber)?.boolValue }
    func number(forAny keys: [String]) -> Double? { keys.lazy.compactMap { number($0) }.first }
    func numberObject(forAny keys: [String]) -> NSNumber? { keys.lazy.compactMap { self[$0] as? NSNumber }.first }
    func string(forAny keys: [String]) -> String? {
        for key in keys {
            if let value = self[key] as? String { return value }
            if let data = self[key] as? Data, let value = String(data: data, encoding: .utf8) {
                return value.trimmingCharacters(in: .controlCharacters)
            }
        }
        return nil
    }
    var adapterWatts: Double? {
        guard let details = self["AdapterDetails"] as? [String: Any] else { return nil }
        return details.number(forAny: ["Watts"])
    }
}
