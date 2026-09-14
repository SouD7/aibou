import Foundation
import AppKit
import Combine

final class MonitoringEngine: @unchecked Sendable {
    let core = CoreSampler()
    let device = DeviceSampler()
    func collect(interval: Double) -> (CoreReading, [PanelReading], Double) {
        let start = ProcessInfo.processInfo.systemUptime
        let result = core.sample(expectedInterval: interval)
        let panels = result.panels + device.sample()
        return (result, panels, (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
    /// One-shot (.snapshot), not a continuity session; do not call concurrently.
    /// Use MonitorStore.diagnosticResults for the two sustained CPU diagnostic rules.
    func collectObservations(interval: Double) -> ObservationSnapshot {
        let result = collect(interval: interval)
        return ObservationSnapshot(panels: result.1, processes: result.0.processes, capturedAt: result.0.capturedAt)
    }
}

private struct StoreTransfer<Value>: @unchecked Sendable {
    let value: Value
}

private struct StoreStorageIndexArchive: Encodable {
    var schemaVersion: Int
    var state: StorageScanState
}

@MainActor
final class MonitorStore: ObservableObject {
    @Published var selectedTab: MonitorTab = .cpu
    @Published var panels: [MonitorTab: PanelReading] = [:]
    @Published var processes: [ProcessSample] = []
    @Published var isRunning = false
    @Published var isSampling = false
    @Published var detailed = false
    @Published var lastSample: Date?
    @Published var samplingMilliseconds = 0.0
    @Published var message = ""
    @Published var scan: StorageScanState = .idle
    @Published var selectedFolder: String? = nil { didSet { storagePage = 0 } }
    @Published var storagePage = 0
    @Published var storageLoading = false
    @Published var storagePersistence = ""
    private var storageIndex = StorageTreeIndex(nodes: [])
    var storageChildCount: Int { storageIndex.count(in: selectedFolder ?? scan.rootPath) }
    var visibleStorageNodes: [StorageNode] { storageIndex.page(in: selectedFolder ?? scan.rootPath, offset: storagePage * StorageTreeIndex.pageSize) }
    func parentStorageFolder() -> String? { storageIndex.node(selectedFolder ?? scan.rootPath)?.parentID }
    @Published var relatedFolders: [StorageAssociatedFolder] = []
    @Published var relatedApp = ""
    @Published var networkDetail: PanelReading?
    @Published var networkStableProcessIDs: Set<String> = []
    @Published var powerDetails: [MonitorTab: PanelReading] = [:]
    @Published var networkBusy = false
    @Published var powerBusy = false
    @Published var history = HistoryLedger()
    @Published var historyEnabled = true
    @Published var deviceEvents: [String] = []
    @Published var diagnosticSymptoms: Set<String> = []
    @Published var diagnosticChecks: Set<String> = []

    private let engine = MonitoringEngine()
    private var diagnosticEngine = DiagnosticEngine()
    private let scanner = StorageScanner()
    private let networkCollector = NetworkDetailCollector()
    private let powerCollector = PowerDetailCollector()
    private let queue = DispatchQueue(label: "aibou.monitor.sampling", qos: .utility)
    private let archiveQueue: DispatchQueue
    private let storageArchiveQueue = DispatchQueue(label: "aibou.storage.archive", qos: .utility)
    private let pendingSaves = DispatchGroup()
    private var timer: Timer?
    private var generation = UUID()
    private var segment = UUID().uuidString
    private var sampleSegment: String?
    private var lastArchive = Date.distantPast
    private var previousDevices: Set<String>?
    private var observers: [NSObjectProtocol] = []
    private var resumeAfterSleep = false
    private var acceptedSamples = 0
    private var didQAPause = false
    private var shuttingDown = false
    private var activeScanRoot: String?
    private var activeScanID: String?
    private var restoreGeneration = UUID()
    private let indexQueue = DispatchQueue(label: "aibou.storage.index", qos: .utility)
    private var networkOperation: CommandOperation?
    private var powerOperation: CommandOperation?
    private var relatedGeneration = UUID()
    private let archiveDirectory: URL
    /// Projects the latest snapshots without causing another hardware collection.
    func observationSnapshot() -> ObservationSnapshot {
        var latest = MonitorTab.allCases.compactMap { panels[$0] }
        latest += MonitorTab.allCases.compactMap { powerDetails[$0] }
        if let networkDetail { latest.append(networkDetail) }
        let collection = ObservationCollection(state: shuttingDown ? .stopped : (isRunning ? .running : .paused),
                                               segmentID: segment, sampleSegmentID: sampleSegment,
                                               lastSampleAt: lastSample)
        return ObservationSnapshot(panels: latest, processes: processes, capturedAt: lastSample ?? Date(),
                                   collection: collection)
    }
    /// Evaluation is read-only; elapsed time is established by accepted samples only.
    func diagnosticResults(now: Date = Date()) -> [DiagnosticResult] {
        diagnosticEngine.evaluate(observationSnapshot(), now: now)
    }
    var interval: Double { detailed ? 1 : 2 }
    /// Aggregate-only projection for consultation; avoids materializing process and file rows.
    func consultationAttachment(now: Date = Date()) -> ConsultationAttachment {
        let collection = ObservationCollection(state: shuttingDown ? .stopped : (isRunning ? .running : .paused),
            segmentID: segment, sampleSegmentID: sampleSegment, lastSampleAt: lastSample)
        return ConsultationAttachment.make(collection: collection,
            panels: MonitorTab.allCases.compactMap { panels[$0] }, now: now)
    }
    var historyURL: URL { archiveDirectory.appendingPathComponent("history.json") }
    var storageURL: URL { archiveDirectory.appendingPathComponent("storage.json") }

    init(directory: URL = LocalArchive.directory(), historyQueue: DispatchQueue = DispatchQueue(label: "aibou.monitor.archive", qos: .utility)) {
        archiveQueue = historyQueue
        archiveDirectory = directory
        historyEnabled = UserDefaults.standard.object(forKey: "saveAggregateHistory") as? Bool ?? true
        if FileManager.default.fileExists(atPath: historyURL.path) {
            do {
                history = try LocalArchive.read(HistoryLedger.self, from: historyURL)
                guard history.version == 1 else { throw NSError(domain: "AIBOU", code: 1, userInfo: [NSLocalizedDescriptionKey: "履歴形式が異なります"]) }
                history.sanitizeAfterLoading(now: Date())
            } catch { message = "履歴を読み込めません: \(error.localizedDescription)"; history = HistoryLedger() }
        }
        if FileManager.default.fileExists(atPath: storageURL.path) {
            storageLoading = true
            let token = restoreGeneration, url = storageURL
            indexQueue.async { [weak self] in
                do {
                    let restored = try StorageScanner.load(from: url)
                    let index = StorageTreeIndex(nodes: restored.nodes)
                    DispatchQueue.main.async {
                        guard let self, !self.shuttingDown, self.restoreGeneration == token else { return }
                        self.storageIndex = index; self.scan = restored; self.selectedFolder = restored.rootPath
                        self.storageLoading = false; self.storagePersistence = "保存済みの結果を復元しました"
                    }
                } catch {
                    let detail = error.localizedDescription
                    DispatchQueue.main.async {
                        guard let self, !self.shuttingDown, self.restoreGeneration == token else { return }
                        self.storageLoading = false; self.storagePersistence = "保存結果を復元できません: \(detail)"
                    }
                }
            }
        }
        scanner.onUpdate = { [weak self] state in
            guard let self else { return }
            // Only terminal snapshots carry nodes; indexing never blocks the UI thread.
            if [.completed, .cancelled, .failed].contains(state.status), !state.nodes.isEmpty {
                self.indexQueue.async {
                    let index = StorageTreeIndex(nodes: state.nodes)
                    DispatchQueue.main.async { self.acceptScan(state, index: index) }
                }
            } else {
                DispatchQueue.main.async { self.acceptScan(state, index: nil) }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.resumeAfterSleep = self.isRunning
                self.pause()
                if self.scan.status == .scanning { self.scanner.pause() }
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.resumeAfterSleep { self.start(preservingClock: true) }
                self.resumeAfterSleep = false
                self.message = "スリープ区間は欠測として扱います。ファイル走査は必要に応じて再開してください。"
            }
        })
        start()
        collectPower(administrator: false)
    }

    func start(preservingClock: Bool = false) {
        guard !isRunning, !shuttingDown else { return }
        isRunning = true; generation = UUID(); segment = UUID().uuidString
        let engine = engine
        queue.async { engine.core.reset(preservingClock: preservingClock) }
        configureTimer(); sample()
    }
    func pause() {
        diagnosticEngine.reset()
        isRunning = false; generation = UUID(); timer?.invalidate(); timer = nil
        isSampling = false
        cancelNetworkCollection()
        archiveHistory()
    }
    func setDetailed(_ value: Bool) {
        detailed = value
        if isRunning { pause(); start() }
    }
    private func configureTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    private func sample() {
        guard isRunning, !isSampling else { return }
        isSampling = true
        let token = generation, interval = interval, engine = engine
        queue.async { [weak self] in
            let result = engine.collect(interval: interval)
            DispatchQueue.main.async {
                guard let self, self.generation == token, self.isRunning else { return }
                self.isSampling = false
                self.processes = result.0.processes
                for panel in result.1 { self.panels[panel.tab] = panel }
                self.lastSample = result.0.capturedAt
                self.sampleSegment = self.segment
                self.diagnosticEngine.ingest(self.observationSnapshot(), now: Date())
                self.samplingMilliseconds = result.2
                if let devices = self.panels[.devices] { self.acceptDeviceInventory(devices) }
                if self.historyEnabled {
                    self.history.append(panels: result.1, segment: self.segment, now: result.0.capturedAt)
                    if Date().timeIntervalSince(self.lastArchive) >= 30 { self.archiveHistory() }
                } else { self.history.prune(now: Date()) }
                self.acceptedSamples += 1
                if !self.didQAPause, self.acceptedSamples >= 2,
                   ProcessInfo.processInfo.arguments.contains("--qa-pause-after-two-samples") {
                    self.didQAPause = true
                    self.pause()
                }
            }
        }
    }
    /// Only a complete inventory establishes presence or absence for connection events.
    func acceptDeviceInventory(_ panel: PanelReading) {
        guard panel.tab == .devices,
              panel.metrics.first(where: { $0.id == "device_inventory_status" })?.status == .measured else { return }
        let current = Set(panel.rows.map(\.id))
        if let previous = previousDevices {
            let time = panel.capturedAt.formatted(date: .omitted, time: .standard)
            for id in current.subtracting(previous) {
                let name = panel.rows.first { $0.id == id }?.name ?? id
                deviceEvents.insert("\(time) 接続: \(name)", at: 0)
            }
            for _ in previous.subtracting(current) { deviceEvents.insert("\(time) 外部機器の切断を検出", at: 0) }
            deviceEvents = Array(deviceEvents.prefix(30))
        }
        previousDevices = current
    }

    func setHistoryEnabled(_ enabled: Bool) {
        historyEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "saveAggregateHistory")
        segment = UUID().uuidString
        message = enabled ? "全体集計の24時間保存を開始しました" : "新しい履歴の保存を停止しました。既存履歴は「履歴削除」で削除できます。"
    }
    func clearHistory() {
        history = HistoryLedger(); segment = UUID().uuidString
        let url = historyURL
        let saves = pendingSaves
        saves.enter()
        archiveQueue.async { [weak self] in
            defer { saves.leave() }
            do { if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) } }
            catch { DispatchQueue.main.async { self?.message = "履歴削除に失敗: \(error.localizedDescription)" } }
        }
        message = "集計履歴を削除しました。スキャン結果は別に保持しています。"
    }
    private func archiveHistory() {
        history.prune(now: Date())
        let copy = history, url = historyURL
        lastArchive = Date()
        let saves = pendingSaves
        saves.enter()
        archiveQueue.async { [weak self] in
            defer { saves.leave() }
            do { try LocalArchive.write(copy, to: url) }
            catch { DispatchQueue.main.async { self?.message = "履歴保存に失敗: \(error.localizedDescription)" } }
        }
    }
    func startScan(root: URL) {
        guard !shuttingDown else { return }
        let normalized = Self.normalizedScanRoot(root), token = UUID()
        restoreGeneration = UUID(); storageLoading = false
        activeScanRoot = normalized; activeScanID = token.uuidString
        selectedFolder = normalized; storageIndex = StorageTreeIndex(nodes: [])
        storagePersistence = "走査中の結果は保存しません"
        scanner.start(root: URL(fileURLWithPath: normalized, isDirectory: true), token: token)
    }
    func chooseScanRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true; panel.message = "外付け・ネットワークドライブも、ここで選んだ範囲だけ走査します。"
        if panel.runModal() == .OK, let url = panel.url { startScan(root: url) }
    }
    func pauseScan() { scanner.pause() }
    func resumeScan() { scanner.resume() }
    func cancelScan() { scanner.cancel() }
    private func acceptScan(_ state: StorageScanState, index: StorageTreeIndex?) {
        guard !shuttingDown, Self.acceptsScanUpdate(state, activeRoot: activeScanRoot, activeID: activeScanID) else { return }
        // Ignore a delayed lightweight progress event after this generation finished.
        if scan.scanID == state.scanID, [.completed, .cancelled, .failed].contains(scan.status), state.status == .scanning { return }
        if let index { storageIndex = index }
        if state.status == .cancelled { storagePersistence = "中断結果は未保存です。以前の完了結果を保持しています" }
        scan = state
        if selectedFolder == nil { selectedFolder = state.rootPath }
        if state.status == .completed {
            storagePersistence = "完了結果を保存中…"
            let snapshot = StoreTransfer(value: state), url = storageURL, scanID = state.scanID
            let saves = pendingSaves
            saves.enter()
            storageArchiveQueue.async { [weak self] in
                defer { saves.leave() }
                let outcome: String
                do { try Self.writeStorageSnapshot(snapshot.value, to: url); outcome = "完了結果を保存しました" }
                catch { outcome = "完了・未保存: \(error.localizedDescription)。以前の保存結果を保持しています" }
                DispatchQueue.main.async {
                    guard let self, !self.shuttingDown, self.activeScanID == scanID else { return }
                    self.storagePersistence = outcome
                }
            }
        }
    }
    func showRelated(path: String, bundleID: String?) {
        let token = UUID()
        relatedGeneration = token
        var appPath = path
        if let range = path.range(of: ".app/") { appPath = String(path[..<range.lowerBound]) + ".app" }
        relatedApp = URL(fileURLWithPath: appPath).lastPathComponent
        let scanner = StoreTransfer(value: scanner)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let folders = scanner.value.associatedFolders(appPath: appPath, bundleID: bundleID)
            DispatchQueue.main.async {
                guard let self, !self.shuttingDown, self.relatedGeneration == token else { return }
                self.relatedFolders = folders
            }
        }
    }
    @discardableResult
    func collectNetwork() -> CommandOperation? {
        guard !networkBusy, isRunning, !shuttingDown, let operation = networkCollector.runner.reserveOperation() else { return nil }
        networkBusy = true; networkOperation = operation
        let collector = StoreTransfer(value: networkCollector)
        let processes = StoreTransfer(value: processes)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let before = Set(processes.value.filter { ApplicationNetworkUsage.identity($0.pid) == $0.id }.map(\.id))
            let result = collector.value.sample(operation: operation, processes: processes.value)
            let stable = Set(processes.value.filter { before.contains($0.id) && ApplicationNetworkUsage.identity($0.pid) == $0.id }.map(\.id))
            DispatchQueue.main.async {
                guard let self, !self.shuttingDown, self.networkOperation == operation else { return }
                self.networkOperation = nil
                self.networkStableProcessIDs = stable
                self.networkDetail = result; self.networkBusy = false
            }
        }
        return operation
    }
    func cancelNetworkCollection(operation: CommandOperation? = nil) {
        if let operation, networkOperation != operation { return }
        networkCollector.runner.cancel(); networkOperation = nil; networkBusy = false
        networkStableProcessIDs = []
    }
    func collectPower(administrator: Bool) {
        guard !powerBusy, !shuttingDown, let operation = powerCollector.runner.reserveOperation() else { return }
        powerBusy = true; powerOperation = operation
        let collector = StoreTransfer(value: powerCollector)
        let processSnapshot = StoreTransfer(value: processes)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = collector.value.sample(operation: operation, administrator: administrator, processes: processSnapshot.value)
            DispatchQueue.main.async {
                guard let self, !self.shuttingDown, self.powerOperation == operation else { return }
                self.powerOperation = nil
                for panel in result { self.powerDetails[panel.tab] = panel }
                self.powerBusy = false
            }
        }
    }
    func shutdown() {
        guard !shuttingDown else { return }
        pause(); shuttingDown = true
        relatedGeneration = UUID()
        scanner.onUpdate = nil; scanner.cancel()
        networkCollector.runner.shutdown(); powerCollector.runner.shutdown()
        networkOperation = nil; powerOperation = nil; restoreGeneration = UUID()
        networkDetail = nil; processes = []; relatedFolders = []; panels = [:]; powerDetails = [:]
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
    }

    /// Call after shutdown; direct command cleanup and saves share one deadline off the main thread.
    func afterPendingSaves(timeout: TimeInterval = 2, completion: @escaping @MainActor @Sendable () -> Void) {
        let saves = pendingSaves, networkRunner = networkCollector.runner, powerRunner = powerCollector.runner
        DispatchQueue.global(qos: .utility).async {
            let deadline = DispatchTime.now() + max(0, timeout)
            _ = networkRunner.waitForDirectProcess(until: deadline)
            _ = powerRunner.waitForDirectProcess(until: deadline)
            _ = saves.wait(timeout: deadline)
            DispatchQueue.main.async { completion() }
        }
    }

    static func normalizedScanRoot(_ root: URL) -> String {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func acceptsScanUpdate(_ state: StorageScanState, activeRoot: String?, activeID: String? = nil) -> Bool {
        guard let activeRoot else { return false }
        return state.rootPath == activeRoot && (activeID == nil || state.scanID == activeID)
    }

    nonisolated static func writeStorageSnapshot(_ state: StorageScanState, to url: URL) throws {
        guard state.status == .completed else { throw StorageScannerError.incompleteScan(state.status) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(StoreStorageIndexArchive(schemaVersion: 1, state: state))
        guard data.count <= StorageScanner.maximumArchiveBytes else { throw StorageScannerError.savedIndexTooLarge }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
