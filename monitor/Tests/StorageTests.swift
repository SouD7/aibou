import Foundation

private enum StorageTestFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self { case .assertion(let message): return message }
    }
}

private func storageExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw StorageTestFailure.assertion(message) }
}

private func waitForStorage(_ scanner: StorageScanner, timeout: TimeInterval = 8) -> StorageScanState {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let state = scanner.snapshot()
        if [.completed, .cancelled, .failed].contains(state.status) { return state }
        Thread.sleep(forTimeInterval: 0.01)
    }
    return scanner.snapshot()
}

func runStorageTests() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("AIBOU-StorageTests-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: base) }

    let hidden = base.appendingPathComponent(".hidden")
    let package = base.appendingPathComponent("Sample.app/Contents/Resources", isDirectory: true)
    let deep = base.appendingPathComponent("one/two/three", isDirectory: true)
    try fm.createDirectory(at: package, withIntermediateDirectories: true)
    try fm.createDirectory(at: deep, withIntermediateDirectories: true)
    try Data(repeating: 0x41, count: 11).write(to: hidden)
    try Data(repeating: 0x42, count: 23).write(to: deep.appendingPathComponent("payload.bin"))
    try Data(repeating: 0x43, count: 7).write(to: package.appendingPathComponent("asset.dat"))
    try fm.createSymbolicLink(at: base.appendingPathComponent("cycle"), withDestinationURL: base)
    try fm.linkItem(at: hidden, to: base.appendingPathComponent("hidden-hardlink"))

    let progressScanner = StorageScanner()
    let progressLock = NSLock()
    var leakedNodes = false
    progressScanner.onUpdate = { state in
        if state.status == .scanning {
            progressLock.lock(); leakedNodes = leakedNodes || !state.nodes.isEmpty; progressLock.unlock()
            if state.scannedCount == 0 { Thread.sleep(forTimeInterval: 0.35) }
        }
    }
    progressScanner.start(root: base)
    _ = waitForStorage(progressScanner)
    progressLock.lock(); let leaked = leakedNodes; progressLock.unlock()
    try storageExpect(!leaked, "progress must not expose the growing whole-node array")

    let scanner = StorageScanner()
    scanner.start(root: base)
    let result = waitForStorage(scanner)
    try storageExpect(result.status == .completed, "fixture scan did not complete: \(result.status)")
    try storageExpect(result.nodes.contains { $0.path == hidden.path }, "hidden file was omitted")
    try storageExpect(result.nodes.contains { $0.path.hasSuffix("Sample.app/Contents/Resources/asset.dat") },
                      "package descendants were omitted")
    try storageExpect(result.nodes.contains { $0.path.hasSuffix("one/two/three/payload.bin") },
                      "deep descendant was omitted; paths=\(result.nodes.map(\.path))")
    let symlink = result.nodes.first { $0.path == base.appendingPathComponent("cycle").path }
    try storageExpect(symlink?.kind == .symbolicLink, "symbolic link was not represented as a link node")
    try storageExpect(symlink?.symbolicLinkDestination != nil, "symbolic link destination was not recorded")
    try storageExpect(result.totalLogicalBytes == 41, "folder logical total should deduplicate hard links")
    try storageExpect(result.nodes.first?.aggregateComplete == true, "completed root aggregate was marked incomplete")
    try storageExpect(result.totalAllocatedBytes != nil, "allocated byte total should be reported on the fixture filesystem")

    let duplicate = result.nodes.first { $0.path.hasSuffix("hidden-hardlink") }
    try storageExpect(duplicate?.tags.contains { $0.reason.contains("重複計上") } == true,
                      "hard-linked file was not tagged as a duplicate")
    try storageExpect(duplicate?.logicalBytes == 11,
                      "duplicate node should retain its own reported logical size")

    let indexURL = base.appendingPathComponent("latest-index.json")
    try scanner.save(to: indexURL)
    let restored = try StorageScanner.load(from: indexURL)
    try storageExpect(restored.status == .saved, "restored index was not identified as saved data")
    let timestampDelta = abs((restored.completedAt ?? .distantPast).timeIntervalSince(result.completedAt ?? .distantFuture))
    try storageExpect(timestampDelta < 1, "completion timestamp changed materially during persistence")
    try storageExpect(restored.nodes.count == result.nodes.count, "persistence changed node count")
    let indexAttributes = try fm.attributesOfItem(atPath: indexURL.path)
    try storageExpect((indexAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                      "saved index permissions were not owner-only")
    let directoryAttributes = try fm.attributesOfItem(atPath: base.path)
    try storageExpect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
                      "index directory permissions were not owner-only")

    let corruptURL = base.appendingPathComponent("corrupt-index.json")
    try Data("{not-json".utf8).write(to: corruptURL)
    do {
        _ = try StorageScanner.load(from: corruptURL)
        throw StorageTestFailure.assertion("corrupt index unexpectedly loaded")
    } catch is StorageTestFailure {
        throw StorageTestFailure.assertion("corrupt index unexpectedly loaded")
    } catch { }

    let duplicateIndexURL = base.appendingPathComponent("duplicate-index.json")
    var archiveObject = try JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as! [String: Any]
    var archiveState = archiveObject["state"] as! [String: Any]
    var archivedNodes = archiveState["nodes"] as! [[String: Any]]
    archivedNodes.append(archivedNodes[0])
    archiveState["nodes"] = archivedNodes
    archiveObject["state"] = archiveState
    try JSONSerialization.data(withJSONObject: archiveObject).write(to: duplicateIndexURL)
    do {
        _ = try StorageScanner.load(from: duplicateIndexURL)
        throw StorageTestFailure.assertion("index with duplicate node IDs unexpectedly loaded")
    } catch is StorageTestFailure {
        throw StorageTestFailure.assertion("index with duplicate node IDs unexpectedly loaded")
    } catch { }

    func checkState(_ state: StorageScanState, valid: Bool, reason: String) throws {
        struct Archive: Encodable { var schemaVersion = 1; var state: StorageScanState }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Archive(state: state))
        try data.write(to: corruptURL)
        do {
            _ = try StorageScanner.load(from: corruptURL)
            try storageExpect(valid, "invalid graph accepted: \(reason)")
        } catch is StorageScannerError {
            try storageExpect(!valid, "valid graph rejected: \(reason)")
        }
        let after = try Data(contentsOf: corruptURL)
        try storageExpect(after == data, "loading must never rewrite the saved archive")
    }
    for defect in ["completion", "count", "logical", "allocated", "rootKind", "errors"] {
        var state = result
        switch defect {
        case "completion": state.completedAt = nil
        case "count": state.scannedCount += 1
        case "logical": state.totalLogicalBytes += 1
        case "allocated": state.totalAllocatedBytes = nil
        case "rootKind": state.nodes[0].kind = .file
        default: state.errorCount = -1
        }
        try checkState(state, valid: false, reason: "inconsistent summary: \(defect)")
    }
    var partial = result
    partial.nodes[0].aggregateComplete = false
    partial.errors = [StorageScanError(path: result.rootPath + "/protected", message: "fixture denied")]
    partial.errorCount = nil // Older schema-1 archives omit this optional field.
    partial.nodes[0].allocatedBytes = nil; partial.totalAllocatedBytes = nil
    try checkState(partial, valid: true, reason: "completed traversal with inaccessible data and unknown allocation")
    partial.errorCount = 0
    try checkState(partial, valid: false, reason: "fewer errors than retained details")
    partial.errorCount = 300
    try checkState(partial, valid: true, reason: "error details are capped independently of total errors")

    func checkArchive(_ nodes: [StorageNode], valid: Bool, reason: String) throws {
        var state = result
        state.nodes = nodes; state.scannedCount = nodes.count
        state.totalLogicalBytes = nodes.first?.logicalBytes ?? 0
        state.totalAllocatedBytes = nodes.first?.allocatedBytes
        try checkState(state, valid: valid, reason: reason)
    }
    let graphRoot = result.nodes[0]
    var a = graphRoot, b = graphRoot
    a.id += "/a"; a.path = a.id; a.parentID = graphRoot.id
    b.id += "/b"; b.path = b.id; b.parentID = graphRoot.id
    try checkArchive([graphRoot, b, a], valid: true, reason: "unordered siblings")
    a.parentID = b.id; b.parentID = a.id
    try checkArchive([graphRoot, a, b], valid: false, reason: "disconnected cycle")
    a.parentID = a.id
    try checkArchive([graphRoot, a], valid: false, reason: "self cycle")
    a.parentID = nil
    try checkArchive([graphRoot, a], valid: false, reason: "second root")
    a.parentID = "/missing"
    try checkArchive([graphRoot, a], valid: false, reason: "missing parent")
    a.parentID = graphRoot.id; a.path = "/mismatched"
    try checkArchive([graphRoot, a], valid: false, reason: "path/ID mismatch")
    var parentedRoot = graphRoot; parentedRoot.parentID = graphRoot.id
    try checkArchive([parentedRoot], valid: false, reason: "root has parent")
    // Synthetic parent chain stresses graph traversal without creating on-disk directories.
    var chain = [graphRoot]
    for i in 0..<20_000 {
        var node = graphRoot
        node.id += "/node\(i)"; node.path = node.id; node.parentID = chain.last!.id
        chain.append(node)
    }
    try checkArchive([graphRoot] + chain.dropFirst().reversed(), valid: true, reason: "deep reverse-ordered chain")

    let info: [String: Any] = [
        "CFBundleIdentifier": "com.example.sample",
        "CFBundleName": "Fixture Name",
        "CFBundleDisplayName": "Fixture Display Name",
        "CFBundlePackageType": "APPL"
    ]
    let infoURL = base.appendingPathComponent("Sample.app/Contents/Info.plist")
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
    let fakeHome = base.appendingPathComponent("home", isDirectory: true)
    let displayNameData = fakeHome.appendingPathComponent("Library/Application Support/Fixture Display Name",
                                                           isDirectory: true)
    let bundleNameCache = fakeHome.appendingPathComponent("Library/Caches/Fixture Name", isDirectory: true)
    try fm.createDirectory(at: displayNameData, withIntermediateDirectories: true)
    try fm.createDirectory(at: bundleNameCache, withIntermediateDirectories: true)

    let associationScanner = StorageScanner(homeDirectory: fakeHome)
    let associations = associationScanner.associatedFolders(appPath: package.appendingPathComponent("asset.dat").path,
                                                             bundleID: "com.example.sample")
    try storageExpect(associations.contains { $0.path.hasSuffix("Sample.app") && $0.confirmed },
                      "specified application was not returned as a confirmed association")
    try storageExpect(associations.contains { $0.path == displayNameData.path && !$0.confirmed },
                      "CFBundleDisplayName application data candidate was omitted")
    try storageExpect(associations.contains { $0.path == bundleNameCache.path && !$0.confirmed },
                      "CFBundleName cache candidate was omitted")

    let missingScanner = StorageScanner()
    missingScanner.start(root: base.appendingPathComponent("does-not-exist"))
    let missing = waitForStorage(missingScanner)
    try storageExpect(missing.status == .failed && !missing.errors.isEmpty,
                      "unreadable root did not produce an explicit failure")

    let cancelRoot = base.appendingPathComponent("cancel", isDirectory: true)
    try fm.createDirectory(at: cancelRoot, withIntermediateDirectories: true)
    for index in 0..<400 {
        let directory = cancelRoot.appendingPathComponent("d\(index)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data([UInt8(index % 255)]).write(to: directory.appendingPathComponent("f"))
    }
    let pauseScanner = StorageScanner()
    let callbackLock = NSLock()
    var callbackCount = 0
    pauseScanner.onUpdate = { _ in
        callbackLock.lock(); callbackCount += 1; callbackLock.unlock()
    }
    pauseScanner.start(root: cancelRoot)
    pauseScanner.pause()
    try storageExpect(pauseScanner.snapshot().status == .paused, "pause was not exposed in scan state")
    pauseScanner.resume()
    try storageExpect(waitForStorage(pauseScanner).status == .completed, "resumed scan did not complete")
    callbackLock.lock(); let observedCallbackCount = callbackCount; callbackLock.unlock()
    try storageExpect(observedCallbackCount < 20,
                      "progress snapshots were published too frequently: \(observedCallbackCount)")

    let cancelScanner = StorageScanner()
    cancelScanner.start(root: cancelRoot)
    cancelScanner.cancel()
    let cancelled = waitForStorage(cancelScanner)
    try storageExpect(cancelled.status == .cancelled, "cancel request did not stop traversal")
    try storageExpect(cancelled.completedAt == nil, "cancelled scan was presented as complete")
    try storageExpect(cancelled.nodes.allSatisfy { $0.kind != .directory || !$0.aggregateComplete },
                      "cancelled scan exposed a complete directory aggregate")

    let capped = StorageScanner(maximumNodes: 8)
    capped.start(root: cancelRoot)
    let cappedResult = waitForStorage(capped)
    try storageExpect(cappedResult.status == .cancelled && cappedResult.nodes.count <= 8 && cappedResult.stopReason != nil && cappedResult.stopCause == .nodeLimit, "resource cap must stop with explicit incomplete reason")
    try storageExpect(cappedResult.completedAt == nil, "resource cap must not count as completion")
    do { try capped.save(to: indexURL); throw StorageTestFailure.assertion("capped scan overwrote completed archive") }
    catch is StorageScannerError { }
    let budgeted = StorageScanner(maximumMetadataBytes: 1)
    budgeted.start(root: cancelRoot)
    let budgetResult = waitForStorage(budgeted)
    try storageExpect(budgetResult.status == .cancelled && budgetResult.nodes.count <= 1 && budgetResult.stopCause == .metadataLimit, "metadata budget must bound traversal")
    let tree = StorageTreeIndex(nodes: result.nodes)
    try storageExpect(tree.count(in: base.path) == result.children(of: base.path).count, "indexed child count differs")
    try storageExpect(tree.page(in: base.path).map(\.id) == result.children(of: base.path).map(\.id), "indexed order differs")
    try storageExpect(tree.page(in: base.path, offset: -1).isEmpty, "invalid page must be empty")
    try storageExpect(tree.node(hidden.path)?.parentID == base.path, "parent lookup failed")

    let restartScanner = StorageScanner()
    restartScanner.start(root: cancelRoot)
    restartScanner.start(root: deep)
    let restarted = waitForStorage(restartScanner)
    try storageExpect(restarted.status == .completed && restarted.rootPath == deep.path,
                      "a superseded scan overwrote the replacement scan")
    try storageExpect(restarted.children(of: deep.path).contains { $0.name == "payload.bin" },
                      "flat index child lookup did not return direct children")
}
