import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationLauncherView: View {
    @ObservedObject var launcher: ApplicationLauncher
    var store: MonitorStore? = nil
    @State private var query = ""
    @State private var detailApplication: LauncherApplication?
    private var filtered: [LauncherApplication] { launcher.applications.filter { $0.matches(query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("アプリケーション", systemImage: "square.grid.2x2").font(.title2.bold())
                Spacer()
                Button("アプリを追加", action: chooseApplication).disabled(launcher.loading)
                Button("一覧を更新") { Task { await launcher.refresh() } }.disabled(launcher.loading)
            }
            Text("使いたいアプリをクリックして開けます。起動中のアプリは手前に表示します。")
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("アプリ名で検索", text: $query).textFieldStyle(.roundedBorder)
                Text("\(filtered.count)件").foregroundStyle(.secondary).monospacedDigit()
            }
            if launcher.loading { HStack { ProgressView().controlSize(.small); Text("アプリを読み込んでいます…") } }
            if !launcher.error.isEmpty { Label(launcher.error, systemImage: "exclamationmark.circle").foregroundStyle(.red).textSelection(.enabled) }
            if !launcher.message.isEmpty { Text(launcher.message).foregroundStyle(.secondary) }
            ForEach(launcher.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            if filtered.isEmpty && !launcher.loading {
                Text(query.isEmpty ? "アプリが見つかりません。「アプリを追加」から選択してください。" : "一致するアプリがありません。検索語を変えるか、アプリを追加してください。")
                    .foregroundStyle(.secondary).padding(.vertical, 30)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 190), spacing: 18)], spacing: 22) {
                ForEach(filtered) { app in
                    LauncherApplicationTile(app: app, running: launcher.running.contains(app.id), launching: launcher.launching.contains(app.id),
                        open: { launcher.open(app) }, showDetails: store == nil ? nil : { detailApplication = app })
                }
            }
            Text("アプリケーションフォルダと標準アプリを表示します。別の場所にあるアプリは手動で追加できます。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22)
        .task { await launcher.loadIfNeeded() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in launcher.updateRunning() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in launcher.updateRunning() }
        .sheet(item: $detailApplication) { app in
            if let store { ApplicationDetailView(app: app, store: store) }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "一覧に追加するアプリを選択"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url { Task { await launcher.add(url) } }
    }
}

private struct LauncherApplicationTile: View {
    let app: LauncherApplication
    let running: Bool
    let launching: Bool
    let open: () -> Void
    let showDetails: (() -> Void)?
    @State private var icon: NSImage?
    var body: some View {
        Button(action: open) {
            VStack(spacing: 10) {
                Group {
                    if let icon { Image(nsImage: icon).resizable().scaledToFit() }
                    else { Image(systemName: "app").resizable().scaledToFit().foregroundStyle(.secondary) }
                }.frame(width: 64, height: 64)
                Text(app.name).font(.body).lineLimit(2).multilineTextAlignment(.center).frame(height: 36)
                Text(launching ? "開いています…" : running ? "● 起動中" : "開く")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(launching)
        .help("\(app.name)\n\(app.url.path)")
        .accessibilityLabel("\(app.name)を開く\(running ? "、起動中" : "")")
        .contextMenu {
            Text(app.url.path)
            if let showDetails { Button("詳細", action: showDetails) }
            Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
        }
        .task(id: app.id) { icon = NSWorkspace.shared.icon(forFile: app.url.path) }
    }
}
