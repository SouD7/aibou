import SwiftUI
import AppKit
#if canImport(CircuitCore)
import CircuitCore
#endif

/// A desk-sized lesson, with the guide, experiment and navigation always visible.
struct LessonExperienceView: View {
    @ObservedObject var store: LessonStore
    var close: () -> Void
    var openExhibit: (String) -> Void
    var isActive: Bool = true
    @StateObject private var voice = GuideVoice()
    @State private var showingSources = false

    private var accent: Color { ExhibitionStyle.color(store.area) }
    private var phase: LessonStep? { store.session?.step }
    private var pose: String { phase == .reflection ? "celebrating" : (phase == nil ? "welcome" : "explaining") }
    private var line: String {
        guard let lesson = store.lesson else { return "気になることから、ひとつずつ。\n今日は何を、一緒に見つけよう？" }
        switch phase {
        case .introduction: return (lesson.intro.components(separatedBy: "。").first ?? lesson.intro) + "。"
        case .experiment: return lesson.activityPrompt
        case .question: return store.session?.answeredCorrectly == true ? "そう、その関係が見えたね。\n自分のPCにもつなげてみよう。" : "条件が変わったら、どうなるかな？\nさっきの発見を使って考えてみよう。"
        case .reflection: return "またひとつ、しくみがつながったね。\n自分のPCや、ほかの展示にもつなげてみよう。"
        case nil: return "一緒に見てみよう。"
        }
    }
    private var spokenText: String {
        guard let lesson = store.lesson else { return line }
        switch phase {
        case .introduction: return lesson.intro + "。" + lesson.explanation
        case .experiment: return lesson.activityPrompt + "。" + lesson.analogyLimit
        case .question: return lesson.challenge.prompt + "。" + lesson.challenge.options.joined(separator: "。")
        case .reflection: return lesson.takeaway + "。" + lesson.labConnection
        case nil: return line
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop
            header.padding(.horizontal, 40).frame(width: 1600, height: 88)
            guide.frame(width: 460, height: 770).position(x: 255, y: 498)
            notebook.frame(width: 1050, height: 748).position(x: 1025, y: 485)
            if !store.saveError.isEmpty {
                HStack {
                    Label(store.saveError, systemImage: "exclamationmark.circle")
                    Button("再試行", action: store.retrySave).buttonStyle(.plain).underline()
                }.font(.system(size: 17)).padding(10).background(ExhibitionStyle.paper)
                    .position(x: 1005, y: 878).accessibilityIdentifier("lesson.save.error")
            }
        }.frame(width: 1600, height: 900)
            .foregroundStyle(ExhibitionStyle.ink)
            .onChange(of: phase) { _ in voice.stop() }
            .onChange(of: store.session?.lessonID) { _ in voice.stop() }
            .onChange(of: isActive) { if !$0 { voice.stop() } }
            .onDisappear { voice.stop() }
    }

    private var backdrop: some View {
        ZStack {
            if let art = LobbyAnimationArt.shared {
                Image(nsImage: art.background).resizable().frame(width: 1600, height: 900)
                    .blur(radius: 5).opacity(0.22)
            }
            LinearGradient(colors: [ExhibitionStyle.paper.opacity(0.35), Color(red: 0.90, green: 0.86, blue: 0.78)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color(red: 0.67, green: 0.47, blue: 0.30)).frame(height: 32).offset(y: 426)
        }.frame(width: 1600, height: 900).clipped().allowsHitTesting(false).accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 18) {
            Label("aibou の小さな授業", systemImage: "book.pages")
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Spacer()
            if store.session != nil {
                Button { voice.stop(); store.showLibrary() } label: {
                    Label("授業一覧（全20テーマ）", systemImage: "square.grid.2x2")
                }.buttonStyle(ExhibitionButtonStyle(accent: accent))
                    .accessibilityIdentifier("lesson.all")
            }
            Label("\(store.progress.completedIDs.count) / 20 の発見", systemImage: "checkmark.seal")
                .font(.system(size: 20, weight: .medium)).accessibilityElement(children: .combine)
                .accessibilityIdentifier("lesson.progress")
            Button { voice.stop(); close() } label: { Label("展示に戻る", systemImage: "xmark") }
                .buttonStyle(ExhibitionButtonStyle())
                .keyboardShortcut(.cancelAction).accessibilityIdentifier("lesson.close")
        }
    }

    private var guide: some View {
        ZStack(alignment: .top) {
            Ellipse().fill(accent.opacity(0.13)).frame(width: 408, height: 554).offset(y: 210)
            if let image = LessonArtwork.images[pose] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 495, height: 660).offset(y: 205)
                    .shadow(color: ExhibitionStyle.ink.opacity(0.13), radius: 10, y: 7)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(accent).frame(width: 10, height: 10)
                    Text("aibou").font(.system(size: 22, weight: .bold, design: .rounded))
                    Spacer()
                    Button {
                        if voice.isSpeaking { voice.stop() } else { voice.speak(spokenText) }
                    } label: { Image(systemName: voice.isSpeaking ? "stop.circle" : "speaker.wave.2") }
                        .buttonStyle(.plain).font(.system(size: 23))
                        .accessibilityLabel(voice.isSpeaking ? "授業の読み上げを止める" : "この説明を聞く")
                        .accessibilityIdentifier("lesson.voice")
                }
                Text(line).font(.system(size: 23, weight: .medium)).lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("lesson.guide.line")
                if let reason = voice.unavailableReason {
                    Text(reason).font(.system(size: 16)).foregroundStyle(ExhibitionStyle.muted)
                }
            }.padding(24).frame(width: 416, alignment: .leading)
                .background(ExhibitionStyle.paper, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(ExhibitionStyle.ink.opacity(0.65), lineWidth: 1.5))
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "arrowtriangle.down.fill").font(.system(size: 24))
                        .foregroundStyle(ExhibitionStyle.paper).offset(x: 76, y: 18)
                        .accessibilityHidden(true)
                }
        }.animation(nil, value: pose)
    }

    private var notebook: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 24).fill(Color(red: 0.22, green: 0.28, blue: 0.32))
                .shadow(color: .black.opacity(0.16), radius: 16, y: 12)
            RoundedRectangle(cornerRadius: 18).fill(ExhibitionStyle.paper)
                .padding(.leading, 19).padding(7)
            Rectangle().fill(accent.opacity(0.35)).frame(width: 2).padding(.vertical, 34).offset(x: 68)
            VStack(spacing: 69) {
                ForEach(0..<8, id: \.self) { _ in
                    Capsule().fill(Color(red: 0.56, green: 0.60, blue: 0.60))
                        .frame(width: 37, height: 7).overlay(Capsule().stroke(ExhibitionStyle.ink.opacity(0.4)))
                }
            }.padding(.leading, 5).accessibilityHidden(true)
            Group {
                if let lesson = store.lesson, let session = store.session {
                    lessonPage(lesson, session: session)
                } else { library }
            }.padding(.leading, 91).padding(.trailing, 36).padding(.vertical, 30)
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今日は、どの「なぜ？」にする？").font(.system(size: 31, weight: .bold, design: .rounded))
                    Text("全20テーマ、どこからでも。途中で別の授業に移っても大丈夫。")
                        .font(.system(size: 20)).foregroundStyle(ExhibitionStyle.muted)
                }
                Spacer()
                Image(systemName: "sparkle").font(.system(size: 34, weight: .light)).foregroundStyle(accent)
            }
            HStack(spacing: 10) {
                ForEach(ExhibitionCatalog.areas) { area in
                    Button { store.area = area.id } label: {
                        VStack(spacing: 5) {
                            Text(area.id.letter).font(.system(size: 25, weight: .bold, design: .rounded))
                            Text(area.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        }.frame(maxWidth: .infinity).frame(height: 73)
                            .background(store.area == area.id ? ExhibitionStyle.color(area.id) : Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(store.area == area.id ? ExhibitionStyle.ink : ExhibitionStyle.ink.opacity(0.15), lineWidth: store.area == area.id ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel(area.title)
                        .accessibilityValue(store.area == area.id ? "選択中" : "")
                        .accessibilityIdentifier("lesson.area.\(area.id.rawValue)")
                }
            }
            VStack(spacing: 11) {
                ForEach(Array(LessonCatalog.lessons(in: store.area).enumerated()), id: \.element.id) { index, lesson in
                    lessonCard(lesson, number: index + 1)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Label("順番は自由。何度でも試せるよ。", systemImage: "hand.point.up.left")
                    .font(.system(size: 18)).foregroundStyle(ExhibitionStyle.muted)
                Spacer()
                if let id = store.progress.lastLessonID, let lesson = LessonCatalog.lesson(id) {
                    Button { store.open(id) } label: { Text("前の授業を開く").underline() }
                        .buttonStyle(.plain).font(.system(size: 18, weight: .medium))
                        .help(lesson.title).accessibilityIdentifier("lesson.previous")
                }
            }
        }
    }

    private func lessonCard(_ lesson: LessonDefinition, number: Int) -> some View {
        let completed = store.progress.completedIDs.contains(lesson.id)
        return Button { store.open(lesson.id) } label: {
            HStack(spacing: 20) {
                Image(systemName: ExhibitionCatalog.game(lesson.id)?.icon ?? "lightbulb")
                    .font(.system(size: 30, weight: .medium)).frame(width: 69, height: 69)
                    .background(accent.opacity(0.26), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(lesson.title).font(.system(size: 23, weight: .bold, design: .rounded))
                    Text(lesson.question).font(.system(size: 20)).foregroundStyle(ExhibitionStyle.muted).lineLimit(2)
                }
                Spacer(minLength: 2)
                if completed {
                    Label("発見済み", systemImage: "checkmark.seal.fill").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.16, green: 0.43, blue: 0.38))
                } else { Image(systemName: "arrow.up.right").font(.system(size: 24)) }
            }.padding(.horizontal, 18).frame(height: 102)
                .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(ExhibitionStyle.ink.opacity(0.18), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("lesson.open.\(lesson.id)")
            .accessibilityLabel("\(lesson.title)。\(lesson.question)")
            .accessibilityValue(completed ? "発見済み" : "未体験")
    }

    private func lessonPage(_ lesson: LessonDefinition, session: LessonSession) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Button { voice.stop(); store.showLibrary() } label: { Label("別の授業を選ぶ", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 18, weight: .medium)).accessibilityIdentifier("lesson.library")
                Spacer()
                Text("\(store.area.letter)  \(ExhibitionCatalog.area(store.area).title)")
                    .font(.system(size: 18)).foregroundStyle(ExhibitionStyle.muted)
            }
            Text(lesson.title).font(.system(size: 30, weight: .bold, design: .rounded))
                .accessibilityIdentifier("lesson.title")
            stepStrip(session.step)
            Group {
                switch session.step {
                case .introduction: introduction(lesson)
                case .experiment: experiment(lesson, session: session)
                case .question: question(lesson, session: session)
                case .reflection: reflection(lesson)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer(lesson, session: session)
        }.popover(isPresented: $showingSources, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text("この授業の参考資料").font(.system(size: 23, weight: .bold))
                    Text("仕組みの確認に用いた資料です。実験は違いを観察するための模型で、実機の性能を測定するものではありません。")
                        .font(.system(size: 17)).lineSpacing(5)
                    ForEach(lesson.sources, id: \.url) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) { Label(source.title, systemImage: "arrow.up.right.square") }
                                .font(.system(size: 17))
                        }
                    }
                    Button("閉じる") { showingSources = false }.buttonStyle(ExhibitionButtonStyle())
                }.padding(25)
            }.frame(width: 570, height: 380)
        }
    }

    private func stepStrip(_ selected: LessonStep) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(["見つける", "試してみる", "考える", "つなげる"].enumerated()), id: \.offset) { index, title in
                HStack(spacing: 8) {
                    Text(index < selected.rawValue ? "✓" : "\(index + 1)")
                        .font(.system(size: 17, weight: .bold)).frame(width: 28, height: 28)
                        .background(index == selected.rawValue ? accent : ExhibitionStyle.ink.opacity(0.06), in: Circle())
                    Text(title).font(.system(size: 18, weight: index == selected.rawValue ? .bold : .regular))
                        .foregroundStyle(index == selected.rawValue ? ExhibitionStyle.ink : ExhibitionStyle.muted)
                    if index < 3 { Rectangle().fill(ExhibitionStyle.ink.opacity(0.13)).frame(height: 1).padding(.horizontal, 14) }
                }
            }
        }.padding(.vertical, 9).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(selected.rawValue + 1) / 4")
            .accessibilityIdentifier("lesson.step")
    }

    private func introduction(_ lesson: LessonDefinition) -> some View {
        VStack(alignment: .leading, spacing: 27) {
            Text(lesson.question).font(.system(size: 34, weight: .bold, design: .rounded)).lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 13)
            HStack(alignment: .top, spacing: 23) {
                Image(systemName: ExhibitionCatalog.game(lesson.id)?.icon ?? "lightbulb")
                    .font(.system(size: 58, weight: .light)).frame(width: 110, height: 120).foregroundStyle(ExhibitionStyle.ink)
                Text(lesson.explanation).font(.system(size: 25)).lineSpacing(11)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(27).frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 9) {
                Label("今日、見つけること", systemImage: "scope").font(.system(size: 18, weight: .semibold)).foregroundStyle(ExhibitionStyle.muted)
                Text(lesson.goal).font(.system(size: 23)).lineSpacing(7)
            }
        }
    }

    private func experiment(_ lesson: LessonDefinition, session: LessonSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("条件を変えて、結果を見てみよう").font(.system(size: 23, weight: .bold))
                Spacer()
                Label(session.explored ? "変化を観察した" : "まず1回、触ってみよう", systemImage: session.explored ? "checkmark.circle.fill" : "hand.point.up.left")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(ExhibitionStyle.muted)
                    .accessibilityIdentifier("lesson.explored")
            }
            LessonActivityView(kind: lesson.activity, onExplore: store.explore)
                .id(lesson.id).frame(width: 830, height: 380).frame(maxWidth: .infinity)
            Text(lesson.analogyLimit).font(.system(size: 17)).lineSpacing(4)
                .foregroundStyle(ExhibitionStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func question(_ lesson: LessonDefinition, session: LessonSession) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(lesson.challenge.prompt).font(.system(size: 26, weight: .semibold)).lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
            ForEach(Array(lesson.challenge.options.enumerated()), id: \.offset) { index, option in
                Button { store.answer(index) } label: {
                    HStack(spacing: 17) {
                        Text(["A", "B", "C"][index]).font(.system(size: 20, weight: .bold))
                            .frame(width: 34, height: 34).background(accent.opacity(0.25), in: Circle())
                        Text(option).font(.system(size: 22, weight: .medium)).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if session.selectedOption == index {
                            Image(systemName: session.answeredCorrectly ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                                .font(.system(size: 23))
                        }
                    }.padding(.horizontal, 19).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 67)
                        .background(session.selectedOption == index ? accent.opacity(0.18) : Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(session.selectedOption == index ? ExhibitionStyle.ink : ExhibitionStyle.ink.opacity(0.2), lineWidth: session.selectedOption == index ? 2 : 1))
                }.buttonStyle(.plain).accessibilityIdentifier("lesson.answer.\(index)")
            }
            if session.selectedOption != nil {
                Text(session.answeredCorrectly ? lesson.challenge.correctFeedback : lesson.challenge.incorrectFeedback)
                    .font(.system(size: 21)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                    .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("lesson.feedback")
            } else {
                Text("選び直しても大丈夫。理由まで、一緒に確かめよう。")
                    .font(.system(size: 18)).foregroundStyle(ExhibitionStyle.muted).padding(.top, 9)
            }
        }
    }

    private func reflection(_ lesson: LessonDefinition) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 57)).foregroundStyle(Color(red: 0.23, green: 0.52, blue: 0.46))
                VStack(alignment: .leading, spacing: 5) {
                    Text("今日の発見を、ノートに。").font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("実験と問いを終えました").font(.system(size: 18)).foregroundStyle(ExhibitionStyle.muted)
                }
            }.padding(.top, 14).accessibilityElement(children: .combine).accessibilityIdentifier("lesson.complete")
            Text(lesson.takeaway).font(.system(size: 27, weight: .medium)).lineSpacing(10)
                .fixedSize(horizontal: false, vertical: true).padding(25).frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 12) {
                Label("自分のPCにつなげると", systemImage: "laptopcomputer").font(.system(size: 20, weight: .bold))
                Text(lesson.labConnection).font(.system(size: 22)).lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 15) {
                Button { voice.stop(); openExhibit(lesson.id) } label: {
                    Label(ExhibitionCatalog.game(lesson.id)?.isPlayable == true ? "ゲームの入口へ" : "関連する展示を見る", systemImage: "arrow.up.right")
                }.buttonStyle(ExhibitionButtonStyle(accent: accent)).accessibilityIdentifier("lesson.exhibit")
            }
            if ExhibitionCatalog.game(lesson.id)?.isPlayable != true {
                Text("このテーマのミニゲームは準備中です。授業の実験は何度でも試せます。")
                    .font(.system(size: 17)).foregroundStyle(ExhibitionStyle.muted)
            }
        }
    }

    private func footer(_ lesson: LessonDefinition, session: LessonSession) -> some View {
        HStack(spacing: 18) {
            Button { showingSources = true } label: { Label("参考資料", systemImage: "text.book.closed") }
                .buttonStyle(.plain).font(.system(size: 17)).foregroundStyle(ExhibitionStyle.muted)
                .accessibilityIdentifier("lesson.sources")
            Spacer()
            if session.step != .introduction {
                Button { store.back() } label: { Label("前へ", systemImage: "chevron.left") }
                    .buttonStyle(ExhibitionButtonStyle()).accessibilityIdentifier("lesson.back")
            }
            if session.step == .reflection {
                Button { store.showLibrary() } label: { Text("ほかの「なぜ？」へ") }
                    .buttonStyle(ExhibitionButtonStyle(accent: accent)).accessibilityIdentifier("lesson.done")
            } else {
                Button { store.advance() } label: {
                    Label(session.step == .introduction ? "試してみる" : (session.step == .experiment ? "考えてみる" : "発見を残す"), systemImage: "arrow.right")
                }.buttonStyle(ExhibitionButtonStyle(accent: accent)).disabled(!session.canAdvance)
                    .accessibilityIdentifier("lesson.next")
            }
        }.padding(.top, 5)
    }
}

enum LessonArtwork {
    static let images: [String: NSImage] = Dictionary(uniqueKeysWithValues: ["welcome", "explaining", "celebrating"].compactMap { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "LessonArt"),
              let original = NSImage(contentsOf: url), let keyed = ImageProcessing.removeGreenScreen(from: original) else { return nil }
        return (name, keyed)
    })
}
