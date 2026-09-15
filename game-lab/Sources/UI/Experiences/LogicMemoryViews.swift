import SwiftUI

struct LogicBitArtView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(LogicBitArtModel(stage: 1))
    var body: some View { ExperienceScreen(store: store, onExit: onExit) { model, send in LogicBitArtApparatus(model: model, send: send) } }
}

struct LogicBitArtApparatus: View {
    let model: LogicBitArtModel
    let send: (LogicBitArtModel.Action) -> Void
    static let colors: [Color] = [.white, .gray, .blue, .green, .yellow, .cyan, .purple, .red, .orange]
    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 26) {
                VStack(spacing: 10) {
                    Text(model.pixels.count == 1 ? "ひとつの点" : "わたしの絵 · 4 × 4　［\(model.selected / 4 + 1), \(model.selected % 4 + 1)］").foregroundStyle(.white).font(.headline)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(model.pixels.count == 1 ? 210 : 67), spacing: 8), count: model.pixels.count == 1 ? 1 : 4), spacing: 8) {
                        ForEach(model.pixels.indices, id: \.self) { index in
                            Button { send(.select(index)) } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(Self.colors[model.colors[index]].gradient)
                                    RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.5), lineWidth: 6)
                                    Text(String(model.pixels[index])).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(.black.opacity(0.65)).frame(maxWidth: .infinity,maxHeight: .infinity,alignment: .bottomTrailing).padding(9)
                                }.frame(width: model.pixels.count == 1 ? 210 : 67, height: model.pixels.count == 1 ? 210 : 67)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.selected == index ? Color.cyan : .clear, lineWidth: 3)).compositingGroup().shadow(color: .black, radius: 1, y: 5)
                                    .anchorPreference(key: LogicPixelAnchors.self,value: .bounds) { model.selected == index ? ["pixel": $0] : [:] }
                            }.buttonStyle(.plain).accessibilityLabel("画素\(index+1)、値\(model.pixels[index])、\(LogicBitArtModel.colorNames[model.colors[index]])")
                                .accessibilityIdentifier("bit.pixel.\(index)")
                        }
                    }.frame(width: 310, height: 300)
                        .transformAnchorPreference(key: LogicPixelAnchors.self,value: .bounds) { anchors,bounds in anchors["picture"] = bounds }
                        .background(LogicMachineHousing().padding(-10))
                }
                ExperienceDevice(title: "この画素の合図", active: true) {
                    VStack(spacing: 20) {
                        HStack(spacing: 10) {
                            ForEach(Array((0..<model.bits).reversed()), id: \.self) { bit in
                                Button { send(.toggle(bit)) } label: {
                                    VStack(spacing: 9) {
                                        Text(String(1 << bit)).font(.headline)
                                        Capsule().fill((model.value & (1 << bit)) != 0 ? ExperienceStyle.cyan : Color.gray).frame(width: 25,height: 52).overlay(Capsule().stroke(.black.opacity(0.5),lineWidth: 3))
                                        Text((model.value & (1 << bit)) != 0 ? "1" : "0").font(.title2.monospacedDigit().bold())
                                    }.frame(width: 45,height: 115)
                                }.buttonStyle(LogicCompactButtonStyle()).accessibilityIdentifier("bit.toggle.\(bit)")
                            }
                        }
                        Text("\(model.binary) = \(model.value)").font(.system(size: 31,weight: .bold,design: .monospaced))
                        Text("\(model.pixels.count)画素 × \(model.bits)bit = \(model.totalBits)bit").font(.system(size: 18,weight: .medium))
                    }.frame(width: 280,height: 252)
                }.frame(width: 325,height: 323)
                    .anchorPreference(key: LogicPixelAnchors.self,value: .bounds) { ["encoder": $0] }
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.stage == 4 ? "目標の9色" : "色の約束 \(model.mappingB ? "B" : "A")").font(.headline).foregroundStyle(.white)
                    if model.stage == 4 {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(41), spacing: 4), count: 4),spacing: 4) {
                            ForEach(LogicBitArtModel.target.indices,id: \.self) { i in
                                ZStack { Rectangle().fill(Self.colors[LogicBitArtModel.target[i]]); Text(String(LogicBitArtModel.target[i])).font(.caption.bold()).foregroundStyle(.black) }.frame(width: 41,height: 35)
                            }
                        }.frame(width: 185)
                    }
                    if model.stage != 4 {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(49),spacing: 6),count: 4),spacing: 6) {
                        ForEach(model.palette.indices,id: \.self) { i in
                            Button { send(.chooseValue(i)) } label: {
                                VStack(spacing: 3) { RoundedRectangle(cornerRadius: 3).fill(Self.colors[model.palette[i]]).frame(width: 33,height: 25); Text(String(repeating: "0", count: max(0, model.bits - String(i,radix: 2).count)) + String(i,radix: 2)).font(.system(size: 12,weight: .bold,design: .monospaced)) }.frame(width: 35,height: 39)
                            }.buttonStyle(LogicCompactButtonStyle(primary: model.value == i)).accessibilityLabel("値\(i)、\(LogicBitArtModel.colorNames[model.palette[i]])")
                        }
                    }.frame(width: 220)
                    } else {
                        Text("下の色札で、選んだ符号の色を決めよう。\n同じ符号の点も一緒に変わるよ。").font(.system(size: 16)).foregroundStyle(.white.opacity(0.7)).frame(width: 220)
                    }
                }.frame(width: 280)
            }.frame(height: 340)
                .overlayPreferenceValue(LogicPixelAnchors.self) { anchors in
                    GeometryReader { proxy in
                        if let selected = anchors["pixel"], let picture = anchors["picture"], let encoder = anchors["encoder"] {
                            LogicPixelConnection(pixel: proxy[selected],picture: proxy[picture],encoder: proxy[encoder])
                        }
                    }.allowsHitTesting(false)
                }
            if model.stage >= 4 && !model.comparisonMode {
                HStack(spacing: 6) {
                    Text("選んだ符号の色").foregroundStyle(.white).font(.system(size: 15,weight: .bold))
                    ForEach(LogicBitArtModel.colorNames.indices,id: \.self) { color in
                        Button { send(.assignColor(color)) } label: { HStack(spacing: 3) { Circle().fill(Self.colors[color]).frame(width: 13,height: 13); Text(LogicBitArtModel.colorNames[color]) }.font(.system(size: 13,weight: .bold)) }.buttonStyle(LogicCompactButtonStyle())
                    }
                }
            }
            HStack(spacing: 14) {
                Button { send(.record) } label: { Label("今の結果を記録",systemImage: "pencil.line") }.buttonStyle(LogicCompactButtonStyle(primary: true)).accessibilityIdentifier("bit.record")
                if model.stage == 3 { Button("約束を切り替える") { send(.switchMapping) }.buttonStyle(LogicCompactButtonStyle()).accessibilityIdentifier("bit.mapping") }
                if model.stage >= 4 && !model.comparisonMode {
                    Button("合図を1本足す") { send(.addBit) }.buttonStyle(LogicCompactButtonStyle()).disabled(model.bits == 4)
                    Button("1本減らす") { send(.removeBit) }.buttonStyle(LogicCompactButtonStyle()).disabled(model.bits == 1)
                }
                if model.stage == 5 {
                    Button("2色で比べる") { send(.beginComparison) }.buttonStyle(LogicCompactButtonStyle())
                    if model.comparisonMode { Button("同じ絵を3bitに") { send(.expandComparison) }.buttonStyle(LogicCompactButtonStyle()).disabled(model.bits != 1) }
                }
                Spacer()
                Text(model.stage < 3 ? "発見 \(model.observedValues.count) / \(model.stage == 1 ? 2 : 8)" : model.stage == 3 ? "比較 \(model.mappingObservations.count) / 2" : "色と番号を見比べよう").foregroundStyle(.white.opacity(0.7)).font(.system(size: 17,weight: .medium))
            }
        }.padding(20).frame(width: 1160,height: 550)
    }
}

private struct LogicPixelAnchors: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue(),uniquingKeysWith: { _,new in new }) }
}

private struct LogicPixelConnection: View {
    let pixel: CGRect
    let picture: CGRect
    let encoder: CGRect
    var body: some View {
        Canvas { context,_ in
            // Route through the 8-point gaps between pixels, never over another colour tile.
            let start = CGPoint(x: pixel.maxX,y: pixel.midY)
            let cornerX = pixel.maxX + 4
            let gapY = pixel.maxY + 4
            let channelX = picture.maxX + 17
            let end = CGPoint(x: encoder.minX,y: encoder.midY)
            var path=Path();path.addLines([start,CGPoint(x: cornerX,y: start.y),CGPoint(x: cornerX,y: gapY),CGPoint(x: channelX,y: gapY),CGPoint(x: channelX,y: end.y),end])
            context.stroke(path,with: .color(.black.opacity(0.8)),style: StrokeStyle(lineWidth: 7,lineCap: .round,lineJoin: .round))
            context.stroke(path,with: .color(.cyan),style: StrokeStyle(lineWidth: 4,lineCap: .round,lineJoin: .round))
            context.stroke(path,with: .color(.white.opacity(0.65)),style: StrokeStyle(lineWidth: 1,lineCap: .round,lineJoin: .round))
            for point in [start,end] {
                context.fill(Path(ellipseIn: CGRect(x: point.x-6,y: point.y-6,width: 12,height: 12)),with: .color(.gray))
                context.fill(Path(ellipseIn: CGRect(x: point.x-3.5,y: point.y-3.5,width: 7,height: 7)),with: .color(.cyan))
            }
        }
    }
}

struct LogicMemorySwitchView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(LogicMemorySwitchModel(stage: 1))
    var body: some View { ExperienceScreen(store: store, onExit: onExit) { model,send in LogicMemorySwitchApparatus(model: model,send: send) } }
}

struct LogicMemorySwitchApparatus: View {
    let model: LogicMemorySwitchModel
    let send: (LogicMemorySwitchModel.Action) -> Void
    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                ExperienceDevice(title: "入力 D", subtitle: "いまの合図") {
                    HStack(spacing: 8) {
                        ForEach(model.input.indices,id: \.self) { index in
                            Button { send(.toggle(index)) } label: {
                                VStack(spacing: 12) {
                                    Capsule().fill(model.input[index] == 1 ? Color.cyan : Color.gray).frame(width: 30,height: 65).overlay(Capsule().stroke(.black.opacity(0.45),lineWidth: 4))
                                    Text(String(model.input[index])).font(.title.bold().monospacedDigit())
                                }.frame(width: 36,height: 114)
                            }.buttonStyle(LogicCompactButtonStyle()).disabled(!model.powered).accessibilityLabel("入力\(index+1)、\(model.input[index])").accessibilityIdentifier("memory-switch.input.\(index)")
                        }
                    }.frame(height: 145)
                }.frame(width: model.input.count == 1 ? 200 : 270,height: 257)
                ExperienceSignal(active: model.powered && model.input.contains(1)).frame(width: 34)
                ExperienceDevice(title: model.stage == 1 ? "そのまま通す" : "記憶 Q", subtitle: model.stage == 1 ? "記憶する箱はまだない" : "書くまで、値を保持", active: model.output.contains(1)) {
                    VStack(spacing: 17) {
                        Text(model.stage == 1 ? model.inputText : model.storedText).font(.system(size: 43,weight: .bold,design: .monospaced)).foregroundStyle(model.output.contains(1) ? ExperienceStyle.cyan : Color.white)
                            .frame(width: 185,height: 78).background(RoundedRectangle(cornerRadius: 8).fill(ExperienceStyle.dark)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray,lineWidth: 4))
                        if model.stage > 1 { Button { send(.write) } label: { Label("書く",systemImage: "pencil") }.buttonStyle(LogicCompactButtonStyle(primary: true)).disabled(!model.powered).accessibilityIdentifier("memory-switch.write") }
                    }.frame(height: 145)
                }.frame(width: 245,height: 257)
                ExperienceSignal(active: model.output.contains(1)).frame(width: 34)
                ExperienceDevice(title: "出力", subtitle: model.powered ? "いま見える値" : "電源OFF") {
                    HStack(spacing: 7) {
                        ForEach(model.output.indices,id: \.self) { i in
                            VStack(spacing: 12) {
                                Image(systemName: model.output[i] == 1 ? "lightbulb.fill" : "lightbulb").font(.system(size: model.output.count == 1 ? 55 : 32)).foregroundStyle(model.output[i] == 1 ? ExperienceStyle.cyan : ExperienceStyle.muted)
                                Text(model.output[i].map(String.init) ?? "?").font(.title.bold())
                            }
                        }
                    }.frame(height: 145)
                }.frame(width: 220,height: 257)
            }.frame(height: 275)
            HStack(spacing: 10) {
                Text("履歴").foregroundStyle(.white).font(.headline)
                ForEach(Array(model.events.suffix(4).enumerated()),id: \.offset) { _,event in
                    ExperienceDevice(title: event.title) {
                        Text("D \(event.input.map(String.init).joined())  \(model.stage == 1 ? "出力" : "Q") \(event.stored.map { $0.map(String.init) ?? "?" }.joined())").font(.system(size: 16,weight: .bold,design: .monospaced)).lineLimit(1)
                    }.frame(width: 225,height: 78)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 13) {
                Button { send(.record) } label: { Label("今の結果を記録",systemImage: "pencil.line") }.buttonStyle(LogicCompactButtonStyle(primary: true)).accessibilityIdentifier("memory-switch.record")
                if model.stage > 1 { Button("相棒に入力を切り替えてもらう") { send(.toggle(0)) }.buttonStyle(LogicCompactButtonStyle()).disabled(!model.powered) }
                if model.stage == 5 {
                    Button(model.powered ? "電源を切る" : "電源を入れる") { send(.power) }.buttonStyle(LogicCompactButtonStyle())
                    Button("コピーを保存") { send(.saveCopy) }.buttonStyle(LogicCompactButtonStyle()).disabled(!model.powered)
                    Button("コピーを戻す") { send(.restoreCopy) }.buttonStyle(LogicCompactButtonStyle()).disabled(model.copy == nil || !model.powered)
                }
                Spacer(minLength: 0)
            }
        }.padding(20).frame(width: 1160,height: 550)
    }
}
