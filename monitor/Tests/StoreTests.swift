import Foundation

private func storeExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw NSError(domain: "AIBOU.StoreTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@MainActor
func runStoreTests() async throws {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("AIBOU-StoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let root = temporary.appendingPathComponent("root", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let normalized = MonitorStore.normalizedScanRoot(root.appendingPathComponent("..", isDirectory: true)
        .appendingPathComponent("root", isDirectory: true))
    try storeExpect(normalized == root.path, "scan roots must be normalized before generation checks")

    let now = Date()
    let rootNode = StorageNode(id: root.path, parentID: nil, name: root.lastPathComponent,
                               path: root.path, kind: .directory, logicalBytes: 12,
                               allocatedBytes: 16, aggregateComplete: true, scannedAt: now,
                               error: nil, symbolicLinkDestination: nil, tags: [])
    let completed = StorageScanState(rootPath: root.path, startedAt: now, updatedAt: now,
                                     completedAt: now, status: .completed, scannedCount: 1,
                                     errors: [], nodes: [rootNode], totalLogicalBytes: 12,
                                     totalAllocatedBytes: 16)
    let stale = StorageScanState(rootPath: temporary.appendingPathComponent("old").path,
                                 startedAt: now, updatedAt: now, completedAt: now,
                                 status: .completed, scannedCount: 99, errors: [], nodes: [],
                                 totalLogicalBytes: 999, totalAllocatedBytes: 999)
    try storeExpect(MonitorStore.acceptsScanUpdate(completed, activeRoot: root.path),
                    "the active scan snapshot should be accepted")
    try storeExpect(!MonitorStore.acceptsScanUpdate(stale, activeRoot: root.path),
                    "a superseded scan callback must not replace the active scan")
    try storeExpect(!MonitorStore.acceptsScanUpdate(completed, activeRoot: nil),
                    "callbacks before a requested scan must not replace restored state")

    var oldGeneration = completed
    oldGeneration.scanID = "old"
    try storeExpect(!MonitorStore.acceptsScanUpdate(oldGeneration, activeRoot: root.path, activeID: "new"), "same-root stale scan generation must be rejected")

    let archive = temporary.appendingPathComponent("storage.json")
    try MonitorStore.writeStorageSnapshot(completed, to: archive)
    let restored = try StorageScanner.load(from: archive)
    try storeExpect(restored.status == .saved && restored.rootPath == root.path && restored.totalLogicalBytes == 12,
                    "storage persistence must encode the callback snapshot itself")
    do {
        var incomplete = completed
        incomplete.status = .scanning
        try MonitorStore.writeStorageSnapshot(incomplete, to: archive)
        try storeExpect(false, "an incomplete scan must never overwrite the saved snapshot")
    } catch is StorageScannerError {
        let stillRestored = try StorageScanner.load(from: archive)
        try storeExpect(stillRestored.totalLogicalBytes == 12,
                        "rejected incomplete snapshots must leave the previous archive intact")
    }

    let historyQueue = DispatchQueue(label: "test.blocked.history")
    let gate = DispatchSemaphore(value: 0)
    historyQueue.async { gate.wait() }
    let store = MonitorStore(directory: temporary.appendingPathComponent("lifecycle", isDirectory: true), historyQueue: historyQueue)
    try storeExpect(store.isRunning, "store should start ordinary unprivileged monitoring")
    let firstSegment = store.observationSnapshot().collection.segmentID
    try storeExpect(store.observationSnapshot().collection.state == .running && firstSegment != nil,
                    "snapshot must expose a running collection segment")
    store.pause()
    try storeExpect(store.observationSnapshot().collection.state == .paused,
                    "snapshot must distinguish paused from running")
    try storeExpect(!store.isRunning && !store.isSampling, "pause must stop scheduling immediately")
    store.start()
    try storeExpect(store.observationSnapshot().collection.segmentID != firstSegment &&
                    store.observationSnapshot().collection.sampleSegmentID == nil,
                    "resume must expose a fresh segment without claiming an uncollected sample")
    try storeExpect(store.isRunning, "resume must create a fresh running segment")
    let process = ProcessSample(pid: 42, parentPID: 1, startTime: now, name: "fixture", path: "", owner: "fixture", bundleID: nil,
                                cpuPercent: 20, threadCount: 1, residentBytes: 100, footprintBytes: 100,
                                diskReadBytes: 200, diskWriteBytes: 300, readBytesPerSecond: 5, writeBytesPerSecond: 6,
                                growthNote: nil, measurementInterval: 2.375)
    store.processes = [process]; store.lastSample = now
    let observation = store.observationSnapshot()
    try storeExpect(observation.processes[0].metrics.first { $0.metricID == "cpu.percent" }?.interval == 2.375,
                    "Store observation must preserve the actual rate window")
    store.pause()
    let powerTime = now.addingTimeInterval(3)
    // Simulate a pending one-shot result being accepted after basic collection paused.
    store.powerDetails[.gpu] = PanelReading(tab: .gpu, metrics: [
        Metric("power.fields", "追加値", value: 1, source: "fixture", recordedAt: powerTime)
    ], capturedAt: powerTime)
    let paused = store.observationSnapshot()
    let power = paused.categories.first { $0.category == .gpu }?.metrics.first
    try storeExpect(paused.collection.state == .paused && paused.collection.lastSampleAt == now &&
                    power?.recordedAt == powerTime && power?.status == .measured,
                    "power completion while paused must preserve both basic state and measurement provenance")

    func inventory(_ ids: [String], _ status: ReadingStatus) -> PanelReading {
        PanelReading(tab: .devices, metrics: [Metric("device_inventory_status", "取得状態", status: status, source: "fixture")],
                     rows: ids.map { ReadingRow(id: $0, name: $0, metrics: []) }, capturedAt: now)
    }
    store.acceptDeviceInventory(inventory(["a", "b"], .measured))
    store.acceptDeviceInventory(inventory([], .unavailable))
    store.acceptDeviceInventory(inventory(["a", "c"], .partial))
    try storeExpect(store.deviceEvents.isEmpty, "failed or partial inventory must not fabricate device changes")
    store.acceptDeviceInventory(inventory(["a", "b"], .measured))
    try storeExpect(store.deviceEvents.isEmpty, "recovery must keep the previous complete inventory baseline")
    store.acceptDeviceInventory(inventory(["a"], .measured))
    try storeExpect(store.deviceEvents.count == 1 && store.deviceEvents[0].contains("切断"), "one genuinely removed entry must emit one disconnect")
    store.acceptDeviceInventory(inventory(["a", "c"], .measured))
    try storeExpect(store.deviceEvents.count == 2 && store.deviceEvents[0].contains("接続: c"), "a new registry entry must emit one connection")
    let started = ProcessInfo.processInfo.systemUptime
    store.shutdown()
    try storeExpect(store.observationSnapshot().collection.state == .stopped,
                    "shutdown must expose a terminal collection state")
    try storeExpect(ProcessInfo.processInfo.systemUptime - started < 1, "shutdown must not wait on blocked persistence")
    await withCheckedContinuation { continuation in
        store.afterPendingSaves(timeout: 0.05) { continuation.resume() }
    }
    try storeExpect(!FileManager.default.fileExists(atPath: store.historyURL.path), "bounded save wait must return while persistence is still blocked")
    gate.signal()
    await withCheckedContinuation { continuation in
        store.afterPendingSaves { continuation.resume() }
    }
    try storeExpect(FileManager.default.fileExists(atPath: store.historyURL.path), "queued final history must finish after the writer unblocks")
    try storeExpect(!store.isRunning && store.panels.isEmpty && store.processes.isEmpty,
                    "shutdown must stop and release displayed live samples")
    store.start()
    try storeExpect(!store.isRunning, "shutdown must be terminal for the store instance")
}
