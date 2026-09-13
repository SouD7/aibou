import Foundation
import Darwin

/// Synthetic archive lifecycle. Never reads or writes the user's saved monitor results.
@main struct ArchiveScaleProbe {
    static func main() throws {
        let count = max(1, min(500_000, CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 500_000))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-archive-scale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("storage.json"), date = Date()
        let root = StorageNode(id: "/fixture", parentID: nil, name: "fixture", path: "/fixture", kind: .directory,
                               logicalBytes: UInt64(count - 1), allocatedBytes: UInt64(count - 1) * 4096,
                               aggregateComplete: true, scannedAt: date, error: nil, symbolicLinkDestination: nil, tags: [])
        var nodes = [root]
        nodes.reserveCapacity(count)
        for number in 1..<count {
            let path = "/fixture/file\(number)"
            nodes.append(StorageNode(id: path, parentID: root.id, name: "file\(number)", path: path, kind: .file,
                                     logicalBytes: 1, allocatedBytes: 4096, aggregateComplete: true,
                                     scannedAt: date, error: nil, symbolicLinkDestination: nil, tags: []))
        }
        let snapshot = StorageScanState(rootPath: root.id, startedAt: date, updatedAt: date, completedAt: date,
                                        status: .completed, scannedCount: count, errors: [], nodes: nodes,
                                        totalLogicalBytes: root.logicalBytes, totalAllocatedBytes: root.allocatedBytes)
        var start = ProcessInfo.processInfo.systemUptime
        try MonitorStore.writeStorageSnapshot(snapshot, to: url)
        let writeMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        start = ProcessInfo.processInfo.systemUptime
        let restored = try StorageScanner.load(from: url)
        let restoreMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        start = ProcessInfo.processInfo.systemUptime
        let index = StorageTreeIndex(nodes: restored.nodes)
        let indexMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
        precondition(index.count(in: root.id) == count - 1 && restored.nodes.count == count)
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        print("nodes=\(count) archiveBytes=\(bytes) writeMs=\(writeMS) restoreMs=\(restoreMS) indexMs=\(indexMS) peakRSSBytes=\(usage.ru_maxrss) pageCount=\(index.page(in: root.id).count)")
    }
}
