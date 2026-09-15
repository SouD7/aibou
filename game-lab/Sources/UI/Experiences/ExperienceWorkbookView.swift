import SwiftUI

struct ExperienceWorkbookView: View {
    @ObservedObject var exhibition: ExhibitionStore
    @ObservedObject var workshop: WorkshopStore
    var close: () -> Void
    var openGame: (String) -> Void
    var openLegacyArtifact: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        ZStack(alignment: .topLeading) {
            ExhibitionStyle.paper
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("日記").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("試したことも、発見したことも。次の遊びへつなげよう。")
                        .font(.system(size: 22)).foregroundStyle(ExhibitionStyle.muted)
                }
                Spacer()
                Button(action: close) { Label("閉じる", systemImage: "xmark") }.buttonStyle(ExhibitionButtonStyle()).keyboardShortcut(.cancelAction)
            }.frame(width: 1470).offset(x: 65, y: 30)
            VStack(spacing: 18) {
                IllustratedGuideView(speaking: false, reducedMotion: reduced, compact: false, notebook: true)
                    .frame(width: 360, height: 540)
                Text("見つけたしくみを\nもう一度、動かしてみよう。")
                    .font(.system(size: 24, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                Text("作品 \(exhibition.experienceProgress.reduce(0) { $0 + $1.artifactCount } + (workshop.state.completedArtifact == nil ? 0 : 1)) 点")
                    .font(.system(size: 21, weight: .bold)).foregroundStyle(.teal)
                if workshop.state.completedArtifact != nil {
                    Button("以前の回路の作品を動かす", action: openLegacyArtifact).buttonStyle(ExhibitionButtonStyle())
                }
            }.frame(width: 410).offset(x: 25, y: 142)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(ExhibitionCatalog.areas) { area in
                        VStack(alignment: .leading, spacing: 12) {
                            Label("\(area.id.letter)  \(area.title)", systemImage: "square.grid.2x2")
                                .font(.system(size: 23, weight: .bold)).foregroundStyle(ExhibitionStyle.ink)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(ExhibitionCatalog.games(in: area.id)) { game in
                                    let progress = exhibition.progress(for: game.id)
                                    Button { openGame(game.id) } label: {
                                        HStack(alignment: .top, spacing: 14) {
                                            Image(systemName: game.icon).font(.system(size: 26)).frame(width: 48, height: 48)
                                                .background(ExhibitionStyle.color(area.id).opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text(game.title).font(.system(size: 21, weight: .bold))
                                                Text(progress?.canResume == true ? "課題 \(progress!.stage) · \(progress!.stageTitle)" : "気になる装置から、はじめよう")
                                                    .font(.system(size: 15)).foregroundStyle(ExhibitionStyle.muted).lineLimit(1)
                                                HStack(spacing: 7) {
                                                    ForEach(1...5, id: \.self) { stage in
                                                        Image(systemName: progress?.completedStages.contains(stage) == true ? "checkmark.circle.fill" : "circle")
                                                            .foregroundStyle(progress?.completedStages.contains(stage) == true ? Color.teal : ExhibitionStyle.muted.opacity(0.4))
                                                    }
                                                    Spacer()
                                                    Text(progress?.artifactCount ?? 0 > 0 ? "作品 \(progress!.artifactCount)" : "あそぶ").font(.system(size: 14, weight: .semibold))
                                                }
                                            }
                                        }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
                                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ExhibitionStyle.ink.opacity(0.2), lineWidth: 1.5))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }.padding(8)
            }.frame(width: 1090, height: 728).offset(x: 450, y: 145)
        }.frame(width: 1600, height: 900).foregroundStyle(ExhibitionStyle.ink)
            .onAppear { exhibition.refreshExperienceProgress() }
    }
}
