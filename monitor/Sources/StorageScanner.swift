import Foundation
import Darwin

enum StorageScanStatus: String, Codable {
    case idle
    case scanning
    case paused
    case completed
    case cancelled
    case failed
    case saved
}

enum StorageStopCause: String, Codable {
    case user, nodeLimit, metadataLimit, errorLimit
}

enum StorageNodeKind: String, Codable {
    case file
    case directory
    case symbolicLink
    case other
}

struct StorageTag: Codable, Hashable {
    var name: String
    var reason: String
}

struct StorageScanError: Codable, Hashable {
    var path: String
    var message: String
}

struct StorageNode: Codable, Identifiable {
    var id: String
    var parentID: String?
    var name: String
    var path: String
    var kind: StorageNodeKind
    var logicalBytes: UInt64
    var allocatedBytes: UInt64?
    var aggregateComplete: Bool
    var scannedAt: Date
    var error: String?
    var symbolicLinkDestination: String?
    var tags: [StorageTag]
}

struct StorageScanState: Codable {
    var rootPath: String
    var startedAt: Date?
    var updatedAt: Date
    var completedAt: Date?
    var status: StorageScanStatus
    var scannedCount: Int
    var errors: [StorageScanError]
    var nodes: [StorageNode]
    var totalLogicalBytes: UInt64
    var totalAllocatedBytes: UInt64?
    var scanID: String? = nil
    var stopReason: String? = nil
    var stopCause: StorageStopCause? = nil
    var errorCount: Int? = nil
    var reportedErrorCount: Int { errorCount ?? errors.count }

    static let idle = StorageScanState(
        rootPath: "", startedAt: nil, updatedAt: Date(), completedAt: nil,
        status: .idle, scannedCount: 0, errors: [], nodes: [],
        totalLogicalBytes: 0, totalAllocatedBytes: nil
    )

    func children(of parentID: String?) -> [StorageNode] {
        nodes.filter { $0.parentID == parentID }.sorted {
            if $0.kind == .directory && $1.kind != .directory { return true }
            if $0.kind != .directory && $1.kind == .directory { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

/// Immutable, page-addressable view of a finished/aborted scan; construct off the UI thread.
final class StorageTreeIndex: @unchecked Sendable {
    private let nodes: [StorageNode]
    private let byID: [String: Int]
    private let byParent: [String: [Int]]
    static let pageSize = 500
    init(nodes: [StorageNode]) {
        self.nodes = nodes
        var ids: [String: Int] = [:], parents: [String: [Int]] = [:]
        for (offset, node) in nodes.enumerated() {
            ids[node.id] = offset
            if let parent = node.parentID { parents[parent, default: []].append(offset) }
        }
        for key in Array(parents.keys) {
            parents[key]!.sort { lhs, rhs in
                let a = nodes[lhs], b = nodes[rhs]
                if (a.kind == .directory) != (b.kind == .directory) { return a.kind == .directory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        byID = ids; byParent = parents
    }
    func node(_ id: String) -> StorageNode? { byID[id].map { nodes[$0] } }
    func count(in parent: String) -> Int { byParent[parent]?.count ?? 0 }
    func page(in parent: String, offset: Int = 0, limit: Int = StorageTreeIndex.pageSize) -> [StorageNode] {
        guard let indices = byParent[parent], offset >= 0, offset < indices.count else { return [] }
        return indices[offset..<min(indices.count, offset + min(max(0, limit), Self.pageSize))].map { nodes[$0] }
    }
}

struct StorageAssociatedFolder: Codable, Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var evidence: String
    var confirmed: Bool
}

enum StorageScannerError: Error, LocalizedError {
    case incompleteScan(StorageScanStatus)
    case invalidSavedIndex
    case savedIndexTooLarge

    var errorDescription: String? {
        switch self {
        case .incompleteScan(let status):
            return "完了していない走査結果（\(status.rawValue)）は保存できません。"
        case .invalidSavedIndex:
            return "保存されたストレージ索引は完了済みではありません。"
        case .savedIndexTooLarge:
            return "保存されたストレージ索引が許容サイズを超えています。"
        }
    }
}

private struct StorageIndexArchive: Codable {
    var schemaVersion: Int
    var state: StorageScanState
}

/// A cancellable, single-worker filesystem indexer. `onUpdate` runs on a background queue.
final class StorageScanner {
    var onUpdate: ((StorageScanState) -> Void)? {
        get { callbackLock.withLock { callback } }
        set { callbackLock.withLock { callback = newValue } }
    }

    private let workerQueue = DispatchQueue(label: "aibou.storage.scan", qos: .utility)
    private let homeDirectory: URL
    private let maximumNodes: Int
    private let maximumMetadataBytes: Int
    static let maximumArchiveBytes = 256 * 1_024 * 1_024
    private let stateLock = NSLock()
    private let callbackLock = NSLock()
    private let control = NSCondition()
    private var state: StorageScanState = .idle
    private var callback: ((StorageScanState) -> Void)?
    private var generation = UUID()
    private var pauseRequested = false
    private var cancelRequested = false
    private var lastPublishedAt = Date.distantPast

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser, maximumNodes: Int = 500_000, maximumMetadataBytes: Int = 128 * 1_024 * 1_024) {
        self.homeDirectory = homeDirectory
        self.maximumNodes = max(1, maximumNodes)
        self.maximumMetadataBytes = max(1, maximumMetadataBytes)
    }

    func start(root: URL = URL(fileURLWithPath: "/"), token: UUID = UUID()) {
        control.lock()
        generation = token
        pauseRequested = false
        cancelRequested = false
        control.broadcast()
        control.unlock()

        let path = normalizedPath(root)
        var initial = StorageScanState(
            rootPath: path, startedAt: Date(), updatedAt: Date(), completedAt: nil,
            status: .scanning, scannedCount: 0, errors: [], nodes: [],
            totalLogicalBytes: 0, totalAllocatedBytes: nil
        )
        initial.scanID = token.uuidString
        guard setState(initial, ifCurrent: token) else { return }
        publish(force: true)
        workerQueue.async { [weak self] in self?.scan(root: URL(fileURLWithPath: path), token: token) }
    }

    func pause() {
        control.lock()
        guard !cancelRequested else { control.unlock(); return }
        pauseRequested = true
        control.unlock()
        mutateState { state in
            if state.status == .scanning { state.status = .paused }
        }
        publish(force: true)
    }

    func resume() {
        control.lock()
        pauseRequested = false
        control.broadcast()
        control.unlock()
        mutateState { state in
            if state.status == .paused { state.status = .scanning }
        }
        publish(force: true)
    }

    func cancel() {
        control.lock()
        cancelRequested = true
        pauseRequested = false
        control.broadcast()
        control.unlock()
        mutateState { state in
            if [.scanning, .paused].contains(state.status) {
                state.status = .cancelled; state.completedAt = nil; state.updatedAt = Date()
                state.stopReason = "利用者が走査を中止しました"; state.stopCause = .user
            }
        }
        publish(force: true)
    }

    func snapshot() -> StorageScanState { stateLock.withLock { state } }

    func children(of parentID: String?) -> [StorageNode] { snapshot().children(of: parentID) }

    func save(to url: URL) throws {
        let current = snapshot()
        guard current.status == .completed else { throw StorageScannerError.incompleteScan(current.status) }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(StorageIndexArchive(schemaVersion: 1, state: current))
        guard data.count <= Self.maximumArchiveBytes else { throw StorageScannerError.savedIndexTooLarge }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func load(from url: URL) throws -> StorageScanState {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? NSNumber, size.uint64Value > UInt64(Self.maximumArchiveBytes) {
            throw StorageScannerError.savedIndexTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(StorageIndexArchive.self, from: Data(contentsOf: url, options: .mappedIfSafe))
        var result = archive.state
        guard archive.schemaVersion == 1,
              result.status == .completed,
              !result.rootPath.isEmpty,
              result.nodes.count <= 500_000,
              let root = result.nodes.first,
              root.id == result.rootPath, root.kind == .directory,
              result.completedAt != nil,
              result.scannedCount == result.nodes.count,
              result.totalLogicalBytes == root.logicalBytes,
              result.totalAllocatedBytes == root.allocatedBytes,
              result.reportedErrorCount >= result.errors.count,
              Self.validTree(result.nodes) else { throw StorageScannerError.invalidSavedIndex }
        result.status = .saved
        return result
    }

    /// Each node is visited at most twice; no recursive stack or ancestor-by-ancestor rescans.
    private static func validTree(_ nodes: [StorageNode]) -> Bool {
        guard let root = nodes.first, root.parentID == nil else { return false }
        var offsets: [String: Int] = [:]
        offsets.reserveCapacity(nodes.count)
        for (index, node) in nodes.enumerated() {
            guard node.path == node.id, offsets.updateValue(index, forKey: node.id) == nil else { return false }
        }
        var parents = [Int](repeating: 0, count: nodes.count)
        for index in nodes.indices.dropFirst() {
            guard let parent = nodes[index].parentID, let offset = offsets[parent] else { return false }
            parents[index] = offset
        }
        // 0: unvisited, 1: on current chain, 2: proven to reach the unique root.
        var marks = [UInt8](repeating: 0, count: nodes.count)
        marks[0] = 2
        var chain: [Int] = []
        for index in nodes.indices where marks[index] == 0 {
            chain.removeAll(keepingCapacity: true)
            var cursor = index
            while marks[cursor] == 0 {
                marks[cursor] = 1; chain.append(cursor); cursor = parents[cursor]
            }
            guard marks[cursor] == 2 else { return false }
            for visited in chain { marks[visited] = 2 }
        }
        return true
    }

    func associatedFolders(appPath: String, bundleID: String?) -> [StorageAssociatedFolder] {
        let fm = FileManager.default
        let appURL = enclosingApplicationURL(for: URL(fileURLWithPath: appPath))
        let executableName = appURL.deletingPathExtension().lastPathComponent
        let userLibrary = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        var candidates: [(URL, String, Bool)] = [(appURL, "アプリ本体（指定された実行元）", true)]

        var candidateNames = [executableName]
        if let bundle = Bundle(url: appURL) {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = bundle.object(forInfoDictionaryKey: key) as? String,
                   !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !candidateNames.contains(name) { candidateNames.append(name) }
                }
            }
        }

        if let bundleID, !bundleID.isEmpty {
            candidates += [
                (userLibrary.appendingPathComponent("Application Support/\(bundleID)"), "Bundle IDと標準保存先が一致する候補", false),
                (userLibrary.appendingPathComponent("Caches/\(bundleID)"), "Bundle IDと標準キャッシュ先が一致する候補", false),
                (userLibrary.appendingPathComponent("Preferences/\(bundleID).plist"), "Bundle IDと設定ファイル名が一致する候補", false),
                (userLibrary.appendingPathComponent("Saved Application State/\(bundleID).savedState"), "Bundle IDと保存状態名が一致する候補", false),
                (userLibrary.appendingPathComponent("Containers/\(bundleID)"), "Bundle IDとSandboxコンテナ名が一致する候補", false),
                (userLibrary.appendingPathComponent("HTTPStorages/\(bundleID)"), "Bundle IDとHTTP保存領域名が一致する候補", false),
                (userLibrary.appendingPathComponent("WebKit/\(bundleID)"), "Bundle IDとWebKit保存領域名が一致する候補", false),
                (URL(fileURLWithPath: "/Library/Caches/\(bundleID)"), "Bundle IDと全ユーザー向けキャッシュ名が一致する候補", false),
                (URL(fileURLWithPath: "/Library/Preferences/\(bundleID).plist"), "Bundle IDと全ユーザー向け設定名が一致する候補", false)
            ]
        }
        for appName in candidateNames where !appName.isEmpty {
            candidates += [
                (userLibrary.appendingPathComponent("Application Support/\(appName)"), "アプリ名と標準保存先の名称が一致する候補", false),
                (userLibrary.appendingPathComponent("Caches/\(appName)"), "アプリ名と標準キャッシュ先の名称が一致する候補", false),
                (URL(fileURLWithPath: "/Library/Application Support/\(appName)"), "アプリ名と全ユーザー向け保存先の名称が一致する候補", false),
                (URL(fileURLWithPath: "/Library/Caches/\(appName)"), "アプリ名と全ユーザー向けキャッシュ名が一致する候補", false)
            ]
        }

        var seen = Set<String>()
        return candidates.compactMap { url, evidence, confirmed in
            let path = normalizedPath(url)
            guard seen.insert(path).inserted, fm.fileExists(atPath: path) else { return nil }
            return StorageAssociatedFolder(name: url.lastPathComponent, path: path,
                                           evidence: evidence, confirmed: confirmed)
        }
    }

    private func enclosingApplicationURL(for url: URL) -> URL {
        var candidate = url.standardizedFileURL
        while candidate.path != "/" {
            if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame { return candidate }
            candidate.deleteLastPathComponent()
        }
        return url.standardizedFileURL
    }

    private func scan(root: URL, token: UUID) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                                      .fileSizeKey, .fileAllocatedSizeKey,
                                      .totalFileAllocatedSizeKey, .volumeURLKey, .nameKey]
        var nodes: [StorageNode] = []
        var seenResources = Set<FileIdentity>()
        var scanErrors: [StorageScanError] = []
        var errorCount = 0, metadataBytes = 0
        var totals = (logical: UInt64(0), allocated: Optional<UInt64>(0))
        func recordError(_ error: StorageScanError) {
            errorCount += 1
            if scanErrors.count < 256 { scanErrors.append(error) }
        }
        func recordNode(_ node: StorageNode) {
            nodes.append(node)
            // Conservative budget covers identities, parent/ID indexes, containers and JSON escaping.
            var stringBytes = node.path.utf8.count + node.name.utf8.count
            stringBytes += node.parentID?.utf8.count ?? 0
            stringBytes += node.symbolicLinkDestination?.utf8.count ?? 0
            stringBytes += node.error?.utf8.count ?? 0
            for tag in node.tags { stringBytes += tag.name.utf8.count + tag.reason.utf8.count }
            metadataBytes += 1_024 + 6 * stringBytes
            guard node.kind != .directory, !isDuplicateNode(node) else { return }
            totals.logical = addingWithoutOverflow(totals.logical, node.logicalBytes)
            if let current = totals.allocated, let value = node.allocatedBytes { totals.allocated = addingWithoutOverflow(current, value) }
            else { totals.allocated = nil }
        }

        guard shouldContinue(token: token) else {
            if isCurrent(token: token) { finishCancelled(nodes: nodes, errors: scanErrors, token: token) }
            return
        }
        let rootPath = normalizedPath(root)
        guard let rootValues = try? root.resourceValues(forKeys: Set(keys)), rootValues.isDirectory == true else {
            finishFailed(path: rootPath, message: "走査ルートを読み取れません。", token: token)
            return
        }
        recordNode(makeNode(url: root, values: rootValues, parentID: nil))
        if let identity = fileIdentity(atPath: rootPath) { seenResources.insert(identity) }

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { url, error in
                recordError(StorageScanError(path: url.path, message: error.localizedDescription))
                return true
            }
        ) else {
            finishFailed(path: rootPath, message: "ディレクトリ列挙を開始できません。", token: token)
            return
        }

        while let item = enumerator.nextObject() as? URL {
            guard shouldContinue(token: token) else {
                guard isCurrent(token: token) else { return }
                finishCancelled(nodes: nodes, errors: scanErrors, token: token, errorCount: errorCount, totals: totals)
                return
            }
            if nodes.count >= maximumNodes || metadataBytes >= maximumMetadataBytes || errorCount >= 10_000 {
                let cause: StorageStopCause = nodes.count >= maximumNodes ? .nodeLimit : (metadataBytes >= maximumMetadataBytes ? .metadataLimit : .errorLimit)
                let limit = cause == .nodeLimit ? "\(maximumNodes)件" : (cause == .metadataLimit ? "メタデータ見積もり\(maximumMetadataBytes)バイト" : "読み取りエラー10,000件")
                let reason = "走査の保護上限（\(limit)）に達しました。対象フォルダを絞って再走査してください。"
                recordError(StorageScanError(path: rootPath, message: reason))
                finishCancelled(nodes: nodes, errors: scanErrors, token: token, errorCount: errorCount, reason: reason, totals: totals, cause: cause)
                return
            }
            let path = normalizedPath(item)
            let parentPath = normalizedPath(item.deletingLastPathComponent())
            do {
                let values = try item.resourceValues(forKeys: Set(keys))
                var node = makeNode(url: item, values: values, parentID: parentPath)
                let mustSkipAlias = path == "/System/Volumes/Data" && rootPath == "/"
                let externalMount = isExternalMount(path: path, rootPath: rootPath, volumeURL: values.volume)
                var duplicate = false
                if values.isSymbolicLink != true, let identity = fileIdentity(atPath: path) {
                    duplicate = !seenResources.insert(identity).inserted
                }
                if mustSkipAlias || externalMount || duplicate {
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    let reason = mustSkipAlias ? "起動Dataボリュームの別名経路を二重走査しない" :
                        externalMount ? "外部または別ボリュームは明示選択時のみ走査" : "同じファイル実体の重複計上を防止"
                    node.tags.append(StorageTag(name: duplicate ? "重複実体" : "走査対象外", reason: reason))
                    node.aggregateComplete = true
                }
                recordNode(node)
            } catch {
                let message = error.localizedDescription
                recordError(StorageScanError(path: path, message: message))
                recordNode(StorageNode(id: path, parentID: parentPath, name: item.lastPathComponent,
                                         path: path, kind: .other, logicalBytes: 0, allocatedBytes: nil,
                                         aggregateComplete: false, scannedAt: Date(), error: message,
                                         symbolicLinkDestination: nil, tags: systemDataTags(path: path)))
            }

            if secondsSinceLastPublication() >= 0.3 {
                publishProgress(count: nodes.count, totals: totals, errors: scanErrors, errorCount: errorCount, token: token)
            }
        }

        guard isCurrent(token: token) else { return }
        aggregate(&nodes, complete: true, errors: scanErrors)
        if errorCount > scanErrors.count {
            for index in nodes.indices where nodes[index].kind == .directory { nodes[index].aggregateComplete = false }
        }
        let now = Date()
        let finalTotals = totalsFromRoot(nodes)
        var completed = StorageScanState(rootPath: rootPath, startedAt: snapshot().startedAt,
                                         updatedAt: now, completedAt: now, status: .completed,
                                         scannedCount: nodes.count, errors: scanErrors, nodes: nodes,
                                         totalLogicalBytes: finalTotals.logical, totalAllocatedBytes: finalTotals.allocated)
        completed.scanID = token.uuidString
        completed.errorCount = errorCount
        guard setState(completed, ifCurrent: token) else { return }
        publish(force: true)
    }

    private func makeNode(url: URL, values: URLResourceValues, parentID: String?) -> StorageNode {
        let path = normalizedPath(url)
        let kind: StorageNodeKind
        if values.isSymbolicLink == true { kind = .symbolicLink }
        else if values.isDirectory == true { kind = .directory }
        else if values.isRegularFile == true { kind = .file }
        else { kind = .other }
        let logical = kind == .file ? UInt64(max(0, values.fileSize ?? 0)) : 0
        let allocatedValue = values.totalFileAllocatedSize ?? values.fileAllocatedSize
        let allocated = kind == .file ? allocatedValue.map { UInt64(max(0, $0)) } : UInt64(0)
        let destination = kind == .symbolicLink ? try? FileManager.default.destinationOfSymbolicLink(atPath: path) : nil
        return StorageNode(id: path, parentID: parentID, name: values.name ?? url.lastPathComponent,
                           path: path, kind: kind, logicalBytes: logical, allocatedBytes: allocated,
                           aggregateComplete: kind != .directory, scannedAt: Date(), error: nil,
                           symbolicLinkDestination: destination, tags: systemDataTags(path: path))
    }

    private func publishProgress(count: Int, totals: (logical: UInt64, allocated: UInt64?), errors: [StorageScanError], errorCount: Int, token: UUID) {
        mutateState(ifCurrent: token) { state in
            state.updatedAt = Date()
            state.scannedCount = count
            state.errors = errors
            state.errorCount = errorCount
            // The growing array stays exclusively with the worker until traversal stops.
            state.totalLogicalBytes = totals.logical
            state.totalAllocatedBytes = totals.allocated
        }
        publish(force: false)
    }

    private func aggregate(_ nodes: inout [StorageNode], complete: Bool, errors: [StorageScanError]) {
        var index = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        for i in nodes.indices where nodes[i].kind == .directory {
            nodes[i].aggregateComplete = complete
        }
        if complete {
            for scanError in errors {
                var candidate = URL(fileURLWithPath: scanError.path).deletingLastPathComponent().path
                while !candidate.isEmpty {
                    if let directoryIndex = index[candidate] {
                        nodes[directoryIndex].aggregateComplete = false
                        break
                    }
                    if candidate == "/" { break }
                    candidate = URL(fileURLWithPath: candidate).deletingLastPathComponent().path
                }
            }
        }
        for childIndex in nodes.indices.reversed() {
            guard let parentID = nodes[childIndex].parentID, let parentIndex = index[parentID] else { continue }
            if !isDuplicateNode(nodes[childIndex]) {
                nodes[parentIndex].logicalBytes = addingWithoutOverflow(nodes[parentIndex].logicalBytes, nodes[childIndex].logicalBytes)
                if let parentAllocated = nodes[parentIndex].allocatedBytes, let childAllocated = nodes[childIndex].allocatedBytes {
                    nodes[parentIndex].allocatedBytes = addingWithoutOverflow(parentAllocated, childAllocated)
                } else {
                    nodes[parentIndex].allocatedBytes = nil
                }
            }
            if nodes[childIndex].error != nil || !nodes[childIndex].aggregateComplete {
                nodes[parentIndex].aggregateComplete = false
            }
        }
        index.removeAll(keepingCapacity: false)
    }

    private func shouldContinue(token: UUID) -> Bool {
        control.lock()
        defer { control.unlock() }
        while token == generation && pauseRequested && !cancelRequested { control.wait() }
        return token == generation && !cancelRequested
    }

    private func isCurrent(token: UUID) -> Bool {
        control.lock(); defer { control.unlock() }
        return token == generation
    }

    private func finishCancelled(nodes: [StorageNode], errors: [StorageScanError], token: UUID, errorCount: Int? = nil, reason: String? = nil, totals suppliedTotals: (logical: UInt64, allocated: UInt64?)? = nil, cause: StorageStopCause? = nil) {
        let totals = suppliedTotals ?? totalsFromRoot(nodes)
        mutateState(ifCurrent: token) { state in
            state.status = .cancelled; state.updatedAt = Date(); state.completedAt = nil
            state.errorCount = errorCount ?? errors.count; state.stopReason = reason ?? state.stopReason; state.stopCause = cause ?? state.stopCause
            state.scannedCount = nodes.count; state.nodes = nodes; state.errors = errors
            state.totalLogicalBytes = totals.logical; state.totalAllocatedBytes = totals.allocated
        }
        publish(force: true)
    }

    private func finishFailed(path: String, message: String, token: UUID) {
        mutateState(ifCurrent: token) { state in
            state.status = .failed; state.updatedAt = Date(); state.completedAt = nil
            state.errors = [StorageScanError(path: path, message: message)]
        }
        publish(force: true)
    }

    private func totalsFromRoot(_ nodes: [StorageNode]) -> (logical: UInt64, allocated: UInt64?) {
        guard let root = nodes.first else { return (0, nil) }
        return (root.logicalBytes, root.allocatedBytes)
    }

    private func setState(_ newState: StorageScanState, ifCurrent token: UUID) -> Bool {
        control.lock(); defer { control.unlock() }
        guard token == generation else { return false }
        stateLock.withLock { state = newState }
        return true
    }
    private func mutateState(_ body: (inout StorageScanState) -> Void) {
        stateLock.withLock { body(&state) }
    }
    private func mutateState(ifCurrent token: UUID, _ body: (inout StorageScanState) -> Void) {
        control.lock(); defer { control.unlock() }
        guard token == generation else { return }
        stateLock.withLock { body(&state) }
    }

    private func publish(force: Bool) {
        let now = Date()
        callbackLock.lock()
        guard force || now.timeIntervalSince(lastPublishedAt) >= 0.25 else {
            callbackLock.unlock()
            return
        }
        lastPublishedAt = now
        let currentCallback = callback
        callbackLock.unlock()
        let value = snapshot()
        currentCallback?(value)
    }

    private func secondsSinceLastPublication() -> TimeInterval {
        callbackLock.withLock { Date().timeIntervalSince(lastPublishedAt) }
    }
}

private func normalizedPath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
}

private struct FileIdentity: Hashable {
    var device: UInt64
    var inode: UInt64
}

private func fileIdentity(atPath path: String) -> FileIdentity? {
    var information = stat()
    guard lstat(path, &information) == 0 else { return nil }
    return FileIdentity(device: UInt64(information.st_dev), inode: UInt64(information.st_ino))
}

private func addingWithoutOverflow(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? UInt64.max : result
}

private func isDuplicateNode(_ node: StorageNode) -> Bool {
    node.tags.contains { $0.name == "重複実体" }
}

private func isExternalMount(path: String, rootPath: String, volumeURL: URL?) -> Bool {
    guard rootPath == "/" else { return false }
    if path.hasPrefix("/Volumes/") { return true }
    guard let volumeURL else { return false }
    let volumePath = normalizedPath(volumeURL)
    return volumePath != "/" && volumePath != "/System/Volumes/Data"
}

private func systemDataTags(path: String) -> [StorageTag] {
    let rules: [(String, String)] = [
        ("/System", "macOSのシステム領域にあるため"),
        ("/Library", "全ユーザー向けのシステム・アプリ補助データ領域にあるため"),
        ("/private/var", "ログ、キャッシュ、仮想メモリ等が置かれる可変システム領域にあるため"),
        ("/private/tmp", "一時データ領域にあるため")
    ]
    if let match = rules.first(where: { path == $0.0 || path.hasPrefix($0.0 + "/") }) {
        return [StorageTag(name: "システムデータ候補", reason: match.1 + "。macOS設定の分類との一致は保証しません。")]
    }
    let userLibrary = NSHomeDirectory() + "/Library/"
    let userCandidates = ["Caches/", "Logs/", "Application Support/"]
    if path.hasPrefix(userLibrary), userCandidates.contains(where: { path.hasPrefix(userLibrary + $0) }) {
        return [StorageTag(name: "システムデータ候補",
                           reason: "ユーザーLibrary内のキャッシュ・ログ・アプリ補助データ候補です。macOS設定の分類との一致は保証しません。")]
    }
    return []
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }; return try body()
    }
}
