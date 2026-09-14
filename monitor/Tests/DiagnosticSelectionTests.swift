import Foundation
import SwiftUI
import AppKit

private func selectionExpect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "AIBOU.DiagnosticSelectionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

func runDiagnosticSelectionTests() throws {
    let causes = DiagnosticCatalog.causes
    try selectionExpect(Set(causes.map(\.id)).count == causes.count, "cause IDs are unique")
    try selectionExpect(Set(DiagnosticCatalog.symptoms.map(\.id)).count == DiagnosticCatalog.symptoms.count, "symptom IDs are unique")
    try selectionExpect(causes.filter(\.isAutomatic).count == 8, "only eight observable conditions may be checked automatically")
    for symptom in DiagnosticCatalog.symptoms {
        try selectionExpect(!symptom.causeIDs.isEmpty && !symptom.title.isEmpty, "every symptom needs causes and a title")
        try selectionExpect(Set(symptom.causeIDs).count == symptom.causeIDs.count, "symptoms must not contain duplicate cause references")
        try selectionExpect(symptom.causeIDs.allSatisfy { DiagnosticCatalog.causesByID[$0] != nil }, "no dangling references")
    }
    let symptomIDs = Set(DiagnosticCatalog.symptoms.map(\.id))
    let causeIDs = Set(causes.map(\.id))
    try selectionExpect(symptomIDs.isDisjoint(with: causeIDs), "symptoms cannot reuse cause identities")
    try selectionExpect(DiagnosticCatalog.symptoms.allSatisfy { $0.id.hasPrefix("symptom.") }, "all symptoms must be explicitly defined")
    let automaticTitles = Set(causes.filter(\.isAutomatic).map(\.title))
    try selectionExpect(DiagnosticCatalog.symptoms.allSatisfy { !automaticTitles.contains($0.title) }, "internal observation headings cannot become symptom cards")
    try selectionExpect(Set(DiagnosticCatalog.symptoms.flatMap(\.causeIDs)) == causeIDs, "removing cause cards must preserve access to every cause from symptom details")
    let all = DiagnosticPresentation(results: [:], selection: DiagnosticCauseSelection(), selectedSymptoms: []).symptoms(in: .all)
    try selectionExpect(all.contains { $0.id == "symptom.save-update-failure" } && all.contains { $0.id == "symptom.general-slowness" }, "all lists concrete user-visible failures")
    try selectionExpect(!all.contains { ["storage-low", "cpu-sustained-busy", "swap-allocated", "memory-pressure", "blocked-vent"].contains($0.id) }, "cause-derived cards must not appear in all")
    let heat = DiagnosticCatalog.causesByID["thermal-pressure"]!
    let blockedVent = DiagnosticCatalog.causesByID["thermal-pressure.cause.0"]!
    var selection = DiagnosticCauseSelection()
    func result(_ state: DiagnosticState) -> [String: DiagnosticResult] {
        [heat.id: DiagnosticResult(id: heat.id, state: state, evidence: [])]
    }
    try selectionExpect(selection.isChecked(heat, results: result(.matched)), "matching observation turns on auto checkbox")
    for state in [DiagnosticState.notMatched, .observing, .unknown, .manual] {
        try selectionExpect(!selection.isChecked(heat, results: result(state)), "only matched is auto checked: \(state)")
    }
    try selectionExpect(!selection.isChecked(heat, results: [:]), "missing result is not a match")
    try selectionExpect(!selection.isChecked(blockedVent, results: result(.matched)), "heat does not prove blocked vents")
    selection.set(false, for: heat)
    try selectionExpect(!selection.isChecked(heat, results: result(.matched)), "manual off wins over matching observation")
    try selectionExpect(selection.manualValue(for: heat) == false, "explicit false must survive")
    selection.set(true, for: heat)
    try selectionExpect(selection.isChecked(heat, results: result(.unknown)), "manual on survives missing/stopped observations")
    selection.followObservation(for: heat)
    try selectionExpect(!selection.isChecked(heat, results: result(.unknown)), "return to automatic resumes missing-state behavior")
    try selectionExpect(selection.isChecked(heat, results: result(.matched)), "return to automatic resumes live matching")
    try selectionExpect(!selection.isChecked(heat, results: result(.notMatched)), "recovery removes automatic checkbox")

    let selected = Set(["symptom.wifi-no-network"])
    let autoPresentation = DiagnosticPresentation(results: result(.matched), selection: selection, selectedSymptoms: selected)
    let current = Set(autoPresentation.symptoms(in: .current).map(\.id))
    try selectionExpect(current.contains("symptom.hot-body") && current.contains("symptom.general-slowness"), "shared automatic cause includes multiple symptoms")
    try selectionExpect(!current.contains("symptom.wifi-no-network"), "selected symptom alone is not a current candidate")
    try selectionExpect(Set(autoPresentation.symptoms(in: .selected).map(\.id)) == selected, "selected tab depends only on symptom selection")
    try selectionExpect(autoPresentation.symptoms(in: .all).count == DiagnosticCatalog.symptoms.count, "all tab lists symptoms")
    try selectionExpect(autoPresentation.causes(in: .automatic).allSatisfy(\.isAutomatic), "automatic tab lists only automatic causes")
    try selectionExpect(autoPresentation.causes(in: .manual).allSatisfy { !$0.isAutomatic }, "manual tab lists only manual causes")
    try selectionExpect(autoPresentation.causes(in: .automatic).count + autoPresentation.causes(in: .manual).count == causes.count, "cause tabs partition complete catalog")
    try selectionExpect(autoPresentation.symptoms(in: .manual).isEmpty && autoPresentation.causes(in: .all).isEmpty, "symptom and cause tabs stay separate")
    try selectionExpect(autoPresentation.symptoms(in: .all, search: "吸排気口の閉塞").contains { $0.id == "symptom.hot-body" }, "symptoms searchable through cause title")
    try selectionExpect(autoPresentation.symptoms(in: .all, category: "ネットワーク").allSatisfy { $0.category == "ネットワーク" }, "category filter applies")
    try selectionExpect(autoPresentation.causes(in: .manual, search: "存在しないテスト項目").isEmpty, "empty search result")

    selection.set(false, for: heat)
    var presentation = DiagnosticPresentation(results: result(.matched), selection: selection, selectedSymptoms: [])
    try selectionExpect(presentation.symptoms(in: .current).isEmpty, "manual off removes auto candidate from current tab")
    selection.set(true, for: blockedVent)
    presentation = DiagnosticPresentation(results: [:], selection: selection, selectedSymptoms: [])
    try selectionExpect(Set(presentation.symptoms(in: .current).map(\.id)) == Set(DiagnosticCatalog.symptoms.filter { $0.causeIDs.contains(blockedVent.id) }.map(\.id)), "manual cause can add an unselected symptom to current tab")
    selection.set(false, for: blockedVent)
    try selectionExpect(!selection.isChecked(blockedVent, results: [:]), "manual candidate can be unchecked")
    selection.reset()
    try selectionExpect(selection.isEmpty && selection.isChecked(heat, results: result(.matched)), "reset clears overrides and restores auto evaluation")
    print("Diagnostic symptom/cause selection tests passed (five tabs, overrides, shared causes, missing data).")
}

@MainActor
func renderDiagnosticsPreviews(to directory: URL) async throws {
    _ = NSApplication.shared
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let archive = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-diagnostic-preview-\(UUID())")
    let store = MonitorStore(directory: archive)
    store.pause()
    store.diagnosticSymptoms.insert("symptom.wifi-no-network")
    store.diagnosticCauseSelection.set(true, for: DiagnosticCatalog.causesByID["thermal-pressure"]!)
    func render<V: View>(_ view: V, name: String, width: CGFloat = 1120, height: CGFloat = 900) throws {
        let hosting = NSHostingView(rootView: view.frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw ConsultationError.message("diagnostic preview unavailable") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw ConsultationError.message("diagnostic PNG unavailable") }
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }
    for (index, filter) in DiagnosticFilter.allCases.enumerated() {
        try render(ScrollView { DiagnosticsView(store: store, initialFilter: filter) }, name: "diagnostics-\(index)")
    }
    try render(DiagnosticSymptomDetail(symptom: DiagnosticCatalog.symptoms.first!, store: store), name: "diagnostics-detail", width: 840, height: 700)
    store.shutdown()
    await withCheckedContinuation { continuation in store.afterPendingSaves { continuation.resume() } }
    try? FileManager.default.removeItem(at: archive)
    print("Synthetic diagnostics previews rendered: five tabs and symptom detail.")
}
