import AppKit
import SwiftUI

enum RoomConsultationFlow {
    static func startsComposing(messages: [ConsultationMessage], question: String) -> Bool {
        messages.isEmpty || !question.isEmpty
    }

    static func canAddQuestion(messages: [ConsultationMessage], busy: Bool, question: String) -> Bool {
        question.isEmpty && !busy && hasAnswerAfterLastQuestion(messages)
    }

    static func needsUnansweredRecovery(messages: [ConsultationMessage], busy: Bool) -> Bool {
        !busy && messages.last(where: \.isUser) != nil && !hasAnswerAfterLastQuestion(messages)
    }

    static func shouldOfferNewConversation(error: String, busy: Bool) -> Bool {
        !busy && error.contains("20往復")
    }

    private static func hasAnswerAfterLastQuestion(_ messages: [ConsultationMessage]) -> Bool {
        guard let questionIndex = messages.lastIndex(where: \.isUser) else { return false }
        return messages[messages.index(after: questionIndex)...]
            .contains { !$0.isUser && !$0.text.isEmpty }
    }
}

/// Owns the room-only editor state for as long as the room consultation UI is
/// actually visible. Monitor sheets keep the shared model alive while removing
/// this subtree, so stale confirmations and preparation errors cannot reappear
/// when the sheet closes.
struct RoomConsultationSurface: View {
    @ObservedObject var model: ConsultationModel
    @ObservedObject var store: MonitorStore
    var addQuestionRequest: Int = 0
    var isVisible: Bool

    @ViewBuilder
    var body: some View {
        if isVisible {
            RoomConsultationView(model: model,
                                 store: store,
                                 addQuestionRequest: addQuestionRequest)
        }
    }
}

/// The in-room consultation surface. Connection setup is normally presented by
/// the parent, but this view keeps recovery actions available if the connection
/// changes while a consultation is open.
struct RoomConsultationView: View {
    @ObservedObject var model: ConsultationModel
    @ObservedObject var store: MonitorStore
    var addQuestionRequest: Int = 0

    @State private var composing = true
    @State private var draft: ConsultationDraft?
    @State private var preparationError = ""

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                connectionRecovery

                if !model.messages.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(model.messages) { message in
                                    messageBubble(message)
                                        .id(message.id)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(minHeight: 72, maxHeight: composing ? 150 : 330)
                        .onAppear { scrollToLatest(using: proxy, animated: false) }
                        .onChange(of: model.messages.count) { _ in
                            scrollToLatest(using: proxy, animated: true)
                        }
                        .onChange(of: model.messages.last?.text ?? "") { _ in
                            scrollToLatest(using: proxy, animated: false)
                        }
                    }
                }

                if model.busy {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text("アバターが考えています…")
                            .font(.callout)
                        Spacer()
                        Button("回答を停止") {
                            Task { await model.interrupt() }
                        }
                    }
                }

                if !model.error.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(model.error)
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        if lastQuestion != nil && !model.busy {
                            Button("再入力") { restoreLastQuestion() }
                                .help("自動では再送せず、内容を確認してから送信します")
                        }
                        if RoomConsultationFlow.shouldOfferNewConversation(error: model.error, busy: model.busy) {
                            Button("新しい相談") { startNewConversation() }
                        }
                    }
                }

                if composing {
                    composer
                } else if needsUnansweredRecovery {
                    HStack {
                        Text(model.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("質問を再入力") { restoreLastQuestion() }
                            .help("自動では再送せず、内容を確認してから送信します")
                    }
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
            .frame(maxWidth: 780)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .onAppear {
            // `question` belongs to the long-lived model, while this view's state is
            // recreated whenever consultation mode closes. Reopen any unsent text
            // as an editable question; a lost confirmation must be prepared again.
            composing = RoomConsultationFlow.startsComposing(messages: model.messages,
                                                              question: model.question)
        }
        .onChange(of: addQuestionRequest) { _ in
            guard canAddQuestion else { return }
            draft = nil
            preparationError = ""
            composing = true
        }
    }

    @ViewBuilder
    private var connectionRecovery: some View {
        if !model.signedIn {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ChatGPTとの接続が必要です")
                        .font(.headline)
                    Text(model.error.isEmpty ? model.status : "接続状態を確認して、もう一度お試しください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.connected {
                    if let url = model.loginURL {
                        Button("ブラウザでログイン") { NSWorkspace.shared.open(url) }
                        Button("取消") { Task { await model.cancelLogin() } }
                    } else {
                        Button(model.connecting ? "準備中…" : "ChatGPTでログイン") {
                            Task { await model.login() }
                        }
                        .disabled(model.connecting)
                    }
                } else if model.executablePath.isEmpty {
                    Text("モニター画面でCodex CLIを設定してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button(model.connecting ? "接続中…" : "再接続") {
                        Task { await model.connect() }
                    }
                    .disabled(model.connecting)

                    if model.connecting {
                        Button("中止") { model.disconnect() }
                    }
                }
            }
            .padding(10)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let draft {
                Text("この内容をOpenAIへ送信し、ログイン中のアカウントのCodex利用枠を使います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(draft.question)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.90),
                                in: RoundedRectangle(cornerRadius: 9))

                if let attachment = draft.attachment {
                    DisclosureGroup("送信するモニタ集計情報") {
                        ScrollView {
                            Text(attachment)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                    }
                    .font(.caption)
                }

                HStack {
                    Button("戻る") { self.draft = nil }
                    Spacer()
                    Button("送信") { send(draft) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.signedIn || model.busy || model.connecting)
                }
            } else {
                TextEditor(text: $model.question)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 72, maxHeight: 120)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.90),
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.secondary.opacity(0.28))
                    }
                    .accessibilityLabel("アバターに相談する内容")

                DisclosureGroup("送信する情報") {
                    Toggle("今回のモニタ集計情報を添付", isOn: $model.attachReadings)
                    Text("有効にすると、CPU・メモリ・空き容量・熱状態などの全体指標と取得時刻を送ります。ファイル一覧、プロセス名、接続先は自動添付しません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                HStack(alignment: .center) {
                    if !preparationError.isEmpty {
                        Text(preparationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("相談する") { prepare() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canPrepare)
                }
            }
        }
    }

    private var canPrepare: Bool {
        model.signedIn
            && !model.busy
            && !model.connecting
            && !model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canAddQuestion: Bool {
        RoomConsultationFlow.canAddQuestion(messages: model.messages,
                                            busy: model.busy,
                                            question: model.question)
    }

    private var needsUnansweredRecovery: Bool {
        RoomConsultationFlow.needsUnansweredRecovery(messages: model.messages, busy: model.busy)
    }

    private var lastQuestion: String? {
        model.messages.last(where: \.isUser)?.text
    }

    private func prepare() {
        do {
            let attachment = model.attachReadings ? try store.consultationAttachment().json() : nil
            draft = model.makeDraft(attachment: attachment)
            preparationError = ""
        } catch {
            preparationError = "添付情報を作成できません: \(error.localizedDescription)"
        }
    }

    private func restoreLastQuestion() {
        guard let lastQuestion else { return }
        model.question = lastQuestion
        preparationError = ""
        composing = true
    }

    private func send(_ draft: ConsultationDraft) {
        let messageCount = model.messages.count
        self.draft = nil
        composing = false
        Task {
            await model.send(draft)
            // Validation/auth can reject before a message is appended. Keep the
            // user's text available for correction in that case.
            if model.messages.count == messageCount {
                composing = true
            }
        }
    }

    private func startNewConversation() {
        model.newConversation()
        model.question = ""
        preparationError = ""
        composing = true
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        guard let id = model.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }

    private func messageBubble(_ message: ConsultationMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.isUser ? "あなた" : "アバター")
                    .font(.caption.bold())
                if let delivery = message.delivery {
                    Text(delivery.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Model output stays selectable plain text and never invokes links or commands.
            Text(message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let attachment = message.attachment {
                DisclosureGroup("この質問に添付した観測情報") {
                    Text(attachment)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(message.isUser ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
    }
}
