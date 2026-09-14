import Foundation
import AppKit
import SwiftUI

private func usageExpect(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: "ApplicationUsageTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private func usageProcess(_ pid: Int32, parent: Int32 = 1, path: String, start: TimeInterval = 100,
                          cpu: Double? = 25, memory: UInt64? = 100) -> ProcessSample {
    ProcessSample(pid: pid, parentPID: parent, startTime: Date(timeIntervalSince1970: start), name: "fixture-\(pid)",
                  path: path, owner: "fixture", bundleID: "test.same.identifier", cpuPercent: cpu, threadCount: 2,
                  residentBytes: memory, footprintBytes: memory, diskReadBytes: nil, diskWriteBytes: nil,
                  readBytesPerSecond: nil, writeBytesPerSecond: nil, growthNote: nil)
}

func runApplicationUsageTests() throws {
    let app = LauncherApplication(url: URL(fileURLWithPath: "/Fixture/App.app"), name: "App", bundleID: "test.same.identifier")
    let samples = [usageProcess(10, path: "/Fixture/App.app/Contents/MacOS/App"),
                   usageProcess(11, path: "/Fixture/App.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper"),
                   usageProcess(12, parent: 10, path: "/usr/bin/python3", start: 101, cpu: 50),
                   usageProcess(13, parent: 12, path: "/usr/bin/worker", start: 102, cpu: 0),
                   usageProcess(14, parent: 10, path: "/Fixture/Other.app/Contents/MacOS/Other"),
                   usageProcess(15, path: "/Another/App.app/Contents/MacOS/App"),
                   usageProcess(16, path: "/Fixture/App.app-extra/Contents/MacOS/Extra"),
                   usageProcess(17, parent: 10, path: "/usr/bin/old-child", start: 90)]
    let group = ApplicationProcessGroup.make(app: app, processes: samples.reversed())
    try usageExpect(Set(group.processes.map(\.pid)) == [10, 11, 12, 13], "include helper and descendant processes; exclude other apps/copies/prefix collisions/old reused parent")
    try usageExpect(group.inheritedIDs.count == 2, "ancestry-based attribution is explicitly estimated")
    let now = Date()
    let totals = group.metrics(recordedAt: now, inventoryStatus: .measured, running: true)
    try usageExpect(totals.first?.value == 100 && totals.first?.status == .estimated, "sum every selected process, preserving multicore CPU scale")
    try usageExpect(totals[1].value == 400, "sum footprints across helpers: \(String(describing: totals[1].value))")
    let incomplete = ApplicationProcessGroup(processes: [samples[0], usageProcess(18, path: samples[0].path, cpu: nil, memory: nil)], inheritedIDs: [])
    let partial = incomplete.metrics(recordedAt: now, inventoryStatus: .measured, running: true)
    try usageExpect(partial[0].value == 25 && partial[0].status == .partial, "missing counter must remain partial rather than silently zero")
    try usageExpect(group.metrics(recordedAt: now.addingTimeInterval(-11), inventoryStatus: .measured, running: true)[0].status == .stale,
                    "stalled sampler must not show current values")
    try usageExpect(group.metrics(recordedAt: now, inventoryStatus: .measured, running: false)[0].status == .stale, "paused values are stale")
    try usageExpect(ApplicationProcessGroup(processes: [], inheritedIDs: []).metrics(recordedAt: now, inventoryStatus: .unavailable, running: true)[0].value == nil,
                    "no processes cannot prove zero usage")
    try usageExpect(ApplicationProcessGroup(processes: [], inheritedIDs: []).metrics(recordedAt: now.addingTimeInterval(-20), inventoryStatus: .unavailable, running: false)[0].status == .unavailable,
                    "nil counters preserve unavailable status even when paused or old")

    func row(_ name: String, _ value: Double, status: ReadingStatus = .derived) -> ReadingRow {
        ReadingRow(id: name, name: name, metrics: ["receiveRate", "sendRate", "bytes_in", "bytes_out"].map {
            Metric($0, $0, value: value, unit: $0.hasSuffix("Rate") ? "B/s" : "B", status: status, source: "fixture")
        })
    }
    let two = ApplicationProcessGroup(processes: [samples[0], samples[1]], inheritedIDs: [])
    var panel = PanelReading(tab: .network, rows: [row("App.10", 8), row("Helper.11", 12), row("127.0.0.1<->10.0.0.10", 900), row("invalid label", 900)])
    let allIDs = Set(two.processes.map(\.id))
    let network = ApplicationNetworkUsage.aggregate(panel: panel, group: two, stableIDs: allIDs)
    try usageExpect(network.allSatisfy { $0.value == 20 && $0.status == .derived }, "network counts process rows only, not connections or malformed labels")
    let reused = ApplicationNetworkUsage.aggregate(panel: panel, group: two, stableIDs: [samples[0].id])
    try usageExpect(reused[0].value == 8 && reused[0].status == .partial, "PID start identity mismatch cannot be attributed")
    panel.rows.append(row("duplicate.10", 90))
    try usageExpect(ApplicationNetworkUsage.aggregate(panel: panel, group: two, stableIDs: allIDs)[0].value == 12, "ambiguous duplicate PID rows excluded")
    panel.rows = [row("App.10", -1), row("Helper.11", .infinity)]
    try usageExpect(ApplicationNetworkUsage.aggregate(panel: panel, group: two, stableIDs: allIDs)[0].value == nil, "negative and nonfinite values excluded")
    panel.rows = [row("App.10", 999, status: .waiting)]
    try usageExpect(ApplicationNetworkUsage.aggregate(panel: panel, group: two, stableIDs: allIDs).allSatisfy { $0.value == nil }, "first-sample lifetime bytes are not interval usage")
    panel = PanelReading(tab: .network, metrics: [Metric("nettop.status", "status", status: .denied, source: "fixture", detail: "permission denied")], capturedAt: now.addingTimeInterval(-20))
    try usageExpect(ApplicationNetworkUsage.aggregate(panel: panel, group: two, stableIDs: [], running: false)[0].status == .denied,
                    "permission failure must not be overwritten by stale status")
    try usageExpect(ApplicationNetworkUsage.identity(getpid()) != nil, "current process identity can be read")
    print("Application usage aggregation tests passed.")
}

@MainActor
func runApplicationDetailLifecycleTests() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-detail-lifecycle-\(UUID())")
    let store = MonitorStore(directory: directory)
    store.pause()
    store.isRunning = true // Enable only explicit collection; do not start a sampling timer.
    let foreign = store.collectNetwork()
    try usageExpect(foreign != nil && store.networkBusy, "network collection reserved")
    let detailAttempt = store.collectNetwork()
    try usageExpect(detailAttempt == nil, "detail cannot claim an already running collection")
    store.cancelNetworkCollection(operation: CommandOperation())
    try usageExpect(store.networkBusy, "unrelated view cannot cancel another consumer's request")
    if let foreign { store.cancelNetworkCollection(operation: foreign) }
    try usageExpect(!store.networkBusy && store.networkStableProcessIDs.isEmpty, "owner can cancel its own request and clear identities")
    store.shutdown()
    await withCheckedContinuation { continuation in store.afterPendingSaves { continuation.resume() } }
    try? FileManager.default.removeItem(at: directory)
    print("Application detail collection ownership tests passed.")
}

@MainActor
func renderApplicationDetailPreview(to destination: URL) async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-detail-preview-\(UUID())")
    let store = MonitorStore(directory: directory)
    store.pause()
    let app = LauncherApplication(url: URL(fileURLWithPath: "/Fixture/Example.app"), name: "Example", bundleID: "test.example")
    store.processes = [usageProcess(10, path: "/Fixture/Example.app/Contents/MacOS/Example", cpu: 45, memory: 314_572_800),
                       usageProcess(11, path: "/Fixture/Example.app/Contents/Helpers/Helper", cpu: 25, memory: 104_857_600)]
    store.lastSample = Date()
    store.panels[.cpu] = PanelReading(tab: .cpu, metrics: [Metric("processCount", "count", value: 2, source: "fixture")])
    store.isRunning = true
    store.networkStableProcessIDs = Set(store.processes.map(\.id))
    store.networkDetail = PanelReading(tab: .network, rows: store.processes.map { process in
        ReadingRow(id: process.id, name: "fixture.\(process.pid)", metrics: ["receiveRate", "sendRate", "bytes_in", "bytes_out"].map {
            Metric($0, $0, value: 2048, status: .derived, source: "fixture")
        })
    })
    let storage = ApplicationStorageResult(appBytes: 314_572_800, relatedBytes: 104_857_600, combinedBytes: 419_430_400,
        rows: [ApplicationStorageRow(scope: .application, name: "Example.app", path: app.url.path, evidence: "本体", confirmed: true,
            logicalBytes: 314_572_800, status: .complete, scannedEntries: 20, issues: []),
               ApplicationStorageRow(scope: .related, name: "test.example", path: "/Fixture/Library/Caches/test.example", evidence: "Bundle IDが一致するキャッシュ候補", confirmed: false,
            logicalBytes: 104_857_600, status: .complete, scannedEntries: 10, issues: [])],
        status: .completed, capturedAt: Date(), elapsed: 0.1, notes: ["関連ファイルは標準保存先からの推定候補です。"], relatedFilesAreEstimatedCandidates: true)
    let view = NSHostingView(rootView: ApplicationDetailView(app: app, store: store,
        model: ApplicationDetailModel(storage: storage), automaticallyCollect: false)
        .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    view.appearance = NSAppearance(named: .aqua)
    view.frame = NSRect(x: 0, y: 0, width: 880, height: 740)
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "preview", code: 1) }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "preview", code: 2) }
    try data.write(to: destination)
    store.shutdown()
    await withCheckedContinuation { continuation in store.afterPendingSaves { continuation.resume() } }
    try? FileManager.default.removeItem(at: directory)
    print("Application detail preview rendered from fixtures; no user application data scanned.")
}
