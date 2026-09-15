import SwiftUI

struct ParallelBoardExperienceView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(ParallelBoardModel(stage:1))
    var body: some View { ExperienceScreen(store:store,onExit:onExit) { model,send in ParallelBoardApparatus(model:model,send:send) } }
}

struct ParallelBoardApparatus: View {
    let model: ParallelBoardModel
    let send: (ParallelBoardModel.Action) -> Void
    @State private var playbackEpoch = 0
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body: some View {
        VStack(spacing:12) {
            HStack(spacing:14) {
                Text("役割と、そのまとまり").font(.system(size:20,weight:.bold)).foregroundStyle(.white)
                if model.stage == 2 || model.stage == 4 { Button(model.soc ? "SoCのまとまり" : "別パッケージ") { send(.soc(!model.soc)) }.buttonStyle(ExperienceButtonStyle(primary:model.soc)) }
                if model.stage == 3 { Button(model.shared ? "共有メモリ" : "別々のメモリ") { send(.shared(!model.shared)) }.buttonStyle(ExperienceButtonStyle(primary:model.shared)) }
                if model.stage == 5 { Button(model.shifted ? "入れ替えた配置" : "元の配置") { send(.position(!model.shifted)) }.buttonStyle(ExperienceButtonStyle(primary:model.shifted)) }
                Spacer()
                Text("機能の枠は、実機の内部写真ではないよ").font(.system(size:14)).foregroundStyle(.white.opacity(0.5))
            }.frame(height:50)
            if model.stage >= 4 { sharedBoard } else { processingBoard }
            HStack(spacing:12) {
                ExperiencePlaybackControls(canStep:!model.runFinished && !(model.stage == 1 && !model.connected && model.tick >= 3)) { send(.step) }
                    .id("\(model.stage)-\(model.soc)-\(model.shared)-\(model.connected)-\(model.capacity)-\(model.shifted)-\(playbackEpoch)")
                Button("同じデータから") { playbackEpoch += 1; send(.reset) }.buttonStyle(ExperienceButtonStyle())
                if model.stage == 4 { ForEach([1,2],id:\.self) { n in Button("道幅 \(n)") { send(.capacity(n)) }.buttonStyle(ExperienceButtonStyle(primary:model.capacity == n)) } }
                Spacer()
            }.frame(height:55)
            ParallelTrialStrip(trials:model.trials)
        }.padding(20).frame(width:1160,height:550)
            .onChange(of:model.tick) { if $0 == 0 { playbackEpoch += 1 } }
    }
    private var sharedBoard: some View {
        HStack(spacing:0) {
            ExperienceDevice(title:"共有メモリ",subtitle:"原本は読み出しても残る") {
                HStack(spacing:16) {
                    ForEach(model.waitingUnits,id:\.self) { unit in ParallelDataCube(label:unit,color:unit.hasPrefix("CPU") ? ExperienceStyle.cyan : ExperienceStyle.purple) }
                }.padding(12).frame(height:100).frame(maxWidth:.infinity).background(ExperienceStyle.dark,in:RoundedRectangle(cornerRadius:9))
                Text("未送信の要求 \(model.waitingUnits.count)個").font(.system(size:17,weight:.medium))
            }.frame(width:300,height:275)
            VStack(spacing:14) {
                Text("共有路").font(.system(size:18,weight:.bold)).foregroundStyle(.white)
                ExperienceSignal(active:model.tick > 0).frame(width:192,height:25)
                Text("\(model.capacity)個 / 手").font(.system(size:23,weight:.bold,design:.rounded)).foregroundStyle(ExperienceStyle.cyan)
            }.frame(width:205)
            ZStack {
                RoundedRectangle(cornerRadius:18).fill(model.soc ? ExperienceStyle.cyan.opacity(0.12) : .clear).overlay(RoundedRectangle(cornerRadius:18).strokeBorder(model.soc ? ExperienceStyle.cyan : .gray.opacity(0.4),lineWidth:3))
                VStack(spacing:12) {
                    Text(model.soc ? "SoC" : "別のパッケージ").font(.system(size:22,weight:.bold)).foregroundStyle(.white)
                    HStack(spacing:20) {
                        receiver(model.shifted ? "GPU" : "CPU")
                        receiver(model.shifted ? "CPU" : "GPU")
                    }.animation(reducedMotion ? nil : .easeInOut(duration:0.3),value:model.shifted)
                }.padding(18)
            }.frame(width:530,height:290)
        }.frame(height:307)
    }
    private func receiver(_ name: String) -> some View {
        let received = name == "CPU" ? model.cpuReceived : model.gpuReceived
        return ExperienceDevice(title:name,active:received > 0) {
            HStack { ForEach(0..<received,id:\.self) { i in ParallelDataCube(label:"\(i+1)",color:name == "CPU" ? ExperienceStyle.cyan : ExperienceStyle.purple,done:true) }; if received == 0 { Image(systemName:"square.dashed").font(.system(size:36)).foregroundStyle(.gray) } }.padding(10).frame(height:75).background(ExperienceStyle.dark,in:RoundedRectangle(cornerRadius:7))
            Text("\(received) / 2").font(.system(size:30,weight:.bold,design:.rounded))
        }.frame(width:232,height:221)
    }
    private var processingBoard: some View {
        VStack(spacing:15) {
            ZStack {
                if model.stage == 2 && model.soc {
                    RoundedRectangle(cornerRadius:16).fill(ExperienceStyle.cyan.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(ExperienceStyle.cyan,lineWidth:3))
                        .frame(width:734,height:204)
                        .overlay(alignment:.top) { Text("SoCの中の役割").font(.system(size:13,weight:.bold)).foregroundStyle(ExperienceStyle.cyan).padding(.horizontal,12).background(ExperienceStyle.dark).offset(y:-7) }
                }
                HStack(spacing:10) {
                ForEach(Array(model.processLabels.enumerated()),id:\.offset) { i,label in
                    if i > 0 { ExperienceSignal(active:model.tick > i).frame(width:22) }
                    ExperienceDevice(title:label,subtitle:"\(i+1)手目",active:model.tick > i) {
                        Image(systemName:model.tick > i ? "checkmark.circle.fill" : i == model.tick ? "cube.fill" : "cube").font(.system(size:model.stage == 3 ? 45 : 32)).foregroundStyle(model.tick > i ? ExperienceStyle.cyan : ExperienceStyle.muted)
                    }.frame(width:model.stage == 3 ? 285 : 148,height:172)
                }
                }
            }.frame(height:210)
            HStack {
                Label(model.soc ? "CPUとGPUは同じSoCにまとめられている" : "CPUとGPUは別パッケージ",systemImage:"square.stack.3d.up").font(.system(size:17,weight:.medium)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                if model.stage == 1 { Button(model.connected ? "RAM → GPU 接続済み" : "RAM → GPU をつなぐ") { send(.connect(!model.connected)) }.buttonStyle(ExperienceButtonStyle(primary:!model.connected)) }
                if model.stage == 3 { Text(model.shared ? "同じ原本を使う・コピー0手" : "別の領域へコピー1手").font(.system(size:18,weight:.bold)).foregroundStyle(ExperienceStyle.cyan) }
            }.frame(height:58)
        }.frame(height:307)
    }
}
