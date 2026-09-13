import Foundation
import IOKit.ps

enum DeviceTestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}

func runDeviceTests() throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw DeviceTestFailure.failed(message) }
    }

    let sampler = DeviceSampler()
    var inventoryReads = 0
    let cachedSampler = DeviceSampler(registryReader: { name, _ in
        if name == "IOUSBHostDevice" {
            inventoryReads += 1
            return .success([.init(id: 1, properties: ["USB Product Name": "Cache fixture"])])
        }
        return .success([])
    }, powerSourceReader: { .success([]) })
    let firstInventory = cachedSampler.sample()
    Thread.sleep(forTimeInterval: 0.02)
    let secondInventory = cachedSampler.sample()
    try expect(inventoryReads == 1, "TTL must reuse the inventory")
    for tab in [MonitorTab.devices, .hardware] {
        let first = firstInventory.first { $0.tab == tab }!
        let second = secondInventory.first { $0.tab == tab }!
        try expect(second.capturedAt == first.capturedAt && second.metrics[0].recordedAt == first.metrics[0].recordedAt,
                   "cached inventory must preserve its actual acquisition date")
    }
    var wallTime = Date(timeIntervalSince1970: 1_800_000_000)
    let initialWall = wallTime
    let startInstant = ContinuousClock().now
    var instant = startInstant
    var clockedReads = 0, failInventory = false
    let clocked = DeviceSampler(registryReader: { name, _ in
        if name == "IOUSBHostDevice" { clockedReads += 1 }
        if failInventory { return .failure("fixture denied") }
        if name == "IOUSBHostDevice" {
            return .success([.init(id: 2, properties: ["USB Product Name": "Clock fixture"])])
        }
        return .success([])
    }, powerSourceReader: { .success([]) }, wallClock: { wallTime }, continuousClock: { instant })
    func checkClockedInventory(date: Date, reads: Int) throws {
        for panel in clocked.sample() where [.devices, .hardware].contains(panel.tab) {
            try expect(panel.capturedAt == date && panel.metrics.allSatisfy { $0.recordedAt == date },
                       "inventory acquisition date must survive TTL reuse and clock corrections")
            try expect(panel.rows.allSatisfy { $0.metrics.allSatisfy { $0.recordedAt == date } },
                       "inventory row and panel dates must agree")
        }
        try expect(clockedReads == reads, "inventory expiration must depend only on the continuous clock")
    }
    try checkClockedInventory(date: initialWall, reads: 1)
    wallTime = initialWall.addingTimeInterval(3600); instant = startInstant.advanced(by: .seconds(29))
    try checkClockedInventory(date: initialWall, reads: 1)
    wallTime = initialWall.addingTimeInterval(-3600)
    try checkClockedInventory(date: initialWall, reads: 1)
    instant = startInstant.advanced(by: .seconds(30))
    try checkClockedInventory(date: wallTime, reads: 2)
    failInventory = true; instant = startInstant.advanced(by: .seconds(60))
    let failureDate = wallTime
    try checkClockedInventory(date: failureDate, reads: 3)
    wallTime = wallTime.addingTimeInterval(10); instant = startInstant.advanced(by: .seconds(61))
    try checkClockedInventory(date: failureDate, reads: 3)
    let failurePanel = clocked.sample().first { $0.tab == .devices }!
    try expect(failurePanel.metrics[0].status == .unavailable, "cached failure must keep its status and acquisition date")
    let panels = sampler.sample()
    let expected: Set<MonitorTab> = [.thermal, .battery, .display, .devices, .hardware]
    try expect(Set(panels.map(\.tab)) == expected, "DeviceSampler must return exactly the five owned panels")
    try expect(panels.allSatisfy { !$0.metrics.contains { $0.value?.isFinite == false } }, "metrics must not contain non-finite values")
    try expect(panels.allSatisfy { panel in panel.metrics.allSatisfy { !$0.source.isEmpty && $0.recordedAt <= Date() } }, "top-level metrics need source and timestamps")

    let thermal = try panels.first { $0.tab == .thermal }.unwrap("thermal panel missing")
    try expect(thermal.metrics.first { $0.id == "thermal_state" }?.text?.isEmpty == false, "thermal state must be reported")
    if thermal.metrics.first(where: { $0.id == "cpu_temperature" })?.status == .unsupported {
        try expect(thermal.metrics.first { $0.id == "cpu_temperature" }?.value == nil, "unsupported CPU temperature must not be invented")
    }

    try expect(DeviceSampler.decodeFixed16_16(65_536 * 42.5) == 42.5, "16.16 fixed-point decoding failed")
    try expect(DeviceSampler.decodeFixed16_16(-1) == nil, "negative unsigned fixed-point input must be rejected")
    try expect(DeviceSampler.signedHardwareInteger(NSNumber(value: UInt32(bitPattern: -1_200))) == -1_200,
               "32-bit two's-complement battery current decoding failed")
    try expect(DeviceSampler.signedHardwareInteger(NSNumber(value: UInt64(bitPattern: -2_400))) == -2_400,
               "64-bit two's-complement battery current decoding failed")
    try expect(DeviceSampler.edidSummary(Data(repeating: 0, count: 128)) == nil, "invalid EDID header must be rejected")
    var validEDID = [UInt8](repeating: 0, count: 128)
    validEDID[0...7] = [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]
    validEDID[18] = 1
    validEDID[19] = 4
    let edidPartialSum = validEDID.prefix(127).reduce(0) { partial, byte in
        (partial + Int(byte)) & 0xff
    }
    validEDID[127] = UInt8((256 - edidPartialSum) & 0xff)
    try expect(DeviceSampler.edidSummary(Data(validEDID)) == "EDID 1.4 / checksum OK", "valid EDID metadata parsing failed")

    let emptyRegistry: DeviceSampler.RegistryReader = { _, _ in .success([]) }
    let duplicateAttributeRows = DeviceSampler.externalDeviceRows(at: Date()) { className, _ in
        guard className == "IOThunderboltDevice" else { return .success([]) }
        return .success([
            DeviceSampler.RegistryEntry(id: 41, properties: [:]),
            DeviceSampler.RegistryEntry(id: 42, properties: [:])
        ])
    }
    try expect(duplicateAttributeRows.status == .measured, "complete fixture inventory must be measured")
    try expect(duplicateAttributeRows.value?.map(\.id) == ["ioregistry-41", "ioregistry-42"],
               "entries with all display attributes missing must remain distinct by registry entry ID")

    let partialRows = DeviceSampler.externalDeviceRows(at: Date()) { className, _ in
        if className == "IOUSBHostDevice" {
            return .partial([DeviceSampler.RegistryEntry(id: 90, properties: ["USB Product Name": "Fixture USB"])],
                            "fixture property failure")
        }
        return .success([])
    }
    try expect(partialRows.status == .partial && partialRows.value?.count == 1,
               "partial registry acquisition must preserve usable device rows")
    let partialSampler = DeviceSampler(registryReader: { className, _ in
        if className == "IOUSBHostDevice" {
            return .partial([DeviceSampler.RegistryEntry(id: 90, properties: [:])], "fixture property failure")
        }
        return .success([])
    }, powerSourceReader: { .success([]) })
    let partialPanel = try partialSampler.sample().first { $0.tab == .devices }.unwrap("partial devices panel missing")
    try expect(partialPanel.metric("device_inventory_status")?.status == .partial && partialPanel.rows.count == 1,
               "partial device acquisition must be visible while preserving its usable rows")

    let ups: [String: Any] = [kIOPSTypeKey: kIOPSUPSType, kIOPSNameKey: "Fixture UPS",
                              "Current Capacity": 99, "Max Capacity": 100]
    let internalBattery: [String: Any] = [kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSNameKey: "Internal",
                                          "Current Capacity": 40, "Max Capacity": 80]
    try expect(DeviceSampler.internalBattery(from: [ups]) == nil, "UPS-only power sources must not be selected as an internal battery")
    try expect(DeviceSampler.internalBattery(from: [ups, internalBattery])?["Current Capacity"] as? Int == 40,
               "internal battery selection must ignore an earlier named UPS")

    let orderedPowerSampler = DeviceSampler(registryReader: emptyRegistry,
                                            powerSourceReader: { .success([ups, internalBattery]) })
    let orderedBatteryPanel = try orderedPowerSampler.sample().first { $0.tab == .battery }.unwrap("fixture battery panel missing")
    try expect(orderedBatteryPanel.metric("charge_percent")?.value == 50,
               "battery panel must use InternalBattery even when UPS is first")

    let upsOnlySampler = DeviceSampler(registryReader: emptyRegistry,
                                       powerSourceReader: { .success([ups]) })
    let upsOnlyBattery = try upsOnlySampler.sample().first { $0.tab == .battery }.unwrap("UPS-only battery panel missing")
    try expect(upsOnlyBattery.metric("power_source_status")?.status == .measured,
               "successfully enumerating a UPS-only list must remain a successful acquisition")
    try expect(upsOnlyBattery.metric("charge_percent")?.status == .unsupported,
               "UPS-only systems must report internal battery absence instead of UPS charge")

    let absentSampler = DeviceSampler(registryReader: emptyRegistry,
                                      powerSourceReader: { .success([]) })
    let absentPanels = absentSampler.sample()
    let absentDevices = try absentPanels.first { $0.tab == .devices }.unwrap("absent devices panel missing")
    try expect(absentDevices.metric("device_inventory_status")?.status == .measured && absentDevices.rows.isEmpty,
               "a successful empty registry snapshot must be distinguishable from failure")
    let absentBattery = try absentPanels.first { $0.tab == .battery }.unwrap("absent battery panel missing")
    try expect(absentBattery.metric("power_source_status")?.status == .measured,
               "a successful empty power-source list must be recorded as measured")
    try expect(absentBattery.metric("charge_percent")?.status == .unsupported,
               "confirmed internal battery absence may be reported as unsupported")

    var failedUSBReads = 0
    let failedSampler = DeviceSampler(registryReader: { className, _ in
        if className == "IOUSBHostDevice" { failedUSBReads += 1 }
        return .failure("fixture API failure")
    }, powerSourceReader: { .failure("fixture power API failure") })
    let failedPanels = failedSampler.sample()
    let failedDevices = try failedPanels.first { $0.tab == .devices }.unwrap("failed devices panel missing")
    try expect(failedDevices.metric("device_inventory_status")?.status == .unavailable && failedDevices.rows.isEmpty,
               "registry API failure must be visible and must not masquerade as an empty snapshot")
    let failedBattery = try failedPanels.first { $0.tab == .battery }.unwrap("failed battery panel missing")
    try expect(failedBattery.metric("power_source_status")?.status == .unavailable &&
               failedBattery.metric("charge_percent")?.status == .unavailable,
               "power-source API failure must not claim that an internal battery is absent")
    let failedThermal = try failedPanels.first { $0.tab == .thermal }.unwrap("failed thermal panel missing")
    try expect(failedThermal.metric("fan_registry_status")?.status == .unavailable &&
               failedThermal.metric("temperature_registry_status")?.status == .unavailable &&
               failedThermal.metric("fan_rpm")?.status == .unavailable &&
               failedThermal.metric("cpu_temperature")?.status == .unavailable,
               "thermal registry failures must not be reported as unsupported sensors")
    let failedHardware = try failedPanels.first { $0.tab == .hardware }.unwrap("failed hardware panel missing")
    try expect(failedHardware.metric("hardware_inventory_status")?.status == .partial,
               "hardware must mark the usable sysctl inventory partial when GPU registry retrieval fails")
    _ = failedSampler.sample()
    try expect(failedUSBReads == 1, "cached inventory failures must remain cached as failures without being flattened to empty success")

    let display = try panels.first { $0.tab == .display }.unwrap("display panel missing")
    for row in display.rows {
        try expect(row.metric("frame_rate")?.status == .unsupported, "configured refresh must not be presented as measured FPS")
        try expect(row.metrics.allSatisfy { !$0.source.isEmpty }, "display row metrics need sources")
    }

    let devices = try panels.first { $0.tab == .devices }.unwrap("devices panel missing")
    for row in devices.rows {
        try expect(row.metrics.allSatisfy { !$0.id.localizedCaseInsensitiveContains("serial") }, "device inventory must not expose serial fields")
        try expect(row.metric("kind")?.text?.isEmpty == false, "device transport missing")
    }

    let hardware = try panels.first { $0.tab == .hardware }.unwrap("hardware panel missing")
    try expect(hardware.rows.contains { $0.id == "model" || $0.id == "machine" }, "live smoke: basic hardware identity unavailable")
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw DeviceTestFailure.failed(message) }
        return value
    }
}

private extension PanelReading {
    func metric(_ id: String) -> Metric? { metrics.first { $0.id == id } }
}
