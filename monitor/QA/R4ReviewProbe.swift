import Foundation

@main
struct R4ReviewProbe {
    static func main() throws {
        var reads = 0
        let sampler = DeviceSampler(registryReader: { name, _ in
            if name == "IOUSBHostDevice" {
                reads += 1
                return .success([.init(id: 1, properties: ["USB Product Name": "Fixture"])])
            }
            return .success([])
        }, powerSourceReader: { .success([]) })
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 0.02)
        let panel = sampler.sample().first { $0.tab == .devices }!
        let rowTime = panel.rows[0].metrics[0].recordedAt
        let statusTime = panel.metrics.first { $0.id == "device_inventory_status" }!.recordedAt
        print("cache_probe reads=\(reads) cachedRowOlderThanStatus=\(rowTime < statusTime) cachedRowOlderThanPanel=\(rowTime < panel.capturedAt)")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIBOU-R4-Probe-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let node = StorageNode(id: "/fixture", parentID: nil, name: "fixture", path: "/fixture", kind: .directory,
                               logicalBytes: 12, allocatedBytes: 16, aggregateComplete: true, scannedAt: now,
                               error: nil, symbolicLinkDestination: nil, tags: [])
        let state = StorageScanState(rootPath: node.id, startedAt: now, updatedAt: now, completedAt: nil,
                                     status: .completed, scannedCount: 999_999, errors: [], nodes: [node],
                                     totalLogicalBytes: 999_999, totalAllocatedBytes: 16)
        struct Archive: Encodable { var schemaVersion = 1; var state: StorageScanState }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let url = directory.appendingPathComponent("storage.json")
        try encoder.encode(Archive(state: state)).write(to: url)
        let restored = try StorageScanner.load(from: url)
        print("archive_probe status=\(restored.status.rawValue) completedAtMissing=\(restored.completedAt == nil) count=\(restored.scannedCount) nodes=\(restored.nodes.count) total=\(restored.totalLogicalBytes) rootBytes=\(restored.nodes[0].logicalBytes)")
    }
}
