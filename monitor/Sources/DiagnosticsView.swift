import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var store: MonitorStore
    @State private var search = ""
    @State private var filter: DiagnosticFilter
    @State private var category = "すべての分類"
    @State private var inspected: DiagnosticSymptom?

    init(store: MonitorStore, initialFilter: DiagnosticFilter = .all) {
        self.store = store
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { timeline in
            let results = Dictionary(uniqueKeysWithValues: store.diagnosticResults(now: timeline.date).map { ($0.id, $0) })
            let presentation = DiagnosticPresentation(results: results, selection: store.diagnosticCauseSelection,
                                                     selectedSymptoms: store.diagnosticSymptoms)
            let selectedCategory = category == "すべての分類" ? nil : category
            let symptoms = presentation.symptoms(in: filter, search: search, category: selectedCategory)
            let causes = presentation.causes(in: filter, search: search, category: selectedCategory)
            let checked = presentation.checkedCauseIDs
            VStack(alignment: .leading, spacing: 16) {
                Label("このMacの状態チェック", systemImage: "checklist").font(.title2.bold())
                    .monitorCircuitExclusion()
                Text("気になる症状を選び、詳細から原因候補を確認できます。症状の選択と原因候補のチェックは別々に管理します。")
                    .monitorCircuitExclusion()
                HStack(spacing: 18) {
                    Text("選択した症状 \(store.diagnosticSymptoms.count)")
                    Text("チェック中の原因候補 \(checked.count)")
                    Text("自動条件に該当 \(results.filter { $0.value.state == .matched }.count)")
                }.font(.callout.monospacedDigit())
                    .monitorCircuitExclusion()
                Text("原因候補のチェックは故障や原因の確定ではありません。自動判定を手動で変更すると、その選択を保持します。「自動に戻す」で観測に追従します。チェックは起動中のみ保持します。")
                    .font(.caption).foregroundStyle(.secondary)
                    .monitorCircuitExclusion()
                if !store.isRunning {
                    Label("監視停止中 — 自動判定は情報不足です。手動の選択は保持しています。", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                        .monitorCircuitExclusion()
                }
                HStack {
                    TextField("症状・原因・対処法を検索", text: $search).textFieldStyle(.roundedBorder)
                    Picker("分類", selection: $category) {
                        Text("すべての分類").tag("すべての分類")
                        ForEach(Array(Set(DiagnosticCatalog.symptoms.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                    }.frame(width: 240)
                }
                .monitorCircuitExclusion()
                Picker("表示する項目", selection: $filter) {
                    ForEach(DiagnosticFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                    .monitorCircuitExclusion()
                HStack {
                    Text(filter.showsCauses ? "原因候補 \(causes.count)件" : "症状 \(symptoms.count)件")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("手動のチェックをリセット") {
                        store.diagnosticSymptoms.removeAll()
                        store.diagnosticChecks.removeAll()
                        store.diagnosticCauseSelection.reset()
                    }.disabled(store.diagnosticSymptoms.isEmpty && store.diagnosticChecks.isEmpty && store.diagnosticCauseSelection.isEmpty)
                        .help("症状と手動チェックを解除し、自動対応の原因候補は観測結果に戻します。")
                }
                .monitorCircuitExclusion()
                Text(filterExplanation).font(.caption).foregroundStyle(.secondary)
                    .monitorCircuitExclusion()
                if symptoms.isEmpty && causes.isEmpty {
                    Text("該当する項目はありません。検索や分類を変更するか、「すべて」から症状を選んでください。項目がないことは正常の証明ではありません。")
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .monitorCircuitExclusion()
                }
                LazyVStack(alignment: .leading, spacing: 12) {
                    if filter.showsCauses {
                        ForEach(causes) { cause in
                            DiagnosticCauseCard(cause: cause, result: results[cause.context.id], store: store)
                        }
                    } else {
                        ForEach(symptoms) { symptom in
                            symptomCard(symptom, checked: checked)
                        }
                    }
                }
            }.padding(22)
        }
        .sheet(item: $inspected) { symptom in
            DiagnosticSymptomDetail(symptom: symptom, store: store)
        }
    }

    private var filterExplanation: String {
        switch filter {
        case .all: return "ユーザーから見える不具合・症状の一覧です。「詳細」で原因候補を開きます。"
        case .current: return "原因候補に1つ以上チェックが付いている症状です。症状自体を選択していなくても表示します。"
        case .selected: return "「この症状がある」を手動で選択した症状です。原因候補のチェックとは連動しません。"
        case .automatic: return "観測結果に追従できる原因候補です。未取得・古い値・継続確認中は自動でチェックしません。"
        case .manual: return "観測だけでは判定できない原因候補です。確認した内容に応じて手動でチェックしてください。"
        }
    }

    private func symptomCard(_ symptom: DiagnosticSymptom, checked: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(symptom.category).font(.caption).foregroundStyle(.secondary)
            Text(symptom.title).font(.headline)
            Text(symptom.examples.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("この症状がある", isOn: diagnosticMembership(symptom.id, in: $store.diagnosticSymptoms))
                    .toggleStyle(.checkbox).accessibilityLabel("\(symptom.title): この症状がある")
                Spacer()
                Text("原因候補 \(symptom.causeIDs.filter { checked.contains($0) }.count) / \(symptom.causeIDs.count) チェック中")
                    .font(.caption).foregroundStyle(.secondary)
                Button("詳細") { inspected = symptom }.accessibilityLabel("\(symptom.title)の原因候補を開く")
            }
        }.padding(16).monitorCard(cornerRadius: 10)
    }
}

struct DiagnosticSymptomDetail: View {
    let symptom: DiagnosticSymptom
    @ObservedObject var store: MonitorStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(symptom.title).font(.title2.bold())
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .monitorCircuitExclusion()
            Toggle("この症状がある", isOn: diagnosticMembership(symptom.id, in: $store.diagnosticSymptoms))
                .toggleStyle(.checkbox)
                .monitorCircuitExclusion()
            Text("原因候補のチェックと症状の選択は独立しています。同じ原因候補のチェックは、ほかの症状や原因一覧にも反映されます。")
                .font(.caption).foregroundStyle(.secondary)
                .monitorCircuitExclusion()
            ScrollView {
                TimelineView(.periodic(from: .now, by: 2)) { timeline in
                    let results = Dictionary(uniqueKeysWithValues: store.diagnosticResults(now: timeline.date).map { ($0.id, $0) })
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(symptom.causeIDs.compactMap { DiagnosticCatalog.causesByID[$0] }) { cause in
                            DiagnosticCauseCard(cause: cause, result: results[cause.context.id], store: store)
                        }
                    }
                }
            }
        }.padding(22).frame(width: 840, height: 700).monitorSurface()
    }
}

private struct DiagnosticCauseCard: View {
    let cause: DiagnosticCause
    let result: DiagnosticResult?
    @ObservedObject var store: MonitorStore

    private var checked: Binding<Bool> {
        Binding(get: {
            store.diagnosticCauseSelection.isChecked(cause, results: result.map { [$0.id: $0] } ?? [:])
        }, set: { store.diagnosticCauseSelection.set($0, for: cause) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Toggle(cause.title, isOn: checked).toggleStyle(.checkbox).font(.headline)
                    .accessibilityLabel(cause.accessibilityLabel)
                Spacer()
                Text(cause.isAutomatic ? "自動判定対応" : "手動判定").font(.caption).foregroundStyle(.secondary)
            }
            if !cause.isAutomatic {
                Text(cause.contextLabel).font(.caption).foregroundStyle(.secondary)
            }
            if cause.isAutomatic {
                HStack {
                    let overridden = store.diagnosticCauseSelection.manualValue(for: cause) != nil
                    Text(overridden ? "手動で\(checked.wrappedValue ? "チェック" : "解除")・観測への追従を停止中" : "観測結果に追従中")
                        .font(.caption)
                    Spacer()
                    if overridden {
                        Button("自動に戻す") { store.diagnosticCauseSelection.followObservation(for: cause) }.font(.caption)
                    }
                }
                Text("観測結果: \(result?.state.title ?? DiagnosticState.unknown.title)")
                    .font(.caption).foregroundStyle(result?.state == .matched ? Color.orange : Color.secondary)
            } else {
                Text("手動で確認する候補です。チェックしても観測結果や原因の確度は変わりません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("根拠・確認・対処法") {
                VStack(alignment: .leading, spacing: 12) {
                    if cause.isAutomatic, let result {
                        ForEach(result.evidence) { evidence in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(evidence.condition, systemImage: evidence.met == true ? "checkmark.circle" : evidence.met == false ? "minus.circle" : "questionmark.circle")
                                Text(evidence.detail).foregroundStyle(.secondary)
                                if let source = evidence.source { Text("取得元: \(source)").foregroundStyle(.secondary) }
                                if let date = evidence.recordedAt {
                                    Text("取得: \(date.formatted(date: .abbreviated, time: .standard))").foregroundStyle(.secondary)
                                }
                            }.font(.caption)
                        }
                    }
                    Text("この確認対象に共通する確認項目").font(.subheadline.bold())
                    ForEach(Array(cause.context.checks.enumerated()), id: \.offset) { index, item in
                        Toggle(item, isOn: diagnosticMembership("\(cause.context.id).\(index)", in: $store.diagnosticChecks))
                            .toggleStyle(.checkbox).font(.caption)
                    }
                    Text("上のチェックは同じ確認対象の原因カードで共有する作業記録です。原因候補や症状の選択には影響しません。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("対処法").font(.subheadline.bold())
                    ForEach(cause.context.actions, id: \.self) { Text("・\($0)").font(.caption) }
                    Text("判定の限界: \(cause.context.limitation)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        ForEach(Array(cause.context.sources.enumerated()), id: \.offset) { index, source in
                            if let url = URL(string: source) { Link("Apple公式資料 \(index + 1)", destination: url).font(.caption) }
                        }
                    }
                }.padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .monitorCard(cornerRadius: 10)
    }
}

private func diagnosticMembership(_ key: String, in set: Binding<Set<String>>) -> Binding<Bool> {
    Binding(get: { set.wrappedValue.contains(key) }, set: { value in
        if value { set.wrappedValue.insert(key) } else { set.wrappedValue.remove(key) }
    })
}
