import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var store: MonitorStore
    @State private var search = ""
    @State private var filter = "all"
    @State private var category = "すべての分類"
    @State private var expanded: Set<String> = []

    var body: some View {
        // Refresh freshness even when collection has stopped or stalled.
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let results = store.diagnosticResults(now: Date())
            let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
            let entries = DiagnosticCatalog.cases.filter { entry in
                let result = byID[entry.id]
                let inFilter = filter == "all" ||
                    (filter == "current" && (store.diagnosticSymptoms.contains(entry.id) || result?.state == .matched || result?.state == .observing)) ||
                    (filter == "manual" && entry.rule == .manual) || (filter == "auto" && entry.rule != .manual)
                let text = ([entry.title, entry.category] + entry.symptoms + entry.causes + entry.actions).joined(separator: " ")
                return inFilter && (category == "すべての分類" || entry.category == category) &&
                    (search.isEmpty || text.localizedCaseInsensitiveContains(search))
            }
            VStack(alignment: .leading, spacing: 16) {
                Label("このMacの状態チェック", systemImage: "checklist").font(.title2.bold())
                Text("症状・原因候補・対処法を、現在の観測値と照合します。条件に該当しても故障や原因の確定ではありません。")
                HStack(spacing: 18) {
                    Text("条件該当 \(results.filter { $0.state == .matched }.count)")
                    Text("継続確認 \(results.filter { $0.state == .observing }.count)")
                    Text("情報不足 \(results.filter { $0.state == .unknown }.count)")
                    Text("手動確認 \(results.filter { $0.state == .manual }.count)")
                }.font(.callout.monospacedDigit())
                Text("未取得の項目は正常とは判断しません。「該当せず」は今回の条件だけの結果です。症状と確認済みチェックは起動中のみ保持します。")
                    .font(.caption).foregroundStyle(.secondary)
                if !store.isRunning {
                    Label("監視停止中 — 自動判定は情報不足です。再開すると再評価します。", systemImage: "pause.circle")
                        .foregroundStyle(.orange)
                }
                HStack {
                    TextField("症状・原因・対処法を検索", text: $search).textFieldStyle(.roundedBorder)
                    Picker("分類", selection: $category) {
                        Text("すべての分類").tag("すべての分類")
                        ForEach(Array(Set(DiagnosticCatalog.cases.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                    }.frame(width: 240)
                }
                HStack {
                    Picker("表示するケース", selection: $filter) {
                        Text("すべて").tag("all")
                        Text("今の候補・選択した症状").tag("current")
                        Text("自動判定").tag("auto")
                        Text("手動確認").tag("manual")
                    }.pickerStyle(.segmented)
                    Button("チェックをリセット") { store.diagnosticSymptoms.removeAll(); store.diagnosticChecks.removeAll() }
                        .disabled(store.diagnosticSymptoms.isEmpty && store.diagnosticChecks.isEmpty)
                }
                Text("\(entries.count) / \(DiagnosticCatalog.cases.count) ケース").font(.caption).foregroundStyle(.secondary)
                if entries.isEmpty {
                    Text("この条件で表示する候補はありません。症状がある場合は「すべて」から探してください。故障がないことを示す結果ではありません。")
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                }
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(entries) { entry in
                        if let result = byID[entry.id] { caseCard(entry, result: result) }
                    }
                }
            }.padding(22)
        }
    }

    private func caseCard(_ entry: DiagnosticCase, result: DiagnosticResult) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Toggle("この症状がある", isOn: membership(entry.id, in: $store.diagnosticSymptoms)).toggleStyle(.checkbox)
                    .accessibilityLabel("\(entry.title): この症状がある")
                Spacer()
                Label(result.state.title, systemImage: symbol(result.state))
                    .font(.caption.bold()).foregroundStyle(color(result.state))
            }
            DisclosureGroup(isExpanded: membership(entry.id, in: $expanded)) {
                VStack(alignment: .leading, spacing: 13) {
                    lines("起こりうる症状", entry.symptoms)
                    if !result.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("観測データのチェック（自動）").font(.subheadline.bold())
                            ForEach(result.evidence) { evidence in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: evidence.met == true ? "checkmark.square.fill" : (evidence.met == false ? "square" : "questionmark.square"))
                                        .accessibilityLabel(evidence.met == true ? "条件成立" : (evidence.met == false ? "条件不成立" : "評価不能"))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(evidence.condition)
                                        Text(evidence.detail).foregroundStyle(.secondary)
                                        if let source = evidence.source { Text("取得元: \(source)").foregroundStyle(.secondary) }
                                        if let date = evidence.recordedAt {
                                            Text("取得: \(date.formatted(date: .abbreviated, time: .standard))").foregroundStyle(.secondary)
                                        }
                                    }
                                }.font(.caption)
                            }
                        }
                    }
                    lines("考えられる原因・切り分け", entry.causes)
                    lines("対処法", entry.actions)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("確認を終えた項目（手動）").font(.subheadline.bold())
                        ForEach(Array(entry.checks.enumerated()), id: \.offset) { index, check in
                            Toggle(check, isOn: membership("\(entry.id).\(index)", in: $store.diagnosticChecks)).toggleStyle(.checkbox).font(.caption)
                        }
                        Text("確認済みの記録です。チェックしても自動判定や原因の確度は変わりません。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("判定の限界: \(entry.limitation)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        ForEach(Array(entry.sources.enumerated()), id: \.offset) { index, source in
                            if let url = URL(string: source) { Link("Apple公式資料 \(index + 1)", destination: url).font(.caption) }
                        }
                    }
                }.padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.category) · \(entry.title)").font(.headline)
                    Text(entry.symptoms.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func membership(_ key: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(key) }, set: { value in
            if value { set.wrappedValue.insert(key) } else { set.wrappedValue.remove(key) }
        })
    }
    private func lines(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold())
            ForEach(values, id: \.self) { Text("・\($0)").font(.caption) }
        }
    }
    private func symbol(_ state: DiagnosticState) -> String {
        switch state {
        case .matched: return "checkmark.square.fill"
        case .observing: return "clock"
        case .notMatched: return "square"
        case .unknown: return "questionmark.square"
        case .manual: return "hand.point.up.left"
        }
    }
    private func color(_ state: DiagnosticState) -> Color {
        switch state {
        case .matched: return .orange
        case .observing: return .blue
        case .notMatched, .manual, .unknown: return .secondary
        }
    }
}
