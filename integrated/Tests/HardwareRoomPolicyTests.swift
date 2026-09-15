import Foundation

private struct PolicyTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw PolicyTestFailure(description: message) }
}

private func metric(
    _ id: String,
    value: Double? = nil,
    text: String? = nil,
    unit: String = "",
    status: ReadingStatus = .measured
) -> Metric {
    Metric(id, id, value: value, text: text, unit: unit, status: status, source: "test")
}

private func panels(
    free: Double = 70,
    total: Double = 100,
    idle: Double = 50,
    occupied: Double = 79,
    physical: Double = 100,
    thermal: String = "正常",
    charge: Double = 75
) -> [MonitorTab: PanelReading] {
    [
        .storage: PanelReading(tab: .storage, metrics: [metric("volumeTotal", value: total), metric("volumeFree", value: free)]),
        .cpu: PanelReading(tab: .cpu, metrics: [metric("idle", value: idle, unit: "%")]),
        .memory: PanelReading(tab: .memory, metrics: [metric("physical", value: physical), metric("occupied", value: occupied)]),
        .thermal: PanelReading(tab: .thermal, metrics: [metric("thermal_state", text: thermal)]),
        .battery: PanelReading(tab: .battery, metrics: [metric("charge_percent", value: charge, unit: "%")]),
        .network: PanelReading(tab: .network, metrics: [metric("rxRate", value: 1024, unit: "B/s")]),
        .display: PanelReading(tab: .display, metrics: [metric("display_count", value: 2, unit: "台")]),
        .devices: PanelReading(tab: .devices, metrics: [metric("device_inventory_status", value: 3, unit: "件")])
    ]
}

private func deviceRow(_ id: String, _ name: String, kind: String?) -> ReadingRow {
    ReadingRow(
        id: id,
        name: name,
        metrics: kind.map { [metric("kind", text: $0)] } ?? []
    )
}

private func testBoundaries() throws {
    var state = HardwareRoomPolicy.visualState(panels: panels(), previous: RoomVisualState())
    try expect(state.bookshelf == .sparse, "storage 70% is sparse")
    try expect(state.compute == .cyan, "CPU idle 50% is cyan")
    try expect(state.desk == .normal, "memory below 80% is normal")
    try expect(state.fans == .slow, "nominal thermal pressure is slow")
    try expect(state.bedLights == 4, "battery 75% has four lights")

    state = HardwareRoomPolicy.visualState(
        panels: panels(free: 69.999, idle: 49.999, occupied: 80, thermal: "やや高い", charge: 50),
        previous: state
    )
    try expect(state.bookshelf == .normal, "storage below 70% is normal")
    try expect(state.compute == .yellow, "CPU idle below 50% is yellow")
    try expect(state.desk == .stacked, "memory 80% is stacked")
    try expect(state.fans == .fast, "non-nominal thermal pressure is fast")
    try expect(state.bedLights == 3, "battery 50% has three lights")

    state = HardwareRoomPolicy.visualState(
        panels: panels(free: 10, idle: 10, occupied: 95, charge: 25),
        previous: state
    )
    try expect(state.bookshelf == .normal, "storage 10% is normal")
    try expect(state.compute == .yellow, "CPU idle 10% is yellow")
    try expect(state.desk == .overflow, "memory 95% overflows")
    try expect(state.bedLights == 2, "battery 25% has two lights")

    state = HardwareRoomPolicy.visualState(
        panels: panels(free: 9.999, idle: 9.999, charge: 1),
        previous: state
    )
    try expect(state.bookshelf == .overflow, "storage below 10% overflows")
    try expect(state.compute == .red, "CPU idle below 10% is red")
    try expect(state.bedLights == 1, "battery 1% has one light")

    state = HardwareRoomPolicy.visualState(panels: panels(charge: 0.999), previous: state)
    try expect(state.bedLights == 0, "battery below 1% has no lights")
}

private func testInvalidAndStaleRetention() throws {
    let previous = try RoomVisualState(
        bedLights: 2,
        bookshelf: .sparse,
        desk: .stacked,
        display: .staticNoise,
        fans: .slow,
        network: .red,
        compute: .yellow
    )
    var input = panels()
    input[.storage] = PanelReading(tab: .storage, metrics: [metric("volumeTotal", value: 100), metric("volumeFree", value: 0, status: .stale)])
    input[.cpu] = PanelReading(tab: .cpu, metrics: [metric("idle", value: .nan)])
    input[.memory] = PanelReading(tab: .memory, metrics: [metric("physical", value: 0), metric("occupied", value: 0)])
    input[.thermal] = PanelReading(tab: .thermal, metrics: [metric("thermal_state", text: "重大", status: .unavailable)])
    input[.battery] = PanelReading(tab: .battery, metrics: [metric("charge_percent", value: -1)])
    let state = HardwareRoomPolicy.visualState(panels: input, previous: previous)
    try expect(state.bookshelf == .sparse, "stale storage retains previous")
    try expect(state.compute == .yellow, "non-finite CPU retains previous")
    try expect(state.desk == .stacked, "invalid memory denominator retains previous")
    try expect(state.fans == .slow, "unavailable thermal state retains previous")
    try expect(state.bedLights == 2, "out-of-range battery retains previous")
    try expect(state.network == .cyan && state.display == .normal, "live-only states reset to their supported visuals")
}

private func testWarningsAndAvatarCandidates() throws {
    let normal = RoomVisualState()
    try expect(HardwareRoomPolicy.avatarCandidates(for: normal) == AvatarPoseID.allCases, "normal state permits all nine poses")
    try expect(HardwareRoomPolicy.avatarCandidates(for: normal).count == 9, "pose manifest has nine choices")
    try expect(HardwareRoomPolicy.warnings(for: normal).isEmpty, "normal state has no warnings")

    let forced = try RoomVisualState(
        bedLights: 1,
        bookshelf: .overflow,
        desk: .overflow,
        display: .staticNoise,
        fans: .fast,
        network: .red,
        compute: .red
    )
    try expect(
        HardwareRoomPolicy.avatarCandidates(for: forced) == [.sleeping, .reading, .writing, .cpuRest, .glitch],
        "all simultaneous forced poses are candidates"
    )
    let warnings = HardwareRoomPolicy.warnings(for: forced)
    try expect(Set(warnings.keys) == Set(["bed", "bookshelf", "desk", "display", "fans", "network", "compute"]), "all warning states are represented")
    try expect(warnings["fans"] != nil && warnings["fan-1"] == nil, "fan warning uses the grouped AvatarStore key")
}

private func testMappingAndSummaries() throws {
    let expected: [String: MonitorTab] = [
        "bookshelf": .storage, "compute": .cpu, "clock": .clock,
        "desk": .memory, "chair": .memory, "fans": .thermal,
        "fan-1": .thermal, "bed": .battery, "network": .network,
        "display": .display, "external": .devices
    ]
    for (id, tab) in expected {
        try expect(HardwareRoomPolicy.tab(for: id) == tab, "\(id) maps to \(tab)")
    }
    try expect(HardwareRoomPolicy.tab(for: "avatar") == nil, "unknown component has no monitor tab")

    let input = panels()
    try expect(HardwareRoomPolicy.summary(for: "bookshelf", panels: input).value.contains("70"), "storage summary uses volumeFree")
    try expect(HardwareRoomPolicy.summary(for: "compute", panels: input).value == "50.00 %", "CPU summary uses idle")
    var deviceInput = input
    deviceInput[.devices] = PanelReading(
        tab: .devices,
        metrics: [metric("device_inventory_status", value: 2, unit: "件")],
        rows: [deviceRow("keyboard", "Magic Keyboard", kind: "USB"),
               deviceRow("dock", "Desk Dock", kind: "Thunderbolt")]
    )
    try expect(
        HardwareRoomPolicy.summary(for: "external", panels: deviceInput).value == "Magic Keyboard（USB）\nDesk Dock（Thunderbolt）",
        "device summary lists names and connection types"
    )

    deviceInput[.devices] = PanelReading(
        tab: .devices,
        metrics: [metric("device_inventory_status", value: 0, unit: "件")]
    )
    try expect(HardwareRoomPolicy.summary(for: "external", panels: deviceInput).value == "接続機器なし", "successful empty inventory is explicit")

    deviceInput[.devices] = PanelReading(
        tab: .devices,
        metrics: [metric("device_inventory_status", value: 1, unit: "件", status: .partial)],
        rows: [deviceRow("camera", "Web Camera", kind: "USB")]
    )
    let partialDevices = HardwareRoomPolicy.summary(for: "external", panels: deviceInput).value
    try expect(partialDevices.contains("Web Camera（USB）") && partialDevices.contains("一覧が不完全"), "partial inventory lists entries and discloses incompleteness")

    deviceInput[.devices] = PanelReading(
        tab: .devices,
        metrics: [metric("device_inventory_status", value: 0, unit: "件", status: .partial)]
    )
    let partialEmpty = HardwareRoomPolicy.summary(for: "external", panels: deviceInput).value
    try expect(partialEmpty.contains("接続機器なし") && partialEmpty.contains("一覧が不完全"), "partial empty inventory does not claim a complete absence")

    deviceInput[.devices] = PanelReading(
        tab: .devices,
        metrics: [metric("device_inventory_status", status: .denied)]
    )
    try expect(HardwareRoomPolicy.summary(for: "external", panels: deviceInput).value == "権限不足", "denied inventory is explicit")

    deviceInput[.devices] = PanelReading(tab: .devices)
    try expect(HardwareRoomPolicy.summary(for: "external", panels: deviceInput).value == "取得できません", "missing inventory status is explicit")

    var unavailable = input
    unavailable[.cpu] = PanelReading(tab: .cpu, metrics: [metric("idle", value: 0, unit: "%", status: .unavailable)])
    unavailable[.network] = PanelReading(tab: .network, metrics: [metric("rxRate", value: 12, unit: "B/s", status: .stale)])
    try expect(HardwareRoomPolicy.summary(for: "compute", panels: unavailable).value == "取得できません", "unavailable zero is not presented as load")
    try expect(HardwareRoomPolicy.summary(for: "network", panels: unavailable).value == "過去値（更新待ち）", "stale summary is explicit")
    try expect(HardwareRoomPolicy.summary(for: "clock", panels: unavailable).value == "取得できません", "missing panel is explicit")
}

@main
struct HardwareRoomPolicyTests {
    static func main() throws {
        try testBoundaries()
        try testInvalidAndStaleRetention()
        try testWarningsAndAvatarCandidates()
        try testMappingAndSummaries()
        print("HardwareRoomPolicyTests: OK")
    }
}
