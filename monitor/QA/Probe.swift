import Foundation
import Darwin

@main
struct MonitorProbe {
    static func main() throws {
        let core = CoreSampler(), devices = DeviceSampler()
        var samples: [[String: Any]] = []
        for index in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let reading = core.sample(expectedInterval: 2)
            let panels = reading.panels + devices.sample()
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let own = reading.processes.first { $0.pid == getpid() }
            let observation = ObservationSnapshot(core: reading)
            let rateIDs: Set<String> = ["cpu.percent", "disk.readBytesPerSecond", "disk.writeBytesPerSecond"]
            let rates = observation.processes.flatMap(\.metrics).filter { rateIDs.contains($0.metricID) && $0.value != nil }
            let validWindows = rates.allSatisfy { ($0.interval ?? 0) > 0 && $0.interval?.isFinite == true }
            precondition(validWindows, "a process rate lost its actual measurement interval")
            samples.append([
                "sample": index, "collectionMilliseconds": elapsed * 1000,
                "processes": reading.processes.count,
                "processRatesWithValidInterval": rates.count,
                "selfCPUPercentOneCore": own?.cpuPercent ?? -1,
                "selfFootprintBytes": own?.footprintBytes ?? 0,
                "panels": panels.map { panel -> [String: Any] in
                    ["tab": panel.tab.rawValue, "rows": panel.rows.count,
                     "metrics": panel.metrics.map { ["id": $0.id, "status": $0.status.rawValue, "hasValue": $0.value != nil || $0.text != nil] }]
                }
            ])
            if index < 4 { Thread.sleep(forTimeInterval: max(0.1, 2 - elapsed)) }
        }
        if CommandLine.arguments.contains("--network") {
            let detail = NetworkDetailCollector().sample(processes: core.sample().processes)
            samples.append(["networkDetailRows": detail.rows.count,
                            "metrics": detail.metrics.map { ["id": $0.id, "status": $0.status.rawValue] }])
        }
        let data = try JSONSerialization.data(withJSONObject: samples, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
