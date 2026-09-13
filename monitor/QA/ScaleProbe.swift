import Foundation
import Darwin

@main struct ScaleProbe {
    static func main() {
        let count = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 100_000
        let date = Date()
        let nodes = (0..<count).map { number in
            StorageNode(id: "/fixture/\(number)", parentID: "/fixture/group\(number / 100)",
                        name: "file\(number)", path: "/fixture/\(number)", kind: .file,
                        logicalBytes: 1, allocatedBytes: 4096, aggregateComplete: true,
                        scannedAt: date, error: nil, symbolicLinkDestination: nil, tags: [])
        }
        var start = ProcessInfo.processInfo.systemUptime
        let index = StorageTreeIndex(nodes: nodes)
        let buildMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        start = ProcessInfo.processInfo.systemUptime
        var fetched = 0
        for _ in 0..<1000 { fetched += index.page(in: "/fixture/group0").count }
        let pageMS = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 1000
        let values = Dictionary(uniqueKeysWithValues: (0..<40).map { ("cpu.core\($0)", Double($0)) })
        var ledger = HistoryLedger(frames: (0..<8640).map { HistoryFrame(date: date.addingTimeInterval(Double($0-8639)*10), segment: "a", values: values) })
        start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1000 { ledger.append(panels: [], segment: "a", now: date) }
        let historyMS = (ProcessInfo.processInfo.systemUptime - start) * 1000 / 1000
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("nodes=\(count) indexBuildMs=\(buildMS) pageMeanMs=\(pageMS) historyMeanMs=\(historyMS) peakRSSBytes=\(usage.ru_maxrss) fetched=\(fetched)")
    }
}
