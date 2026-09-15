import AppKit
import SwiftUI

private final class ApplicationStorageCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

@MainActor
final class ApplicationDetailModel: ObservableObject {
    @Published private(set) var storage: ApplicationStorageResult?
    @Published private(set) var storageBusy = false
    private var cancellation: ApplicationStorageCancellation?

    init(storage: ApplicationStorageResult? = nil) { self.storage = storage }

    func scan(app: LauncherApplication) {
        guard !storageBusy else { return }
        let token = ApplicationStorageCancellation()
        cancellation = token; storageBusy = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                ApplicationStorage.scan(app: app, isCancelled: { token.isCancelled })
            }.value
            guard let self, self.cancellation === token, !token.isCancelled else { return }
            self.storage = result; self.storageBusy = false
        }
    }
    func stop() { cancellation?.cancel(); cancellation = nil; storageBusy = false }
}

struct ApplicationDetailView: View {
    let app: LauncherApplication
    @ObservedObject var store: MonitorStore
    @StateObject private var detail = ApplicationDetailModel()
    @State private var networkOperation: CommandOperation?
    @Environment(\.dismiss) private var dismiss
    private let automaticallyCollect: Bool

    init(app: LauncherApplication, store: MonitorStore, model: ApplicationDetailModel? = nil, automaticallyCollect: Bool = true) {
        self.app = app; self.store = store; self.automaticallyCollect = automaticallyCollect
        _detail = StateObject(wrappedValue: model ?? ApplicationDetailModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(app.name) の詳細").font(.title2.bold())
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(app.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let group = ApplicationProcessGroup.make(app: app, processes: store.processes)
                    let inventory = store.panels[.cpu]?.metrics.first { $0.id == "processCount" }?.status ?? .waiting
                    VStack(alignment: .leading, spacing: 18) {
                        Text("CPU・メモリ：取得できた \(group.processes.count) プロセスの合計").font(.headline)
                        if !store.isRunning { Label("基本監視停止中。再開すると使用量の更新も再開します。", systemImage: "pause.circle").foregroundStyle(.orange) }
                        if group.processes.isEmpty { Text("このアプリに属するプロセスが見つかりません。未起動、終了直後、または読取制限の可能性があります。").foregroundStyle(.secondary) }
                        metricGrid(group.metrics(recordedAt: store.lastSample, inventoryStatus: inventory, running: store.isRunning, now: context.date))
                        Text("CPUは1コア=100%です。メモリはプロセスごとの値の合計で、共有領域の扱いによりシステム全体の使用量増分とは一致しません。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("ネットワーク：プロセス集計").font(.headline)
                        if store.networkBusy { HStack { ProgressView().controlSize(.small); Text("通信量を計測中…") } }
                        if let panel = store.networkDetail {
                            let metrics = ApplicationNetworkUsage.aggregate(panel: panel, group: group, stableIDs: store.networkStableProcessIDs,
                                running: store.isRunning, now: context.date)
                            metricGrid(metrics)
                            if let failure = panel.metrics.first(where: { $0.id == "nettop.status" }) {
                                Text(failure.detail).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                            }
                        } else { Text("通信量の取得を待っています。").foregroundStyle(.secondary) }
                        Text("詳細を開いている間、約3秒ごとに1秒区間を観測します。表示はその区間の合計で、起動からの累積通信量ではありません。権限制限や行の欠落は0に置き換えません。")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("合算したプロセスと帰属の根拠（\(group.processes.count)）") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(group.processes) { process in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(process.name)  •  PID \(process.pid)").font(.callout.bold())
                                        Text(group.inheritedIDs.contains(process.id) ? "親子関係からの推定" : "アプリ内部の実行パスで照合").font(.caption)
                                        Text(process.path).font(.caption.monospaced()).textSelection(.enabled)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        }
                        Text("本体・内包ヘルパーと、その子プロセスを合算します。別アプリの起動は合算せず、親子関係が失われた外部ヘルパーや共用OSサービスは帰属できない場合があります。")
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        storageSection
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.monitorCircuitExclusion().padding(22).frame(width: 880, height: 740).monitorSurface()
        .onAppear { if automaticallyCollect { detail.scan(app: app) } }
        .task {
            guard automaticallyCollect else { return }
            while !Task.isCancelled {
                if store.isRunning, let operation = store.collectNetwork() { networkOperation = operation }
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
            }
        }
        .onDisappear {
            detail.stop()
            if let networkOperation { store.cancelNetworkCollection(operation: networkOperation) }
        }
    }

    private func metricGrid(_ metrics: [Metric]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], alignment: .leading, spacing: 10) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 5) {
                    Text(metric.label).font(.caption).foregroundStyle(.secondary)
                    Text(metric.formatted).font(.title3.monospacedDigit().bold())
                    Text("\(metric.status.title) • \(metric.recordedAt.formatted(date: .omitted, time: .standard))").font(.caption2).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .monitorCard(cornerRadius: 8)
                    .help(metric.detail)
            }
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ディスク使用量").font(.headline)
                Spacer()
                if detail.storageBusy { ProgressView().controlSize(.small); Text("容量を集計中…").font(.caption) }
                Button("容量を再集計") { detail.scan(app: app) }.disabled(detail.storageBusy)
            }
            if let result = detail.storage {
                let appRows = result.rows.filter { $0.scope == .application }
                let appReadable = appRows.contains { $0.scannedEntries > 0 && $0.status != .unreadable }
                let relatedRows = result.rows.filter { $0.scope == .related }
                let anyRelatedReadable = relatedRows.contains { $0.scannedEntries > 0 && $0.status != .unreadable }
                let relatedReadable = relatedRows.isEmpty || anyRelatedReadable
                metricGrid([
                    Metric("disk.app", "アプリ本体", value: appReadable ? Double(result.appBytes) : nil, unit: "B",
                        status: !appReadable ? .unavailable : appRows.allSatisfy(\.complete) ? .measured : .partial, source: "ファイルサイズ合算", recordedAt: result.capturedAt),
                    Metric("disk.related", "関連ファイル候補", value: relatedReadable ? Double(result.relatedBytes) : nil, unit: "B",
                        status: relatedRows.allSatisfy(\.complete) ? .estimated : .partial, source: "標準保存先候補", recordedAt: result.capturedAt),
                    Metric("disk.total", result.complete ? "本体＋関連候補の合計" : "本体＋関連候補（読取範囲の合計）", value: appReadable || anyRelatedReadable ? Double(result.combinedBytes) : nil, unit: "B",
                        status: result.complete ? .estimated : .partial, source: "重複除外後の論理サイズ", recordedAt: result.capturedAt)
                ])
                ForEach(result.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                Text("論理サイズを表示します。APFSの圧縮・クローンなどがある場合、実際に空くディスク容量とは異なります。容量は表示時のスナップショットです。")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("容量を集計した場所（\(result.rows.count)）") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(result.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.name).font(.callout.bold())
                                    Spacer()
                                    Text(row.scannedEntries > 0 ? ByteCountFormatter.string(fromByteCount: Int64(clamping: row.logicalBytes), countStyle: .binary) : "—")
                                    Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: row.path)]) }
                                }
                                Text(row.path).font(.caption.monospaced()).textSelection(.enabled)
                                Text(row.evidence).font(.caption).foregroundStyle(.secondary)
                                ForEach(row.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                            }
                        }
                    }.padding(.top, 8)
                }
            } else { Text("アプリ本体と標準の関連保存先を集計します。大きなフォルダは時間がかかる場合があります。").foregroundStyle(.secondary) }
        }
    }
}
