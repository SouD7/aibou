import Foundation
struct LauncherApplication { let url: URL }
struct ProcessSample {
    var pid: Int32
    var parentPID: Int32
    var startTime: Date
    var path: String
    var id: String { "\(pid):\(startTime.timeIntervalSince1970)" }
}
struct ApplicationProcessGroup {
    var processes: [ProcessSample]
    var inheritedIDs: Set<String>

    /// Exact installation path is the anchor; another app with the same bundle ID is not included.
    static func make(app: LauncherApplication, processes: [ProcessSample]) -> ApplicationProcessGroup {
        let root = app.url.resolvingSymlinksInPath().standardizedFileURL.path
        var normalized: [String: String] = [:]
        func path(_ process: ProcessSample) -> String {
            if process.path.isEmpty { return "" }
            if let cached = normalized[process.path] { return cached }
            let value = URL(fileURLWithPath: process.path).resolvingSymlinksInPath().standardizedFileURL.path
            normalized[process.path] = value
            return value
        }
        var included = Set(processes.filter { path($0).hasPrefix(root + "/") }.map(\.id))
        let direct = included
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        // Iterative traversal also handles helper processes reparented to launchd via direct paths.
        var changed = true
        while changed {
            changed = false
            for process in processes where !included.contains(process.id) {
                guard let parent = byPID[process.parentPID], included.contains(parent.id),
                      process.startTime >= parent.startTime else { continue }
                // Launching a separate GUI application does not make it part of the parent's budget.
                let otherPath = path(process)
                if otherPath.split(separator: "/").contains(where: { $0.lowercased().hasSuffix(".app") }) { continue }
                included.insert(process.id); changed = true
            }
        }
        return ApplicationProcessGroup(processes: processes.filter { included.contains($0.id) },
                                       inheritedIDs: included.subtracting(direct))
    }

}

let app = LauncherApplication(url: URL(fileURLWithPath: "/Applications/Fixture.app"))
for count in [500, 1000, 2000] {
    for deep in [false, true] {
        var samples: [ProcessSample] = []
        for i in 0..<count {
            var parent: Int32 = 1
            if i > 0 && deep { parent = Int32(i + 99) }
            else if i > 0 && i < 5 { parent = 100 }
            let path = i == 0 ? "/Applications/Fixture.app/Contents/MacOS/Fixture" : "/usr/bin/aibou-fixture-\(i)"
            samples.append(ProcessSample(pid: Int32(i + 100), parentPID: parent,
                startTime: Date(timeIntervalSince1970: Double(i + 1000)), path: path))
        }
        if deep { samples.reverse() }
        let start = ProcessInfo.processInfo.systemUptime
        let result = ApplicationProcessGroup.make(app: app, processes: samples)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("\(deep ? "deep-reversed" : "shallow") count=\(count) included=\(result.processes.count) seconds=\(elapsed)")
    }
}
