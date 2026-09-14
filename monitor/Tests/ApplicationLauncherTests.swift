import AppKit
import Foundation
import SwiftUI

private func launcherExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "AIBOU.LauncherTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private func makeLauncherFixture(_ url: URL, name: String, bundleID: String = "test.aibou.launcher", background: Bool = false) throws {
    let contents = url.appendingPathComponent("Contents")
    let executable = contents.appendingPathComponent("MacOS/fixture")
    try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleExecutable": "fixture", "CFBundleName": name,
                               "CFBundleIdentifier": bundleID, "LSUIElement": background]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
}

@MainActor
func runApplicationLauncherTests() async throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("aibou-launcher-tests-\(UUID())")
    defer { try? fm.removeItem(at: directory) }
    let root = directory.appendingPathComponent("Applications")
    let first = root.appendingPathComponent("First.app")
    let duplicateID = root.appendingPathComponent("Utilities/Second.app")
    let outside = directory.appendingPathComponent("Elsewhere/Third.app")
    try makeLauncherFixture(first, name: "First; $(touch must-not-execute)")
    try makeLauncherFixture(duplicateID, name: "Second")
    try makeLauncherFixture(outside, name: "Third")
    try makeLauncherFixture(first.appendingPathComponent("Contents/Helpers/Nested.app"), name: "Nested")
    try makeLauncherFixture(root.appendingPathComponent("Agent.app"), name: "Agent", background: true)
    try makeLauncherFixture(root.appendingPathComponent(".Hidden.app"), name: "Hidden")
    try fm.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: first)
    try fm.createSymbolicLink(at: root.appendingPathComponent("Loop"), withDestinationURL: root)
    try Data("not an application".utf8).write(to: root.appendingPathComponent("Document.app"))
    let missing = directory.appendingPathComponent("Missing.app")
    let result = ApplicationCatalog.scan(roots: [root, root], additional: [outside, missing])
    try launcherExpect(result.applications.count == 3, "skip embedded/background/hidden/invalid apps, deduplicate aliases, retain separate installations: \(result.applications.map(\.id)), second=\(String(describing: ApplicationCatalog.application(at: duplicateID))), notes=\(result.notes)")
    try launcherExpect(result.notes.count == 1, "missing manual app is reported")
    try launcherExpect(result.applications.contains { $0.id == outside.resolvingSymlinksInPath().path }, "manual apps outside default roots are included")
    try launcherExpect(ApplicationCatalog.scan(roots: [root], additional: [], maximumEntries: 1).notes.count == 1, "scan limit must expose partial results")
    let app = try result.applications.first { $0.id == first.resolvingSymlinksInPath().path }.unwrapLauncher("first app missing")
    try launcherExpect(app.matches(" FIRST ") && app.matches("TEST.AIBOU") && !app.matches("unrelated"), "localized name and bundle ID search")
    let emptyName = directory.appendingPathComponent("EmptyName.app")
    try makeLauncherFixture(emptyName, name: "  ")
    try launcherExpect(ApplicationCatalog.application(at: emptyName)?.name == "EmptyName", "blank bundle names fall back to filename")

    let suite = "test.aibou.launcher.\(UUID())"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    var opened: [URL] = []
    var completion: ((Error?) -> Void)?
    let model = ApplicationLauncher(preferences: preferences, roots: [root], opener: { url, callback in
        opened.append(url); completion = callback
    })
    await model.loadIfNeeded()
    await model.add(outside)
    await model.add(outside)
    try launcherExpect(model.applications.count == 3, "manual addition persists without duplicates")
    let restored = ApplicationLauncher(preferences: preferences, roots: [])
    await restored.loadIfNeeded()
    try launcherExpect(restored.applications.map(\.id) == [outside.resolvingSymlinksInPath().path], "manual app selection restored without touching real preferences")
    let manualAlias = directory.appendingPathComponent("Stable.app")
    try fm.createSymbolicLink(at: manualAlias, withDestinationURL: outside)
    await restored.add(manualAlias)
    let replacement = directory.appendingPathComponent("Elsewhere/Version2.app")
    try makeLauncherFixture(replacement, name: "Updated")
    try fm.removeItem(at: manualAlias)
    try fm.createSymbolicLink(at: manualAlias, withDestinationURL: replacement)
    try fm.removeItem(at: outside)
    await restored.refresh()
    try launcherExpect(restored.applications.map(\.id) == [replacement.resolvingSymlinksInPath().path], "manual stable symlink follows updated app version")
    model.open(app); model.open(app)
    try launcherExpect(opened.map(\.path) == [first.resolvingSymlinksInPath().path] && model.launching.contains(app.id), "launch exact app URL once, never interpolate a shell command")
    completion?(NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "denied"]))
    try await Task.sleep(nanoseconds: 20_000_000)
    try launcherExpect(model.launching.isEmpty && model.error.contains("denied"), "launch failure clears pending state and is visible")
    model.open(app); completion?(nil)
    try await Task.sleep(nanoseconds: 20_000_000)
    try launcherExpect(model.error.isEmpty && model.message.contains("開きました"), "successful retry shows completion")
    try fm.removeItem(at: first)
    model.open(app)
    try launcherExpect(opened.count == 2 && !model.error.isEmpty, "deleted application never reaches opener")
    print("Application launcher tests passed (no installed applications launched).")
}

private extension Optional {
    func unwrapLauncher(_ message: String) throws -> Wrapped {
        guard let value = self else { throw NSError(domain: "AIBOU.LauncherTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        return value
    }
}

/// Explicit opt-in smoke mode; normal tests never start installed applications.
@MainActor
func runApplicationLaunchSmoke(at fixture: URL) async throws {
    let app = try ApplicationCatalog.application(at: fixture, includeBackground: true).unwrapLauncher("smoke fixture invalid")
    try launcherExpect(app.bundleID.hasPrefix("test.aibou.launcher.smoke."), "smoke mode accepts only dedicated fixture bundles")
    let suite = "test.aibou.launcher.smoke.\(UUID())"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    let launcher = ApplicationLauncher(preferences: preferences, roots: [])
    launcher.open(app)
    for _ in 0..<100 {
        if !launcher.launching.contains(app.id) { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    try launcherExpect(launcher.launching.isEmpty && launcher.error.isEmpty && !launcher.message.isEmpty,
                       "NSWorkspace launch did not succeed: \(launcher.error)")
    try launcherExpect(FileManager.default.fileExists(atPath: fixture.appendingPathComponent("started.txt").path), "fixture never executed")
    try await Task.sleep(nanoseconds: 1_500_000_000)
    print("NSWorkspace real launch passed for disposable fixture; no user applications launched.")
}

@MainActor
func renderApplicationLauncherPreview(to destination: URL) async throws {
    _ = NSApplication.shared
    let suite = "test.aibou.launcher.preview.\(UUID())"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    let launcher = ApplicationLauncher(preferences: preferences, opener: { _, _ in })
    await launcher.loadIfNeeded()
    try launcherExpect(!launcher.applications.isEmpty, "read-only real app discovery returned no apps")
    let view = NSHostingView(rootView: ScrollView { ApplicationLauncherView(launcher: launcher) }
        .frame(width: 1050, height: 850).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
    view.appearance = NSAppearance(named: .aqua)
    view.frame = NSRect(x: 0, y: 0, width: 1050, height: 850)
    view.layoutSubtreeIfNeeded()
    // Let lazy grid tasks obtain icons before caching the offscreen view.
    try await Task.sleep(nanoseconds: 200_000_000)
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NSError(domain: "preview", code: 1) }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "preview", code: 2) }
    try data.write(to: destination)
    print("Launcher preview rendered; discovered \(launcher.applications.count) applications; no applications launched.")
}
