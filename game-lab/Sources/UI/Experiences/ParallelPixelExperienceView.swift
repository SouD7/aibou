import SwiftUI

struct ParallelPixelExperienceView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(ParallelPixelModel(stage:1))
    var body: some View { ExperienceScreen(store:store,onExit:onExit) { model,send in ParallelPixelApparatus(model:model,send:send) } }
}

struct ParallelPixelApparatus: View {
    let model: ParallelPixelModel
    let send: (ParallelPixelModel.Action) -> Void
    @State private var playbackEpoch = 0
    @State private var selectedPixel: Int?
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        VStack(spacing:10) {
            HStack(spacing:16) {
                ExperienceDevice(title:"CPU",subtitle:"1画素 / 手",active:!model.useGPU) {
                    ZStack {
                        RoundedRectangle(cornerRadius:8).fill(ExperienceStyle.dark).frame(width:111,height:167)
                            .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.gray,lineWidth:4))
                        HStack(spacing:54) { ForEach(0..<2,id:\.self) { _ in Capsule().fill(LinearGradient(colors:[.gray,.white,.gray],startPoint:.leading,endPoint:.trailing)).frame(width:8,height:146) } }
                        VStack(spacing:0) {
                            RoundedRectangle(cornerRadius:5).fill(LinearGradient(colors:[.gray,.white,.gray],startPoint:.leading,endPoint:.trailing)).frame(width:61,height:31)
                            Capsule().fill(LinearGradient(colors:[.gray,.white,.gray],startPoint:.leading,endPoint:.trailing)).frame(width:22,height:76)
                            Image(systemName:"pencil.tip").font(.system(size:30)).foregroundStyle(!model.useGPU && !model.runFinished ? ExperienceStyle.cyan : .gray)
                        }.offset(y:!model.useGPU && model.tick % 2 == 1 ? 6 : 0)
                            .animation(reducedMotion ? nil : .easeInOut(duration:0.22),value:model.tick)
                        RoundedRectangle(cornerRadius:4).fill(Color(white:0.6)).frame(width:91,height:13).offset(y:72)
                    }.frame(height:176)
                }.frame(width:190,height:300)
                ExperienceDevice(title:"元の絵",subtitle:"\(model.count)画素・同じ原画") {
                    ParallelPixelGrid(values:model.source,selected:selectedPixel,select:{selectedPixel=$0}).frame(width:160,height:160)
                }.frame(width:220,height:300)
                ExperienceDevice(title:"GPU",subtitle: model.stage == 4 ? "前の答えを待つ" : "4画素 / 手",active:model.useGPU) {
                    ParallelPress(active:model.useGPU && model.phase == "計算",tick:model.tick,singleDependency:model.stage == 4,processed:model.processed)
                }.frame(width:290,height:300)
                ExperienceDevice(title:"加工中の絵",subtitle: model.runFinished ? "出力できた" : model.phase == "読み戻し" ? "装置内・読み戻し待ち" : "\(model.processed) / \(model.count)画素") {
                    ParallelPixelGrid(values:model.pixels,processed:model.pass > 0 || model.runFinished ? model.count : model.processed,selected:selectedPixel,select:{selectedPixel=$0}).frame(width:160,height:160)
                }.frame(width:220,height:300)
            }.padding(12).background(ParallelMachineHousing())
            HStack(spacing:15) {
                ForEach(["準備","計算","読み戻し"],id:\.self) { phase in
                    HStack { Image(systemName:model.phase == phase ? "circle.inset.filled" : "circle"); Text(phase); if phase == "準備" { Text(model.useGPU ? "2手" : "0手") }; if phase == "読み戻し" { Text(model.useGPU ? "1手" : "0手") } }
                        .font(.system(size:18,weight:.semibold)).foregroundStyle(model.phase == phase ? ExperienceStyle.cyan : .white.opacity(0.45))
                    if phase != "読み戻し" { ExperienceSignal(active:model.phase == phase).frame(width:45) }
                }
                Spacer()
                if let i = selectedPixel,model.pixels.indices.contains(i) { Text("画素\(i+1)：\(model.source[i]) → \(model.pixels[i])").font(.system(size:17,weight:.bold)).foregroundStyle(.white) }
            }.padding(.horizontal,12).frame(height:40)
            HStack(spacing:12) {
                Button("CPU") { send(.device(false)) }.buttonStyle(ExperienceButtonStyle(primary:!model.useGPU)).disabled(model.stage == 5)
                Button("GPU") { send(.device(true)) }.buttonStyle(ExperienceButtonStyle(primary:model.useGPU))
                ExperiencePlaybackControls(canStep:!model.runFinished) { send(.step) }.id("\(model.stage)-\(model.useGPU)-\(model.resident)-\(playbackEpoch)")
                Button("同じ原画から") { playbackEpoch += 1; send(.reset) }.buttonStyle(ExperienceButtonStyle())
                if model.stage == 5 { Button(model.resident ? "✓ まとめる" : "毎回戻す") { send(.resident(!model.resident)) }.buttonStyle(ExperienceButtonStyle(primary:model.resident)) }
                Spacer()
            }.frame(height:54)
            ParallelTrialStrip(trials:model.trials)
        }.padding(16).frame(width:1160,height:550)
            .onChange(of:model.tick) { if $0 == 0 { playbackEpoch += 1 } }
    }
}
