import AppKit
import Foundation

struct LauncherApplication: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let bundleID: String
    var id: String { url.path }

    func matches(_ query: String) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || name.localizedStandardContains(text) || bundleID.localizedStandardContains(text)
    }
}

struct ApplicationScan: Sendable {
    var applications: [LauncherApplication] = []
    var notes: [String] = []
}

enum ApplicationCatalog {
    static var defaultRoots: [URL] {
        ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
         "/System/Applications", "/System/Library/CoreServices/Applications"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func application(at location: URL, includeBackground: Bool = false) -> LauncherApplication? {
        let url = location.resolvingSymlinksInPath().standardizedFileURL
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url), let info = bundle.infoDictionary,
              info["CFBundlePackageType"] as? String == "APPL",
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        if !includeBackground {
            for key in ["LSUIElement", "LSBackgroundOnly"] {
                if let value = info[key] as? NSNumber, value.boolValue { return nil }
                if let value = info[key] as? String, ["1", "true", "yes"].contains(value.lowercased()) { return nil }
            }
        }
        let localized = bundle.localizedInfoDictionary
        let names = [localized?["CFBundleDisplayName"] as? String, info["CFBundleDisplayName"] as? String,
                     localized?["CFBundleName"] as? String, info["CFBundleName"] as? String]
        let name = names.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            ?? url.deletingPathExtension().lastPathComponent
        return LauncherApplication(url: url, name: name, bundleID: bundle.bundleIdentifier ?? "")
    }

    /// Scan known application directories, never recurse into an app's embedded helpers.
    static func scan(roots: [URL], additional: [URL], maximumEntries: Int = 20_000) -> ApplicationScan {
        let fm = FileManager.default
        var result = ApplicationScan()
        var found: [String: LauncherApplication] = [:]
        var visited = 0
        var incomplete = false
        for root in roots {
            if !fm.fileExists(atPath: root.path) { continue }
            guard let items = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in
                    incomplete = true; return true
                }) else { incomplete = true; continue }
            while let url = items.nextObject() as? URL {
                visited += 1
                if visited > maximumEntries { incomplete = true; break }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                let traversable = values?.isDirectory == true && values?.isSymbolicLink != true
                if url.pathExtension.lowercased() == "app" {
                    if traversable { items.skipDescendants() }
                    if let app = application(at: url) { found[app.id] = app }
                } else if traversable && (items.level >= 8 || values?.isPackage == true) {
                    items.skipDescendants()
                    if items.level >= 8 { incomplete = true }
                }
            }
            if visited > maximumEntries { break }
        }
        for url in additional {
            if let app = application(at: url, includeBackground: true) { found[app.id] = app }
            else if result.notes.count < 5 { result.notes.append("追加したアプリを読み込めません: \(url.lastPathComponent)") }
        }
        if incomplete { result.notes.append("一部の場所は読み取れないか探索上限に達しました。表示されないアプリは「アプリを追加」から選択できます。") }
        result.applications = found.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return result
    }
}

@MainActor
final class ApplicationLauncher: ObservableObject {
    typealias Opener = (URL, @escaping (Error?) -> Void) -> Void
    @Published private(set) var applications: [LauncherApplication] = []
    @Published private(set) var loading = false
    @Published private(set) var launching: Set<String> = []
    @Published private(set) var running: Set<String> = []
    @Published private(set) var notes: [String] = []
    @Published private(set) var message = ""
    @Published private(set) var error = ""
    private let preferences: UserDefaults
    private let roots: [URL]
    private let opener: Opener
    private let additionalKey = "launcher.additionalApplicationPaths"
    private var hasLoaded = false

    init(preferences: UserDefaults = .standard, roots: [URL] = ApplicationCatalog.defaultRoots, opener: Opener? = nil) {
        self.preferences = preferences; self.roots = roots
        self.opener = opener ?? { url, completion in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.allowsRunningApplicationSubstitution = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in completion(error) }
        }
    }

    func loadIfNeeded() async { if !hasLoaded { await refresh() }; updateRunning() }

    func refresh() async {
        guard !loading else { return }
        loading = true; error = ""
        let roots = roots
        let additional = (preferences.stringArray(forKey: additionalKey) ?? []).map { URL(fileURLWithPath: $0) }
        let result = await Task.detached(priority: .utility) { ApplicationCatalog.scan(roots: roots, additional: additional) }.value
        applications = result.applications; notes = result.notes
        loading = false; hasLoaded = true
        updateRunning()
    }

    func add(_ url: URL) async {
        guard !loading else { return }
        guard ApplicationCatalog.application(at: url, includeBackground: true) != nil else {
            error = "起動可能な.appを選択してください。"; return
        }
        var paths = preferences.stringArray(forKey: additionalKey) ?? []
        // Keep the selected alias so versioned installations can retarget it after upgrades.
        let selectedPath = url.standardizedFileURL.path
        if !paths.contains(selectedPath) { paths.append(selectedPath); preferences.set(paths, forKey: additionalKey) }
        await refresh()
    }

    func updateRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path })
    }

    func open(_ app: LauncherApplication) {
        guard !launching.contains(app.id) else { return }
        error = ""; message = ""
        guard ApplicationCatalog.application(at: app.url, includeBackground: true) != nil else {
            error = "\(app.name)を開けません。移動・削除されていないか確認し、一覧を更新してください。"; return
        }
        launching.insert(app.id)
        opener(app.url) { [weak self] failure in
            DispatchQueue.main.async {
                guard let self else { return }
                self.launching.remove(app.id)
                if let failure { self.error = "\(app.name)を開けません: \(failure.localizedDescription)" }
                else { self.message = "\(app.name)を開きました。" }
                self.updateRunning()
            }
        }
    }
}
