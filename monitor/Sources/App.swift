import SwiftUI
import AppKit
import Charts

@MainActor
final class MonitorDelegate: NSObject, NSApplicationDelegate {
    weak var store: MonitorStore?
    weak var consultation: ConsultationModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        consultation?.disconnect()
        guard let store else { return .terminateNow }
        store.shutdown()
        let cleanup = DispatchGroup()
        cleanup.enter()
        store.afterPendingSaves { cleanup.leave() }
        if let consultation {
            cleanup.enter()
            consultation.afterPendingShutdown { cleanup.leave() }
        }
        cleanup.notify(queue: .main) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { consultation?.disconnect(); store?.shutdown() }
}

#if !AIBOU_INTEGRATED
@main
struct AIBOUMonitorApp: App {
    @NSApplicationDelegateAdaptor(MonitorDelegate.self) private var delegate
    @StateObject private var store = MonitorStore()
    @StateObject private var consultation = ConsultationModel()
    var body: some Scene {
        WindowGroup("AIBOU Monitor") {
            MonitorWindow(store: store, consultation: consultation)
                .frame(minWidth: 1050, minHeight: 660)
                .onAppear { delegate.store = store; delegate.consultation = consultation }
        }
        .defaultSize(width: 1400, height: 900)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
#endif

enum MonitorPresentation {
    case full
    case hardware(MonitorTab)
    case diagnostics
    case applications

    fileprivate var showsSidebar: Bool {
        if case .full = self { return true }
        return false
    }
}

struct MonitorWindow: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var consultation: ConsultationModel
    let presentation: MonitorPresentation
    @StateObject private var launcher = ApplicationLauncher()
    @State private var search = ""
    @State private var sortKey = ""
    @State private var inspected: ReadingRow?
    @State private var showingRelated = false
    @State private var chartMetric = ""
    @State private var showingDiagnostics: Bool
    @State private var showingConsultation: Bool
    @State private var showingApplications: Bool

    init(store: MonitorStore, consultation: ConsultationModel, presentation: MonitorPresentation = .full) {
        self.store = store
        self.consultation = consultation
        self.presentation = presentation

        let arguments = ProcessInfo.processInfo.arguments
        switch presentation {
        case .full:
            _showingDiagnostics = State(initialValue: arguments.contains("--diagnostics"))
            _showingConsultation = State(initialValue: arguments.contains("--consultation"))
            _showingApplications = State(initialValue: arguments.contains("--applications"))
        case .hardware:
            _showingDiagnostics = State(initialValue: false)
            _showingConsultation = State(initialValue: false)
            _showingApplications = State(initialValue: false)
        case .diagnostics:
            _showingDiagnostics = State(initialValue: true)
            _showingConsultation = State(initialValue: false)
            _showingApplications = State(initialValue: false)
        case .applications:
            _showingDiagnostics = State(initialValue: false)
            _showingConsultation = State(initialValue: false)
            _showingApplications = State(initialValue: true)
        }
    }

    private var selectedTab: MonitorTab {
        if case .hardware(let tab) = presentation { return tab }
        return store.selectedTab
    }

    private var panel: PanelReading {
        store.panels[selectedTab] ?? PanelReading(tab: selectedTab,
            metrics: [Metric("awaiting", "基本計測", status: .waiting, source: "AIBOU",
                             detail: selectedTab == .gpu ? "GPUの条件付き指標は下の追加計測で確認します。" : "初回の計測を待っています。")])
    }
    var body: some View {
        Group {
            if presentation.showsSidebar {
                NavigationSplitView {
                    sidebar
                } detail: {
                    detailContent
                }
            } else {
                detailContent
            }
        }
        .onAppear {
            if case .hardware(let tab) = presentation, store.selectedTab != tab {
                store.selectedTab = tab
            }
        }
        .sheet(item: $inspected) { row in
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text(row.name).font(.title2.bold()); Spacer(); Button("閉じる") { inspected = nil } }
                Text(row.note).foregroundStyle(.secondary)
                if let path = row.path { Text(path).font(.caption.monospaced()).textSelection(.enabled) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(row.metrics) { metric in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(metric.label): \(metric.formatted)").font(.headline)
                                Text("\(metric.status.title) · \(metric.source) · \(metric.recordedAt.formatted())").font(.caption).foregroundStyle(.secondary)
                                if !metric.detail.isEmpty { Text(metric.detail).font(.caption).textSelection(.enabled) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }
                }
            }.monitorCircuitExclusion().padding(24).frame(width: 720, height: 570).monitorSurface()
        }
        .sheet(isPresented: $showingRelated) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("\(store.relatedApp) の関連フォルダ").font(.title2.bold()); Spacer(); Button("閉じる") { showingRelated = false } }
                Text("標準保存先とBundle ID等の照合結果。アプリが任意の場所に保存するデータを完全に網羅するものではありません。")
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.relatedFolders.isEmpty { Text("アクセスできる標準保存先を検索しています。結果がない場合もあります。") }
                        ForEach(store.relatedFolders) { folder in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(folder.name).font(.headline)
                                    Text(folder.confirmed ? "確認済み" : "関連候補").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Finder") { reveal(folder.path) }
                                    if presentation.showsSidebar {
                                        Button("この範囲を調査") {
                                            showingRelated = false; store.selectedTab = .storage
                                            var isDirectory: ObjCBool = false
                                            _ = FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory)
                                            let url = URL(fileURLWithPath: folder.path)
                                            store.startScan(root: isDirectory.boolValue ? url : url.deletingLastPathComponent())
                                        }.disabled(store.scan.status == .scanning || store.scan.status == .paused)
                                    }
                                }
                                Text(folder.path).font(.caption.monospaced()).textSelection(.enabled)
                                Text(folder.evidence).font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }
                }
            }.monitorCircuitExclusion().padding(24).frame(width: 860, height: 600).monitorSurface()
        }
    }

    private var sidebar: some View {
        List(selection: Binding<MonitorTab?>(get: { showingDiagnostics || showingConsultation || showingApplications ? nil : store.selectedTab }, set: { if let tab = $0 { store.selectedTab = tab; showingDiagnostics = false; showingConsultation = false; showingApplications = false } })) {
            Button { showingApplications = true; showingConsultation = false; showingDiagnostics = false } label: {
                Label("アプリ", systemImage: "square.grid.2x2").fontWeight(showingApplications ? .bold : .regular)
            }.buttonStyle(.plain).padding(.vertical, 8)
            Button { showingConsultation = true; showingDiagnostics = false; showingApplications = false } label: {
                Label("相談", systemImage: "bubble.left.and.bubble.right").fontWeight(showingConsultation ? .bold : .regular)
            }.buttonStyle(.plain).padding(.vertical, 8)
            Button { showingDiagnostics = true; showingConsultation = false; showingApplications = false } label: {
                Label("状態チェック", systemImage: "checklist").fontWeight(showingDiagnostics ? .bold : .regular)
            }.buttonStyle(.plain).padding(.vertical, 8)
            ForEach(MonitorTab.allCases) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab).padding(.vertical, 5)
            }
        }
        .navigationSplitViewColumnWidth(min: 165, ideal: 185, max: 235)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AIBOU Monitor").font(.headline)
                Text("このMacの観測データ").font(.caption).foregroundStyle(.secondary)
                    #if AIBOU_INTEGRATED
                    Text("部屋に戻っても監視を継続").font(.caption2).foregroundStyle(.secondary)
                    #else
                    Text("画面を閉じると監視を終了").font(.caption2).foregroundStyle(.secondary)
                    #endif
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
                controlBar.monitorCircuitExclusion()
                Divider()
                ScrollView {
                    if showingApplications {
                        ApplicationLauncherView(launcher: launcher, store: store)
                    } else if showingConsultation {
                        ConsultationView(model: consultation, store: store)
                    } else if showingDiagnostics {
                        DiagnosticsView(store: store)
                    } else {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(selectedTab.title, systemImage: selectedTab.symbol).font(.title2.bold())
                            Spacer()
                            if let date = store.lastSample {
                                Text("\(date.formatted(date: .omitted, time: .standard)) 計測")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }.monitorCircuitExclusion()
                        if !store.isRunning {
                            Label("基本監視停止中 — 最後の値を表示。開始済みの追加電力計測は完了する場合があります", systemImage: "pause.circle.fill")
                                .foregroundStyle(.orange).padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).monitorCircuitExclusion()
                        }
                        if selectedTab == .storage { storageBrowser }
                        metricCards(panel.metrics)
                        if !panel.notes.isEmpty { notes(panel.notes) }
                        historyChart
                        if !panel.rows.isEmpty {
                            HStack {
                                Text(selectedTab == .storage ? "プロセス別ディスクI/O" : "詳細一覧").font(.headline)
                                Text("\(panel.rows.count) 件").foregroundStyle(.secondary)
                                Spacer()
                                TextField("名前・PID・値で検索", text: $search).textFieldStyle(.roundedBorder).frame(width: 230)
                                Picker("並べ替え", selection: $sortKey) {
                                    Text("既定順").tag("")
                                    Text("名前順").tag("name")
                                    ForEach(panel.columns) { Text($0.title).tag($0.id) }
                                }.frame(width: 200)
                            }.monitorCircuitExclusion()
                            ReadingGrid(columns: panel.columns, rows: filteredRows(panel.rows), onSelect: { inspected = $0 },
                                        onRelated: showRelated)
                        } else if [.devices, .display].contains(selectedTab) {
                            Text("今回の列挙では表示できる対象がありません。権限制限や接続状態も確認してください。")
                                .foregroundStyle(.secondary).monitorCircuitExclusion()
                        }
                        if selectedTab == .network { networkSection.monitorCircuitExclusion() }
                        if [.gpu, .clock, .thermal].contains(selectedTab) { powerSection.monitorCircuitExclusion() }
                        if selectedTab == .devices, !store.deviceEvents.isEmpty {
                            GroupBox("起動中の接続・切断履歴") {
                                VStack(alignment: .leading) {
                                    ForEach(Array(store.deviceEvents.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.padding(22)
                    }
                }
                Divider()
                HStack {
                    Text(store.message.isEmpty ? "実測・算出・推定・取得不可を区別。項目にポインタを置くと取得元と定義を確認できます。" : store.message)
                        .lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Text(String(format: "収集 %.0f ms", store.samplingMilliseconds)).monospacedDigit()
                }.font(.caption).foregroundStyle(.secondary).padding(10).monitorCircuitExclusion()
            }
            .task(id: selectedTab) { search = ""; sortKey = ""; chartMetric = "" }
        }

    private var controlBar: some View {
        HStack(spacing: 14) {
            Circle().fill(store.isRunning ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(store.isRunning ? "基本監視中" : "基本監視停止中").font(.headline)
            Button {
                if store.isRunning { store.pause() } else { store.start() }
            } label: { Label(store.isRunning ? "基本監視を停止" : "再開", systemImage: store.isRunning ? "pause" : "play") }
            Picker("計測間隔", selection: Binding(get: { store.detailed }, set: { store.setDetailed($0) })) {
                Text("通常 · 2秒").tag(false); Text("詳細 · 1秒").tag(true)
            }.pickerStyle(.segmented).frame(width: 235)
            Spacer()
            Toggle("24時間保存", isOn: Binding(get: { store.historyEnabled }, set: { store.setHistoryEnabled($0) })).toggleStyle(.switch)
            Button("履歴削除") { store.clearHistory() }
        }.padding(14)
    }

    private func metricCards(_ metrics: [Metric]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 195), alignment: .topLeading)], alignment: .leading, spacing: 10) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        Text(metric.label).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 3)
                        Text(metric.status.title).font(.system(size: 10)).foregroundStyle(statusColor(metric.status))
                    }
                    Text(metric.formatted).font(.system(size: 20, weight: .semibold, design: .monospaced)).lineLimit(2)
                    if metric.value == nil && metric.text == nil { Text(metric.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3) }
                }.padding(12).frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .monitorCard(cornerRadius: 8, nativeBorder: true)
                    .help("\(metric.source)\n\(metric.detail)\n計測: \(metric.recordedAt.formatted())\n\(metric.interval.map { "計測区間: \($0)秒" } ?? "")")
            }
        }
    }
    private func notes(_ strings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) { ForEach(strings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) } }.monitorCircuitExclusion()
    }

    @ViewBuilder private var historyChart: some View {
        let available = panel.metrics.filter { metric in
            metric.value != nil && store.history.frames.contains { $0.values["\(panel.tab.rawValue).\(metric.id)"] != nil }
        }
        if !available.isEmpty {
            let selected = available.first { $0.id == chartMetric } ?? preferredHistoryMetric(available)
            let key = "\(panel.tab.rawValue).\(selected.id)"
            let frames = store.history.series(for: key)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("直近24時間の全体集計").font(.headline)
                        Text("10秒ごと / 欠測は接続しません").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Picker("指標", selection: Binding(get: { selected.id }, set: { chartMetric = $0 })) {
                            ForEach(available) { Text($0.label).tag($0.id) }
                        }.frame(width: 235)
                    }
                    if frames.count < 2 { Text("推移の表示には、もう1回の履歴サンプルが必要です。").font(.caption).foregroundStyle(.secondary).frame(height: 75) }
                    else {
                        Chart(frames) { frame in
                            let value = frame.value
                            LineMark(x: .value("時刻", frame.date), y: .value(selected.unit, selected.unit == "B" ? value / 1_073_741_824 : value), series: .value("観測区間", frame.segment))
                                .foregroundStyle(Color.accentColor)
                        }.chartLegend(.hidden).chartYAxisLabel(selected.unit == "B" ? "GiB" : selected.unit).frame(height: 125)
                    }
                }.padding(5)
            }
        }
    }
    private func preferredHistoryMetric(_ available: [Metric]) -> Metric {
        let preferred = ["user", "occupied", "charge_percent", "rxRate", "deviceReadRate", "jitter"]
        return available.first { preferred.contains($0.id) } ?? available[0]
    }

    private var storageBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { store.startScan(root: URL(fileURLWithPath: "/")) } label: { Label("起動ボリュームをスキャン", systemImage: "internaldrive") }
                    .disabled(store.scan.status == .scanning || store.scan.status == .paused)
                Button("フォルダ / ドライブを選択…") { store.chooseScanRoot() }
                    .disabled(store.scan.status == .scanning || store.scan.status == .paused)
                if store.scan.status == .scanning { Button("走査を一時停止") { store.pauseScan() } }
                if store.scan.status == .paused { Button("走査を再開") { store.resumeScan() } }
                if store.scan.status == .scanning || store.scan.status == .paused { Button("走査を中止") { store.cancelScan() } }
                Spacer()
                Button("フルディスクアクセス設定") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                }
            }
            if store.storageLoading { ProgressView("保存済みの階層を読み込み中…") }
            if !store.storagePersistence.isEmpty { Text(store.storagePersistence).font(.caption).foregroundStyle(.secondary) }
            Text("隠しファイル・Library・.app内部を含む階層調査。アクセスできない場所を明示し、外付け・ネットワークドライブは選択したときだけ走査します。")
                .font(.caption).foregroundStyle(.secondary)
            if store.scan.status != .idle {
                HStack {
                    if store.scan.status == .scanning { ProgressView().controlSize(.small) }
                    Text("\(scanStatus(store.scan.status)) · \(store.scan.scannedCount) 項目 · 読み取り問題 \(store.scan.reportedErrorCount) 件")
                    Spacer()
                    Text("\(store.scan.updatedAt.formatted(date: .abbreviated, time: .standard))")
                }.font(.caption.monospacedDigit())
                Text("論理合計 \(bytes(store.scan.totalLogicalBytes)) · 割当済み \(store.scan.totalAllocatedBytes.map(bytes) ?? "未確定")\(store.scan.status == .scanning || store.scan.status == .paused || store.scan.status == .cancelled ? "（途中の集計）" : "")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                HStack {
                    Button("ルート") { store.selectedFolder = store.scan.rootPath }
                    Button("上の階層") {
                        store.selectedFolder = store.parentStorageFolder() ?? store.scan.rootPath
                    }.disabled(store.selectedFolder == store.scan.rootPath)
                    Text(store.selectedFolder ?? store.scan.rootPath).font(.caption.monospaced()).lineLimit(2).textSelection(.enabled)
                }
                let nodes = store.visibleStorageNodes
                if [.scanning, .paused].contains(store.scan.status) { Text("走査中は件数・合計だけを更新します。階層は完了または中止後に表示します。").font(.caption).foregroundStyle(.secondary) }
                if let reason = store.scan.stopReason { Text(reason).font(.caption).foregroundStyle(.orange) }
                if store.storageChildCount > StorageTreeIndex.pageSize {
                    HStack {
                        Button("前の500件") { store.storagePage -= 1 }.disabled(store.storagePage == 0)
                        Text("\(store.storagePage * StorageTreeIndex.pageSize + 1)〜\(min(store.storageChildCount, (store.storagePage + 1) * StorageTreeIndex.pageSize)) / \(store.storageChildCount) 件")
                        Button("次の500件") { store.storagePage += 1 }.disabled((store.storagePage + 1) * StorageTreeIndex.pageSize >= store.storageChildCount)
                    }.font(.caption)
                }
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("名前 / フォルダを開く").frame(width: 290, alignment: .leading)
                            Text("論理サイズ").frame(width: 125, alignment: .trailing)
                            Text("割当済み").frame(width: 125, alignment: .trailing)
                            Text("分類 / 状態").frame(width: 250, alignment: .leading)
                            Spacer()
                        }.font(.caption.bold()).padding(8)
                        Divider()
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(nodes) { node in
                                    HStack(spacing: 12) {
                                        Button {
                                            if node.kind == .directory { store.selectedFolder = node.id }
                                            else { inspectStorage(node) }
                                        } label: {
                                            Label(node.name, systemImage: node.kind == .directory ? "folder" : (node.kind == .symbolicLink ? "link" : "doc"))
                                                .lineLimit(1).frame(width: 290, alignment: .leading)
                                        }.buttonStyle(.plain)
                                        Text(node.kind == .directory && !node.aggregateComplete && node.logicalBytes == 0 ? "未集計" : bytes(node.logicalBytes))
                                            .frame(width: 125, alignment: .trailing)
                                        Text(node.kind == .directory && !node.aggregateComplete && node.logicalBytes == 0 ? "未集計" : (node.allocatedBytes.map(bytes) ?? "—")).frame(width: 125, alignment: .trailing)
                                        Text(node.error ?? ([node.aggregateComplete ? "" : "部分集計"] + node.tags.map(\.name)).filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(node.error == nil ? Color.secondary : Color.orange).lineLimit(2).frame(width: 250, alignment: .leading)
                                        Button("詳細") { inspectStorage(node) }
                                        if node.path.lowercased().hasSuffix(".app") { Button("関連フォルダ") { showRelated(ReadingRow(id: node.id, name: node.name, metrics: [], path: node.path, bundleID: Bundle(path: node.path)?.bundleIdentifier)) } }
                                    }.font(.system(size: 12, design: .monospaced)).padding(.vertical, 7).padding(.horizontal, 8)
                                        .help(node.tags.map { "\($0.name): \($0.reason)" }.joined(separator: "\n"))
                                    Divider().opacity(0.4)
                                }
                            }
                        }.frame(height: 285)
                    }.frame(minWidth: 940)
                }
                if !store.scan.errors.isEmpty {
                    DisclosureGroup("読み取りできなかった場所と理由（先頭20件）") {
                        ForEach(Array(store.scan.errors.prefix(20).enumerated()), id: \.offset) { _, error in
                            Text("\(error.path): \(error.message)").font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else { Text("まだ走査していません。監視の軽さを保つため、ファイル調査は上のボタンで開始します。").foregroundStyle(.secondary) }
        }.padding(14).monitorCard(cornerRadius: 10)
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("プロセス別通信・接続先").font(.headline)
                Spacer()
                if store.networkBusy { ProgressView().controlSize(.small) }
                Button("1秒間の詳細を計測") { store.collectNetwork() }.disabled(store.networkBusy || !store.isRunning)
            }
            if let detail = store.networkDetail {
                Text("\(detail.capturedAt.formatted()) の計測結果。再計測するまで更新されません。").font(.caption).foregroundStyle(.secondary)
                metricCards(detail.metrics); notes(detail.notes)
                ReadingGrid(columns: detail.columns, rows: detail.rows, onSelect: { inspected = $0 }, onRelated: showRelated)
            } else { Text("nettopでプロセス別の送受信量・接続先・TCP RTT等を計測します。接続先は終了後に保存しません。").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var powerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("機種・権限に依存する追加計測").font(.headline)
                Spacer()
                if store.powerBusy { ProgressView().controlSize(.small) }
                Button("管理者認証して1秒計測") { store.collectPower(administrator: true) }.disabled(store.powerBusy || !store.isRunning)
            }
            Text("macOS標準のpowermetricsを1回実行します。OSの認証画面が開きます。常駐サービスは導入しません。").font(.caption).foregroundStyle(.secondary)
            Text(PowerDetailCollector.administratorStopLimitation).font(.caption).foregroundStyle(.secondary)
            if let detail = store.powerDetails[selectedTab] {
                Text("\(detail.capturedAt.formatted()) の追加計測").font(.caption).foregroundStyle(.secondary)
                metricCards(detail.metrics); notes(detail.notes)
                ReadingGrid(columns: detail.columns, rows: detail.rows, onSelect: { inspected = $0 }, onRelated: showRelated)
            }
        }
    }
    private func filteredRows(_ rows: [ReadingRow]) -> [ReadingRow] {
        var result = search.isEmpty ? rows : rows.filter { row in
            row.name.localizedCaseInsensitiveContains(search) || row.metrics.contains { $0.formatted.localizedCaseInsensitiveContains(search) }
        }
        if sortKey == "name" { result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        else if !sortKey.isEmpty {
            result.sort {
                let a = $0.metric(sortKey), b = $1.metric(sortKey)
                if a?.value != nil || b?.value != nil { return (a?.value ?? -.infinity) > (b?.value ?? -.infinity) }
                return (a?.formatted ?? "") < (b?.formatted ?? "")
            }
        }
        return result
    }
    private func showRelated(_ row: ReadingRow) {
        guard let path = row.path else { return }
        store.relatedFolders = []; store.showRelated(path: path, bundleID: row.bundleID); showingRelated = true
    }
    private func inspectStorage(_ node: StorageNode) {
        inspected = ReadingRow(id: node.id, name: node.name, metrics: [
            Metric("logical", "論理サイズ", value: Double(node.logicalBytes), unit: "B", status: node.aggregateComplete ? .measured : .partial, source: "ファイル属性・子孫集計", recordedAt: node.scannedAt),
            Metric("allocated", "割当済みサイズ", value: node.allocatedBytes.map { Double($0) }, unit: "B", status: node.allocatedBytes == nil ? .unavailable : (node.aggregateComplete ? .measured : .partial), source: "URLResourceValues", detail: "APFS共有・スナップショット等により、削除で解放できる容量とは一致しない場合があります。", recordedAt: node.scannedAt),
            Metric("kind", "種類", text: node.kind.rawValue, source: "FileManager", recordedAt: node.scannedAt)
        ], note: ([node.error, node.symbolicLinkDestination.map { "リンク先: \($0)" }].compactMap { $0 } + node.tags.map { "\($0.name): \($0.reason)" }).joined(separator: "\n"), path: node.path)
    }
    private func bytes(_ value: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary) }
    private func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    private func scanStatus(_ status: StorageScanStatus) -> String {
        switch status { case .idle: return "未走査"; case .scanning: return "走査中"; case .paused: return "一時停止"; case .completed: return "走査完了"; case .cancelled: return "中止・部分結果"; case .failed: return "走査失敗"; case .saved: return "保存された過去の走査結果" }
    }
    private func statusColor(_ status: ReadingStatus) -> Color {
        switch status { case .measured, .derived: return .secondary; case .estimated, .partial, .stale: return .orange; case .waiting: return .secondary; case .denied, .unsupported, .unavailable: return .orange }
    }
}

struct ReadingGrid: View {
    let columns: [TableColumn]
    let rows: [ReadingRow]
    var onSelect: (ReadingRow) -> Void
    var onRelated: (ReadingRow) -> Void
    var body: some View {
        if !rows.isEmpty {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text("名前 / 詳細").frame(width: 220, alignment: .leading)
                        ForEach(columns) { Text($0.title).frame(width: $0.width, alignment: .leading) }
                    }.font(.caption.bold()).padding(9)
                    Divider()
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { row in
                                HStack(spacing: 12) {
                                    Button { onSelect(row) } label: { Text(row.name).frame(width: 220, alignment: .leading).lineLimit(1) }.buttonStyle(.plain)
                                    ForEach(columns) { column in
                                        let metric = row.metric(column.id)
                                        Text(metric?.formatted ?? "—").frame(width: column.width, alignment: .leading).lineLimit(1)
                                            .foregroundStyle(metric?.value == nil && metric?.text == nil ? Color.secondary : Color.primary)
                                            .help(metric.map { "\($0.label) · \($0.status.title)\n\($0.source)\n\($0.detail)" } ?? "取得されていません")
                                    }
                                }.font(.system(size: 12, design: .monospaced)).padding(9)
                                    .contentShape(Rectangle()).onTapGesture { onSelect(row) }
                                    .contextMenu {
                                        Button("数値と取得元の詳細") { onSelect(row) }
                                        if let path = row.path, path.contains(".app") { Button("関連フォルダを表示") { onRelated(row) } }
                                        if let path = row.path { Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }
                                    }
                                Divider().opacity(0.35)
                            }
                        }
                    }.frame(height: 360)
                }.frame(minWidth: 700)
            }.monitorCircuitExclusion()
        }
    }
}
