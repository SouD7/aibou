import SwiftUI
import AppKit

struct ConsultationView: View {
    @ObservedObject var model: ConsultationModel
    @ObservedObject var store: MonitorStore
    @State private var draft: ConsultationDraft?
    @State private var previewing = false
    @State private var preparationError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Codexに相談", systemImage: "bubble.left.and.bubble.right").font(.title2.bold())
            Text("このMacの状態について、原因候補や次に確認することを相談できます。送信した質問と添付情報はOpenAIへ送られ、ログインしたアカウントのCodex利用枠を使います。")
                .foregroundStyle(.secondary)
            GroupBox("接続") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.accountLabel).font(.headline)
                        Spacer()
                        if model.connected {
                            Button("切断") { model.disconnect() }
                            Button("ログアウト") { Task { await model.logout() } }.disabled(model.busy || model.connecting)
                        } else {
                            Button(model.connecting ? "接続中…" : "Codexと接続") { Task { await model.connect() } }
                                .disabled(model.connecting || model.executablePath.isEmpty)
                            if model.connecting { Button("中止") { model.disconnect() } }
                        }
                    }
                    if !model.connected && !model.connecting {
                        HStack {
                            TextField("Codex CLIのパス", text: $model.executablePath).textFieldStyle(.roundedBorder)
                            Button("実行ファイルを選択") { chooseExecutable() }
                        }
                        Text("公式Codex CLIを選択してください。選択した実行ファイルはユーザー権限で起動します。初回はAIBOU専用にChatGPTへログインします。")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Codex CLIの導入方法", destination: URL(string: "https://developers.openai.com/codex/cli")!)
                    }
                    if model.connected && !model.signedIn {
                        HStack {
                            if let url = model.loginURL {
                                Button("ブラウザでログイン") { NSWorkspace.shared.open(url) }
                                Button("ログインを取消") { Task { await model.cancelLogin() } }
                            } else {
                                Button("ChatGPTでログイン") { Task { await model.login() } }.disabled(model.connecting)
                            }
                        }
                    }
                    Text(model.status).font(.callout).textSelection(.enabled)
                    if !model.error.isEmpty { Label(model.error, systemImage: "exclamationmark.circle").foregroundStyle(.red).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            HStack {
                Text("相談の内容").font(.headline)
                Spacer()
                Button("新しい相談") { model.newConversation() }.disabled(model.busy || model.connecting)
            }
            if model.messages.isEmpty {
                Text("例：最近動作が重いです。今の数値から分かることと、次に確認することを教えてください。")
                    .foregroundStyle(.secondary).padding(.vertical, 10)
            }
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(model.messages) { message in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message.isUser ? "あなた" : "Codex").font(.headline)
                        if let delivery = message.delivery { Text(delivery.rawValue).font(.caption).foregroundStyle(.secondary) }
                        // Render as selectable plain text; model output never invokes links or commands.
                        Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        if let attachment = message.attachment {
                            DisclosureGroup("この質問に添付した観測情報") {
                                Text(attachment).font(.caption.monospaced()).textSelection(.enabled)
                            }.font(.caption)
                        }
                    }.padding(14).background(message.isUser ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor),
                                             in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if model.busy { HStack { ProgressView().controlSize(.small); Text("回答を待っています…"); Button("回答を停止") { Task { await model.interrupt() } } } }
            VStack(alignment: .leading, spacing: 8) {
                Text("質問・追加質問").font(.headline)
                HStack {
                    Text("回答の長さ")
                    Picker("回答の長さ", selection: $model.responseLength) {
                        ForEach(ConsultationResponseLength.allCases, id: \.self) { length in
                            Text(length.label).tag(length)
                        }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 300)
                }
                Text("このアプリの相談に適用し、次回もこの設定を使います。「詳しく」と質問すると、選択にかかわらず説明を広げます。")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $model.question).font(.body).frame(minHeight: 90, maxHeight: 140)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)))
                    .accessibilityLabel("相談する内容")
                Toggle("今回のモニタ集計情報を添付", isOn: $model.attachReadings)
                Text("CPU・メモリ・空き容量・熱状態などの全体指標と取得時刻を添付します。ファイル一覧、プロセス名、接続先は自動添付しません。質問に自分で入力した内容は送信されます。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("会話は起動中のみ保持。再接続前の発言は画面に残りますが、Codexへ引き継がれません。自動修復は行いません。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("送信内容を確認") { prepare() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.signedIn || model.busy || model.connecting || model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !preparationError.isEmpty { Text(preparationError).foregroundStyle(.red) }
            }
        }.padding(22)
        .sheet(isPresented: $previewing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("この内容をCodexへ送信します").font(.title2.bold())
                Text("質問と添付情報をOpenAIへ送信し、Codex利用枠を消費します。添付は以下の確認時点の値です。")
                Text("回答の長さ：\(draft?.responseLength.label ?? "標準")").font(.headline)
                ScrollView { Text(draft?.transmittedText ?? "").font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Button("戻る") { previewing = false }
                    Spacer()
                    Button("この内容で相談") {
                        guard let draft else { return }
                        previewing = false
                        Task { await model.send(draft) }
                    }.buttonStyle(.borderedProminent).disabled(!model.signedIn || model.busy || model.connecting)
                }
            }.padding(24).frame(width: 700, height: 580)
        }
    }
    private func prepare() {
        do {
            let attachment = model.attachReadings ? try store.consultationAttachment().json() : nil
            draft = model.makeDraft(attachment: attachment)
            preparationError = ""; previewing = true
        } catch { preparationError = "添付情報を作成できません: \(error.localizedDescription)" }
    }
    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Codex実行ファイルを選択"; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.executablePath = url.path }
    }
}
