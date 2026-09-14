import Foundation
import Darwin

enum ApplicationStorageScope: String, Codable, Sendable {
    case application
    case related
}

enum ApplicationStorageRowStatus: String, Codable, Sendable {
    case complete
    case partial
    case cancelled
    case limitReached
    case unreadable
    case excludedOverlap
}

struct ApplicationStorageRow: Identifiable, Codable, Equatable, Sendable {
    var id: String { path }
    let scope: ApplicationStorageScope
    let name: String
    let path: String
    let evidence: String
    let confirmed: Bool
    let logicalBytes: UInt64
    let status: ApplicationStorageRowStatus
    let scannedEntries: Int
    let issues: [String]

    var complete: Bool { status == .complete || status == .excludedOverlap }
}

enum ApplicationStorageStatus: String, Codable, Sendable {
    case completed
    case partial
    case cancelled
    case failed
}

struct ApplicationStorageLimits: Sendable {
    var maximumEntries: Int = 250_000
    var maximumErrors: Int = 128
    var maximumDuration: TimeInterval = 15

    init(maximumEntries: Int = 250_000, maximumErrors: Int = 128, maximumDuration: TimeInterval = 15) {
        self.maximumEntries = max(1, maximumEntries)
        self.maximumErrors = max(1, maximumErrors)
        self.maximumDuration = max(0.01, maximumDuration)
    }
}

struct ApplicationStorageResult: Codable, Equatable, Sendable {
    let appBytes: UInt64
    let relatedBytes: UInt64
    let combinedBytes: UInt64
    let rows: [ApplicationStorageRow]
    let status: ApplicationStorageStatus
    let capturedAt: Date
    let elapsed: TimeInterval
    let notes: [String]

    /// Related paths are candidates inferred from bundle ID and app names. They are not an
    /// exhaustive or exclusive ownership map for the application.
    let relatedFilesAreEstimatedCandidates: Bool

    var complete: Bool { status == .completed }
}

enum ApplicationStorage {
    /// Performs one bounded snapshot. Call this off the main actor; cancellation is cooperative.
    static func scan(
        app: LauncherApplication,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        limits: ApplicationStorageLimits = ApplicationStorageLimits(),
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> ApplicationStorageResult {
        let started = ProcessInfo.processInfo.systemUptime
        let scanner = StorageScanner(homeDirectory: homeDirectory)
        let discovered = scanner.associatedFolders(appPath: app.url.path, bundleID: app.bundleID)
        let appPath = normalizedApplicationStoragePath(app.url)

        var candidates: [(folder: StorageAssociatedFolder, scope: ApplicationStorageScope, rejection: String?)] = discovered.map {
            let scope: ApplicationStorageScope = normalizedApplicationStoragePath(URL(fileURLWithPath: $0.path)) == appPath
                ? .application : .related
            let rejection = scope == .related
                ? relatedCandidateRejection(path: $0.path, homeDirectory: homeDirectory)
                : nil
            return ($0, scope, rejection)
        }
        if !candidates.contains(where: { $0.scope == .application }) {
            candidates.insert((StorageAssociatedFolder(name: app.url.lastPathComponent, path: appPath,
                                                        evidence: "アプリ本体（指定された実行元）", confirmed: true), .application, nil), at: 0)
        }
        candidates.sort {
            if $0.scope != $1.scope { return $0.scope == .application }
            let lhs = normalizedApplicationStoragePath(URL(fileURLWithPath: $0.folder.path))
            let rhs = normalizedApplicationStoragePath(URL(fileURLWithPath: $1.folder.path))
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return lhs < rhs
        }

        var budget = ScanBudget(limits: limits, startedAt: started, isCancelled: isCancelled)
        var identities = Set<ApplicationFileIdentity>()
        identities.reserveCapacity(min(limits.maximumEntries, 65_536))
        var acceptedRoots: [String] = []
        var rows: [ApplicationStorageRow] = []

        for (candidate, scope, rejection) in candidates {
            let path = normalizedApplicationStoragePath(URL(fileURLWithPath: candidate.path))
            if let rejection {
                rows.append(ApplicationStorageRow(
                    scope: scope, name: candidate.name, path: path, evidence: candidate.evidence,
                    confirmed: candidate.confirmed, logicalBytes: 0, status: .partial,
                    scannedEntries: 0, issues: [rejection]
                ))
                continue
            }
            if scope == .related, acceptedRoots.contains(where: { applicationStorageContains(parent: $0, child: path) }) {
                rows.append(ApplicationStorageRow(
                    scope: scope, name: candidate.name, path: path, evidence: candidate.evidence,
                    confirmed: candidate.confirmed, logicalBytes: 0, status: .excludedOverlap,
                    scannedEntries: 0, issues: ["上位の候補フォルダですでに集計済みのため、二重計上していません。"]
                ))
                continue
            }
            _ = budget.evaluateStop()
            if budget.stopStatus != nil {
                rows.append(unscannedRow(candidate: candidate, scope: scope, path: path, stop: budget.stopStatus!))
                continue
            }
            let row = scanRoot(candidate: candidate, scope: scope, path: path,
                               budget: &budget, identities: &identities)
            rows.append(row)
            if row.status != ApplicationStorageRowStatus.unreadable { acceptedRoots.append(path) }
        }

        let appBytes = sumWithoutOverflow(rows.lazy.filter { $0.scope == .application }.map(\.logicalBytes))
        let relatedBytes = sumWithoutOverflow(rows.lazy.filter { $0.scope == .related }.map(\.logicalBytes))
        let status: ApplicationStorageStatus
        if budget.stopStatus == ApplicationStorageRowStatus.cancelled { status = .cancelled }
        else if rows.first(where: { $0.scope == .application })?.status == .unreadable { status = .failed }
        else if rows.contains(where: { !$0.complete }) { status = .partial }
        else { status = .completed }

        var notes = ["関連ファイルはBundle IDとアプリ名から推定した標準保存先候補です。網羅性と、そのアプリだけが所有することは保証しません。"]
        if candidates.contains(where: { $0.rejection != nil }) {
            notes.append("標準Library領域の外へ出る候補、またはシンボリックリンクを経由する候補は安全のため走査していません。")
        }
        if status != .completed {
            notes.append("読み取れた範囲の容量を表示しています。未走査部分を0バイトとして完了扱いにはしていません。")
        }
        return ApplicationStorageResult(
            appBytes: appBytes,
            relatedBytes: relatedBytes,
            combinedBytes: addingApplicationStorageBytes(appBytes, relatedBytes),
            rows: rows,
            status: status,
            capturedAt: Date(),
            elapsed: max(0, ProcessInfo.processInfo.systemUptime - started),
            notes: notes,
            relatedFilesAreEstimatedCandidates: true
        )
    }

    private static func scanRoot(
        candidate: StorageAssociatedFolder,
        scope: ApplicationStorageScope,
        path: String,
        budget: inout ScanBudget,
        identities: inout Set<ApplicationFileIdentity>
    ) -> ApplicationStorageRow {
        var bytes: UInt64 = 0
        var entries = 0
        var issues: [String] = []
        var accountedEnumerationErrors = 0
        let root = URL(fileURLWithPath: path)

        guard let rootInfo = applicationStorageFileInfo(path) else {
            return ApplicationStorageRow(scope: scope, name: candidate.name, path: path,
                                         evidence: candidate.evidence, confirmed: candidate.confirmed,
                                         logicalBytes: 0, status: .unreadable, scannedEntries: 0,
                                         issues: ["この場所を読み取れません。移動、削除、またはアクセス権を確認してください。"])
        }
        if rootInfo.isSymbolicLink {
            return ApplicationStorageRow(scope: scope, name: candidate.name, path: path,
                                         evidence: candidate.evidence, confirmed: candidate.confirmed,
                                         logicalBytes: 0, status: .partial, scannedEntries: 1,
                                         issues: ["シンボリックリンクの参照先は安全のため自動走査していません。"])
        }
        if rootInfo.isRegularFile {
            budget.consumeEntry()
            entries = 1
            if identities.insert(rootInfo.identity).inserted { bytes = rootInfo.logicalBytes }
            return makeRow(candidate: candidate, scope: scope, path: path, bytes: bytes,
                           entries: entries, status: budget.stopStatus ?? .complete, issues: issues)
        }
        guard rootInfo.isDirectory else {
            return ApplicationStorageRow(scope: scope, name: candidate.name, path: path,
                                         evidence: candidate.evidence, confirmed: candidate.confirmed,
                                         logicalBytes: 0, status: .partial, scannedEntries: 1,
                                         issues: ["通常のファイルまたはフォルダではないため容量を集計できません。"])
        }

        budget.consumeEntry()
        entries = 1
        let enumerationErrors = ApplicationEnumerationErrors(maximumNames: 8)
        let maximumErrors = budget.limits.maximumErrors
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [],
            errorHandler: { url, _ in
                enumerationErrors.record(url.lastPathComponent)
                return enumerationErrors.count < maximumErrors
            }
        ) else {
            return ApplicationStorageRow(scope: scope, name: candidate.name, path: path,
                                         evidence: candidate.evidence, confirmed: candidate.confirmed,
                                         logicalBytes: 0, status: .unreadable, scannedEntries: entries,
                                         issues: ["フォルダの走査を開始できません。"])
        }

        while let item = enumerator.nextObject() as? URL {
            while accountedEnumerationErrors < enumerationErrors.count {
                budget.recordError()
                accountedEnumerationErrors += 1
            }
            if let stop = budget.evaluateStop() {
                if stop == .cancelled { issues.append("容量の集計を中止しました。") }
                else { issues.append("安全のため走査上限で停止しました。") }
                break
            }
            budget.consumeEntry()
            entries += 1
            guard let info = applicationStorageFileInfo(item.path) else {
                budget.recordError()
                if issues.count < 8 { issues.append("読み取れない項目があります: \(item.lastPathComponent)") }
                continue
            }
            if info.isSymbolicLink {
                continue
            }
            if info.isRegularFile, identities.insert(info.identity).inserted {
                let next = addingApplicationStorageBytes(bytes, info.logicalBytes)
                if next == UInt64.max, bytes != UInt64.max { issues.append("容量の合計が表現可能な上限を超えました。") }
                bytes = next
            }
        }

        while accountedEnumerationErrors < enumerationErrors.count {
            budget.recordError()
            accountedEnumerationErrors += 1
        }
        issues.append(contentsOf: enumerationErrors.names.map { "読み取れない項目があります: \($0)" })

        let status = budget.stopStatus ?? (issues.isEmpty ? .complete : .partial)
        return makeRow(candidate: candidate, scope: scope, path: path, bytes: bytes,
                       entries: entries, status: status, issues: issues)
    }

    private static func makeRow(candidate: StorageAssociatedFolder, scope: ApplicationStorageScope,
                                path: String, bytes: UInt64, entries: Int,
                                status: ApplicationStorageRowStatus, issues: [String]) -> ApplicationStorageRow {
        ApplicationStorageRow(scope: scope, name: candidate.name, path: path,
                              evidence: candidate.evidence, confirmed: candidate.confirmed,
                              logicalBytes: bytes, status: status, scannedEntries: entries,
                              issues: Array(issues.prefix(8)))
    }

    private static func unscannedRow(candidate: StorageAssociatedFolder, scope: ApplicationStorageScope,
                                     path: String, stop: ApplicationStorageRowStatus) -> ApplicationStorageRow {
        let message = stop == .cancelled ? "中止されたため、この場所は未走査です。" : "走査上限に達したため、この場所は未走査です。"
        return ApplicationStorageRow(scope: scope, name: candidate.name, path: path,
                                     evidence: candidate.evidence, confirmed: candidate.confirmed,
                                     logicalBytes: 0, status: stop, scannedEntries: 0, issues: [message])
    }
}

private struct ScanBudget {
    let limits: ApplicationStorageLimits
    let startedAt: TimeInterval
    let isCancelled: @Sendable () -> Bool
    var entries = 0
    var errors = 0
    var stopStatus: ApplicationStorageRowStatus?

    mutating func consumeEntry() {
        entries += 1
        _ = evaluateStop()
    }

    mutating func recordError() {
        errors += 1
        _ = evaluateStop()
    }

    mutating func evaluateStop() -> ApplicationStorageRowStatus? {
        if stopStatus != nil { return stopStatus }
        if isCancelled() { stopStatus = .cancelled }
        else if entries >= limits.maximumEntries || errors >= limits.maximumErrors ||
                    ProcessInfo.processInfo.systemUptime - startedAt >= limits.maximumDuration {
            stopStatus = .limitReached
        }
        return stopStatus
    }
}

private struct ApplicationFileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

private struct ApplicationStorageFileInfo {
    let identity: ApplicationFileIdentity
    let logicalBytes: UInt64
    let isDirectory: Bool
    let isRegularFile: Bool
    let isSymbolicLink: Bool
}

private final class ApplicationEnumerationErrors: @unchecked Sendable {
    private let maximumNames: Int
    private(set) var count = 0
    private(set) var names: [String] = []

    init(maximumNames: Int) { self.maximumNames = maximumNames }

    func record(_ name: String) {
        count += 1
        if names.count < maximumNames { names.append(name) }
    }
}

private func applicationStorageFileInfo(_ path: String) -> ApplicationStorageFileInfo? {
    var value = stat()
    guard lstat(path, &value) == 0 else { return nil }
    let kind = value.st_mode & S_IFMT
    return ApplicationStorageFileInfo(
        identity: ApplicationFileIdentity(device: UInt64(value.st_dev), inode: UInt64(value.st_ino)),
        logicalBytes: UInt64(max(0, value.st_size)),
        isDirectory: kind == S_IFDIR,
        isRegularFile: kind == S_IFREG,
        isSymbolicLink: kind == S_IFLNK
    )
}

private func normalizedApplicationStoragePath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
}

private func applicationStorageContains(parent: String, child: String) -> Bool {
    parent == child || (parent != "/" && child.hasPrefix(parent + "/"))
}

private func relatedCandidateRejection(path: String, homeDirectory: URL) -> String? {
    let homeLibrary = homeDirectory.standardizedFileURL.appendingPathComponent("Library", isDirectory: true)
    let allowedBases = [
        homeLibrary.appendingPathComponent("Application Support", isDirectory: true),
        homeLibrary.appendingPathComponent("Caches", isDirectory: true),
        homeLibrary.appendingPathComponent("Preferences", isDirectory: true),
        homeLibrary.appendingPathComponent("Saved Application State", isDirectory: true),
        homeLibrary.appendingPathComponent("Containers", isDirectory: true),
        homeLibrary.appendingPathComponent("HTTPStorages", isDirectory: true),
        homeLibrary.appendingPathComponent("WebKit", isDirectory: true),
        URL(fileURLWithPath: "/Library/Application Support", isDirectory: true),
        URL(fileURLWithPath: "/Library/Caches", isDirectory: true),
        URL(fileURLWithPath: "/Library/Preferences", isDirectory: true)
    ].map(normalizedApplicationStoragePath)
    let candidate = normalizedApplicationStoragePath(URL(fileURLWithPath: path))
    guard let base = allowedBases.first(where: { applicationStorageContains(parent: $0, child: candidate) && $0 != candidate }) else {
        return "標準Library領域の直下候補ではないため、安全のため走査していません。"
    }
    guard !applicationStoragePathContainsSymbolicLink(base: base, candidate: candidate) else {
        return "シンボリックリンクを経由する候補の参照先は、安全のため走査していません。"
    }
    return nil
}

private func applicationStoragePathContainsSymbolicLink(base: String, candidate: String) -> Bool {
    var current = base
    if applicationStorageIsSymbolicLink(current) { return true }
    let relative = candidate.dropFirst(base.count).drop(while: { $0 == "/" })
    for component in relative.split(separator: "/") {
        current += "/" + component
        if applicationStorageIsSymbolicLink(current) { return true }
    }
    return false
}

private func applicationStorageIsSymbolicLink(_ path: String) -> Bool {
    var value = stat()
    guard lstat(path, &value) == 0 else { return false }
    return value.st_mode & S_IFMT == S_IFLNK
}

private func addingApplicationStorageBytes(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    return overflow ? UInt64.max : result
}

private func sumWithoutOverflow<S: Sequence>(_ values: S) -> UInt64 where S.Element == UInt64 {
    values.reduce(0, addingApplicationStorageBytes)
}
