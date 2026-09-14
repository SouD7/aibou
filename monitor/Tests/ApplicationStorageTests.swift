import Foundation
import Darwin

private func applicationStorageExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "ApplicationStorageTests", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: message]) }
}

func runApplicationStorageTests() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("aibou-application-storage-\(UUID())", isDirectory: true)
    defer { try? fm.removeItem(at: base) }

    let home = base.appendingPathComponent("home", isDirectory: true)
    let appURL = base.appendingPathComponent("Sample.app", isDirectory: true)
    let appContents = appURL.appendingPathComponent("Contents", isDirectory: true)
    try fm.createDirectory(at: appContents, withIntermediateDirectories: true)
    let appData = appContents.appendingPathComponent("payload.bin")
    try Data(repeating: 1, count: 5).write(to: appData)

    let outside = base.appendingPathComponent("outside.bin")
    try Data(repeating: 2, count: 101).write(to: outside)
    try fm.createSymbolicLink(at: appContents.appendingPathComponent("outside-link"),
                              withDestinationURL: outside)
    let afterLink = appContents.appendingPathComponent("z-after-link", isDirectory: true)
    try fm.createDirectory(at: afterLink, withIntermediateDirectories: false)
    try Data(repeating: 5, count: 13).write(to: afterLink.appendingPathComponent("must-be-counted.bin"))

    let bundleID = "com.example.storage-fixture"
    let support = home.appendingPathComponent("Library/Application Support/\(bundleID)", isDirectory: true)
    let cache = home.appendingPathComponent("Library/Caches/\(bundleID)", isDirectory: true)
    try fm.createDirectory(at: support, withIntermediateDirectories: true)
    try fm.createDirectory(at: cache, withIntermediateDirectories: true)
    let supportData = support.appendingPathComponent("state.bin")
    try Data(repeating: 3, count: 7).write(to: supportData)
    try Data(repeating: 4, count: 3).write(to: cache.appendingPathComponent("unique.bin"))

    let relatedHardLink = cache.appendingPathComponent("same-state.bin")
    guard Darwin.link(supportData.path, relatedHardLink.path) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let appHardLink = support.appendingPathComponent("same-as-app.bin")
    guard Darwin.link(appData.path, appHardLink.path) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    let app = LauncherApplication(url: appURL, name: "Sample", bundleID: bundleID)
    let result = ApplicationStorage.scan(app: app, homeDirectory: home)
    try applicationStorageExpect(result.status == .completed && result.complete,
                                 "complete fixture was not reported complete")
    try applicationStorageExpect(result.appBytes == 18,
                                 "app bundle counted a symlink target or skipped the sibling after it: \(result.appBytes)")
    try applicationStorageExpect(result.relatedBytes == 10,
                                 "related roots double-counted hard links: \(result.relatedBytes)")
    try applicationStorageExpect(result.combinedBytes == 28,
                                 "combined observed bytes were incorrect")
    try applicationStorageExpect(result.relatedFilesAreEstimatedCandidates,
                                 "related storage was not explicitly marked as estimated candidates")
    try applicationStorageExpect(result.rows.contains { $0.scope == .application && $0.confirmed && $0.complete },
                                 "app evidence row was omitted")
    try applicationStorageExpect(result.rows.filter { $0.scope == .related }.allSatisfy { !$0.evidence.isEmpty },
                                 "related path evidence was omitted")

    let limited = ApplicationStorage.scan(
        app: app,
        homeDirectory: home,
        limits: ApplicationStorageLimits(maximumEntries: 2, maximumErrors: 8, maximumDuration: 5)
    )
    try applicationStorageExpect(limited.status == .partial && !limited.complete,
                                 "entry limit was presented as a complete zero-byte result")
    try applicationStorageExpect(limited.rows.contains { $0.status == .limitReached },
                                 "entry limit was not distinguishable in row evidence")
    try applicationStorageExpect(limited.notes.contains { $0.contains("読み取れた範囲") },
                                 "partial result caveat was omitted")

    let cancelled = ApplicationStorage.scan(app: app, homeDirectory: home, isCancelled: { true })
    try applicationStorageExpect(cancelled.status == .cancelled && !cancelled.complete,
                                 "cooperative cancellation was not exposed")
    try applicationStorageExpect(cancelled.rows.contains { $0.status == .cancelled },
                                 "cancelled roots were not marked")

    let escaped = home.appendingPathComponent("Library/Escape", isDirectory: true)
    try fm.createDirectory(at: escaped, withIntermediateDirectories: true)
    try Data(repeating: 6, count: 29).write(to: escaped.appendingPathComponent("must-not-scan.bin"))
    let malicious = LauncherApplication(url: appURL, name: "Sample", bundleID: "../Escape")
    let protected = ApplicationStorage.scan(app: malicious, homeDirectory: home)
    try applicationStorageExpect(protected.relatedBytes == 0,
                                 "a traversal-like discovery candidate escaped its standard Library base")
    try applicationStorageExpect(protected.rows.contains { $0.path == escaped.path && $0.status == .partial && $0.scannedEntries == 0 },
                                 "excluded discovery candidate did not preserve safety evidence")
    try applicationStorageExpect(protected.notes.contains { $0.contains("標準Library領域の外") },
                                 "unsafe candidate summary was omitted")

    let linkedTarget = base.appendingPathComponent("linked-related-target", isDirectory: true)
    try fm.createDirectory(at: linkedTarget, withIntermediateDirectories: true)
    try Data(repeating: 7, count: 31).write(to: linkedTarget.appendingPathComponent("must-not-scan.bin"))
    let linkedBundleID = "com.example.linked-storage"
    let linkedCandidate = home.appendingPathComponent("Library/Caches/\(linkedBundleID)")
    try fm.createSymbolicLink(at: linkedCandidate, withDestinationURL: linkedTarget)
    let linked = ApplicationStorage.scan(
        app: LauncherApplication(url: appURL, name: "Sample", bundleID: linkedBundleID),
        homeDirectory: home
    )
    try applicationStorageExpect(linked.relatedBytes == 0,
                                 "a symlinked related root was followed outside the allowed Library base")
    try applicationStorageExpect(linked.rows.contains { $0.path == linkedCandidate.path && $0.issues.contains { $0.contains("シンボリックリンク") } },
                                 "symlink rejection did not preserve per-path evidence")

    let errorBundleID = "com.example.storage-errors"
    let errorSupport = home.appendingPathComponent("Library/Application Support/\(errorBundleID)", isDirectory: true)
    let errorCache = home.appendingPathComponent("Library/Caches/\(errorBundleID)", isDirectory: true)
    let lockedDirectories = [errorSupport, errorCache].map { $0.appendingPathComponent("locked", isDirectory: true) }
    for directory in lockedDirectories {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([8]).write(to: directory.appendingPathComponent("hidden.bin"))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
    }
    let errorResult = ApplicationStorage.scan(
        app: LauncherApplication(url: appURL, name: "Sample", bundleID: errorBundleID),
        homeDirectory: home,
        limits: ApplicationStorageLimits(maximumEntries: 10_000, maximumErrors: 2, maximumDuration: 5)
    )
    for directory in lockedDirectories {
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    try applicationStorageExpect(errorResult.rows.contains { $0.status == .limitReached },
                                 "errors from later roots were not accumulated into the global error budget")

    let missing = LauncherApplication(url: base.appendingPathComponent("Missing.app"),
                                      name: "Missing", bundleID: "com.example.missing")
    let failed = ApplicationStorage.scan(app: missing, homeDirectory: home)
    try applicationStorageExpect(failed.status == .failed && !failed.complete,
                                 "missing app bundle was not an explicit failure")
    try applicationStorageExpect(failed.rows.first?.status == .unreadable,
                                 "missing app path did not preserve per-path failure evidence")
}
