import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

struct ExhibitionMapView: View {
    @ObservedObject var exhibition: ExhibitionStore
    @ObservedObject var workshop: WorkshopStore
    let openGame: (String) -> Void
    let openArea: (ExhibitionAreaID) -> Void
    let close: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ExhibitionStyle.paper
            Path { path in
                path.move(to: CGPoint(x: 410, y: 420)); path.addLine(to: CGPoint(x: 410, y: 470))
                path.addLine(to: CGPoint(x: 1190, y: 470)); path.addLine(to: CGPoint(x: 1190, y: 420))
                for x in [CGFloat(290), 800, 1310] {
                    path.move(to: CGPoint(x: 800, y: 470)); path.addLine(to: CGPoint(x: x, y: 470)); path.addLine(to: CGPoint(x: x, y: 535))
                }
            }.stroke(Color(red: 0.74, green: 0.74, blue: 0.71), style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round))
                .accessibilityHidden(true)
            HStack(alignment: .center) {
                IllustratedGuideView(speaking: false, reducedMotion: true, compact: true, notebook: true)
                    .frame(width: 88, height: 88).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text("館内マップ").font(.system(size: 39, weight: .bold, design: .rounded))
                    Text("気になるしくみから、のぞいてみよう。  5つの展示室・20の入口")
                        .font(.system(size: 21)).foregroundStyle(ExhibitionStyle.muted)
                }
                Spacer()
                Button(action: close) { Label("閉じる", systemImage: "xmark") }
                    .buttonStyle(ExhibitionButtonStyle()).accessibilityIdentifier("ex.map.close")
                    .keyboardShortcut(.cancelAction)
            }.frame(width: 1460).position(x: 800, y: 66)
            room(.a, width: 660, height: 310).position(x: 405, y: 280)
            room(.b, width: 660, height: 310).position(x: 1195, y: 280)
            Button {
                exhibition.goToLobby(); close()
            } label: { Label("ロビー", systemImage: "leaf") }
                .buttonStyle(ExhibitionButtonStyle()).accessibilityIdentifier("ex.map.lobby")
                .position(x: 800, y: 478)
            room(.c, width: 460, height: 310).position(x: 290, y: 692)
            room(.d, width: 460, height: 310).position(x: 800, y: 692)
            room(.e, width: 460, height: 310).position(x: 1310, y: 692)
            Text("20の体験を、気になる入口から。作業の続きや作品は日記に残ります。")
                .font(.system(size: 17)).foregroundStyle(ExhibitionStyle.muted)
                .position(x: 800, y: 876)
        }.foregroundStyle(ExhibitionStyle.ink)
    }

    private func room(_ areaID: ExhibitionAreaID, width: CGFloat, height: CGFloat) -> some View {
        let area = ExhibitionCatalog.area(areaID)
        let accent = ExhibitionStyle.color(areaID)
        return VStack(spacing: 10) {
            Button { openArea(areaID) } label: {
                HStack(spacing: 13) {
                    Text(areaID.letter).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(area.title).font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.85)
                    Spacer(minLength: 1)
                    Image(systemName: "arrow.up.right").font(.system(size: 17, weight: .semibold))
                }.padding(.horizontal, 19).frame(height: 52)
                    .background(accent, in: RoundedRectangle(cornerRadius: 11))
            }.buttonStyle(.plain).accessibilityIdentifier("ex.map.area.\(areaID.rawValue)")
            ForEach(ExhibitionCatalog.games(in: areaID)) { game in
                Button { openGame(game.id) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(accent).frame(width: 10, height: 10)
                        Text(game.title).font(.system(size: 22, weight: .semibold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.80)
                        Spacer(minLength: 2)
                        if game.isPlayable {
                            Text(exhibition.status(for: game, workshop: workshop.state).title)
                                .font(.system(size: 18, weight: .semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(accent.opacity(0.55), in: Capsule())
                        } else {
                            Text("準備中").font(.system(size: 18)).foregroundStyle(ExhibitionStyle.muted)
                        }
                    }.padding(.horizontal, 14).frame(height: 45)
                        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(game.title)、\(exhibition.status(for: game, workshop: workshop.state).title)")
                    .accessibilityIdentifier("ex.game.\(game.id)")
            }
        }.padding(15).frame(width: width, height: height)
            .background(WorkshopChamfer(corner: 22).fill(accent.opacity(0.17))
                .shadow(color: ExhibitionStyle.ink.opacity(0.13), radius: 0, y: 7))
            .overlay(WorkshopChamfer(corner: 22).strokeBorder(ExhibitionStyle.ink.opacity(0.8), lineWidth: 2.5))
    }
}

struct ExhibitionWorkbookView: View {
    @ObservedObject var exhibition: ExhibitionStore
    @ObservedObject var workshop: WorkshopStore
    let close: () -> Void
    let openArtifact: () -> Void
    let openCircuit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            ExhibitionStyle.paper
            Circle().fill(ExhibitionStyle.color(.a).opacity(0.12)).frame(width: 660, height: 660).position(x: 380, y: 520)
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("日記").font(.system(size: 39, weight: .bold, design: .rounded))
                    Text("作ったものと、見つけたしくみを、ここに。")
                        .font(.system(size: 22)).foregroundStyle(ExhibitionStyle.muted)
                }
                Spacer()
                Button(action: close) { Label("閉じる", systemImage: "xmark") }
                    .buttonStyle(ExhibitionButtonStyle()).accessibilityIdentifier("ex.workbook.close")
                    .keyboardShortcut(.cancelAction)
            }.frame(width: 1460).position(x: 800, y: 78)
            IllustratedGuideView(speaking: false, reducedMotion: workshop.reducedMotion || systemReducedMotion, compact: false, notebook: true)
                .frame(width: 580, height: 620).position(x: 342, y: 530).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 24) {
                Label(workshop.state.completedArtifact != nil ? "01  ふたりの準備完了ランプ" : "最初の作品を、ここへ。", systemImage: "lightbulb")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                ZStack {
                    RoundedRectangle(cornerRadius: 15).fill(Color(red: 0.18, green: 0.22, blue: 0.26))
                    HStack(spacing: 36) {
                        VStack(spacing: 20) {
                            Label("A", systemImage: "circle.fill")
                            Label("B", systemImage: "circle.fill")
                        }.font(.system(size: 29, weight: .semibold)).foregroundStyle(ExhibitionStyle.color(.a))
                        Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.6))
                        Text(workshop.state.completedArtifact != nil ? "AND" : "？")
                            .font(.system(size: 31, weight: .semibold, design: .monospaced)).padding(27)
                            .background(ExhibitionStyle.paper, in: RoundedRectangle(cornerRadius: 12))
                        Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.6))
                        Image(systemName: workshop.state.completedArtifact != nil ? "lightbulb.fill" : "lightbulb")
                            .font(.system(size: 53, weight: .light))
                            .foregroundStyle(workshop.state.completedArtifact != nil ? ExhibitionStyle.color(.b) : .white.opacity(0.4))
                    }
                }.frame(height: 215).accessibilityHidden(true)
                Text(workshop.state.completedArtifact != nil ? "ふたりの準備がそろったときだけ、光る。\n保存した回路は、何度でも動かせるよ。" : "部品をつないで、光り方を確かめよう。\nできあがった回路が、このページに残るよ。")
                    .font(.system(size: 23)).lineSpacing(8)
                    .accessibilityIdentifier(workshop.state.completedArtifact == nil ? "ex.workbook.empty" : "ex.workbook.saved")
                HStack {
                    if workshop.state.completedArtifact != nil {
                        Button(action: openArtifact) { Label("作品を動かす", systemImage: "play.fill") }
                            .buttonStyle(ExhibitionButtonStyle(accent: ExhibitionStyle.color(.a)))
                            .accessibilityIdentifier("ex.workbook.artifact")
                    } else {
                        Button(action: openCircuit) { Label("論理回路へ", systemImage: "arrow.right") }
                            .buttonStyle(ExhibitionButtonStyle(accent: ExhibitionStyle.color(.a)))
                            .accessibilityIdentifier("ex.workbook.begin")
                    }
                    Spacer()
                    Text("作品  \(workshop.state.completedArtifact == nil ? 0 : 1)")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(ExhibitionStyle.muted)
                }
            }.padding(35).frame(width: 820)
                .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(ExhibitionStyle.ink.opacity(0.2), lineWidth: 1.5))
                .position(x: 1090, y: 490)
            HStack(spacing: 20) {
                ForEach(ExhibitionCatalog.areas) { area in
                    HStack(spacing: 7) {
                        Circle().fill(ExhibitionStyle.color(area.id)).frame(width: 12, height: 12)
                        Text("\(area.id.letter) \(ExhibitionCatalog.games(in: area.id).filter { exhibition.visitedGameIDs.contains($0.id) }.count) / 4")
                    }
                }
                Text("入口を見学").foregroundStyle(ExhibitionStyle.muted)
            }.font(.system(size: 21, weight: .medium, design: .rounded)).position(x: 1070, y: 825)
        }.foregroundStyle(ExhibitionStyle.ink)
    }
}
