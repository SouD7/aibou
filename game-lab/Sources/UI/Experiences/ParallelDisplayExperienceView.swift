import SwiftUI

struct ParallelDisplayExperienceView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(ParallelDisplayModel(stage:1))
    var body: some View { ExperienceScreen(store:store,onExit:onExit) { model,send in ParallelDisplayApparatus(model:model,send:send) } }
}

struct ParallelDisplayApparatus: View {
    let model: ParallelDisplayModel
    let send: (ParallelDisplayModel.Action) -> Void
    @State private var playbackEpoch = 0
    private var visibleFrames: [ParallelFrame] { Array(model.displayed.dropFirst(model.windowStart).prefix(6)) }
    private var originals: [ParallelFrame] {
        let start = visibleFrames.first?.sourceQuantum ?? 0
        return Array(model.generated.filter { $0.quantum >= start }.prefix(6))
    }
    var body: some View {
        VStack(spacing:12) {
            HStack(spacing:18) {
                ExperienceDevice(title:"生成 \(model.fps) FPS",subtitle:"新しい絵を作る") {
                    HStack(spacing:8) {
                        if model.stage == 1 { ForEach([15,30],id:\.self) { n in Button("\(n)") { send(.fps(n)) }.buttonStyle(ExperienceButtonStyle(primary:model.fps == n)) } }
                        else { Image(systemName:"film.stack").font(.system(size:35)).foregroundStyle(ExperienceStyle.ink); Text("\(model.fps)").font(.system(size:36,weight:.bold,design:.rounded)) }
                    }
                }.frame(width:252,height:170)
                ExperienceDevice(title:"模型の映像",subtitle:model.highResolution ? "128 × 72画素" : "64 × 36画素",active:true) {
                    GeometryReader { g in
                        ZStack(alignment:.leading) {
                            RoundedRectangle(cornerRadius:7).fill(ExperienceStyle.dark)
                            Rectangle().fill(.white.opacity(0.7)).frame(height:2).padding(.horizontal,15)
                            Circle().fill(ExperienceStyle.cyan).frame(width:27,height:27).shadow(color:.cyan.opacity(0.5),radius:8)
                                .offset(x:15 + CGFloat(model.displayed.last?.position ?? 0) * max(0,g.size.width - 57))
                        }
                    }.frame(height:43)
                }.frame(width:400,height:170)
                ExperienceDevice(title:"更新 \(model.hz) Hz",subtitle:"利用できる最新の絵を出す") {
                    HStack(spacing:7) {
                        if model.stage == 2 || model.stage == 3 {
                            ForEach(model.stage == 2 ? [30,60,120] : [30,60],id:\.self) { n in Button("\(n)") { send(.hz(n)) }.buttonStyle(ExperienceButtonStyle(primary:model.hz == n)) }
                        } else { Image(systemName:"display").font(.system(size:33)); Text("\(model.hz)").font(.system(size:36,weight:.bold,design:.rounded)) }
                    }
                }.frame(width:330,height:170)
            }
            VStack(spacing:10) {
                filmRow("作った絵",frames:originals,selectable:false)
                filmRow("画面の更新",frames:visibleFrames,selectable:true)
            }.frame(height:164)
            HStack(spacing:10) {
                ExperiencePlaybackControls(canStep:!model.runFinished) { send(.step) }.id("\(model.stage)-\(model.requestedFPS)-\(model.hz)-\(model.highResolution)-\(model.boosted)-\(playbackEpoch)")
                Button("最初の1秒から") { playbackEpoch += 1; send(.reset) }.buttonStyle(ExperienceButtonStyle())
                if model.stage >= 4 { Button(model.highResolution ? "128 × 72" : "64 × 36") { send(.resolution(!model.highResolution)) }.buttonStyle(ExperienceButtonStyle(primary:model.highResolution)) }
                if model.stage == 5 { Button(model.boosted ? "能力 ×2" : "能力 ×1") { send(.capacity(!model.boosted)) }.buttonStyle(ExperienceButtonStyle(primary:model.boosted)) }
                Spacer(minLength:0)
                Button { send(.window(model.windowStart - 6)) } label: { Image(systemName:"chevron.left") }.buttonStyle(ExperienceButtonStyle()).disabled(model.windowStart == 0).accessibilityLabel("前の6更新")
                Button { send(.window(model.windowStart + 6)) } label: { Image(systemName:"chevron.right") }.buttonStyle(ExperienceButtonStyle()).disabled(model.windowStart >= max(0,model.displayed.count - 6)).accessibilityLabel("次の6更新")
            }.frame(height:55)
            HStack {
                Text("コマ番号と時刻で比較").font(.system(size:14)).foregroundStyle(.white.opacity(0.65))
                ForEach(Array(model.trials.suffix(3))) { trial in
                    Text(trial.label).font(.system(size:12,weight:.semibold)).padding(.horizontal,8).padding(.vertical,6)
                        .foregroundStyle(ExperienceStyle.ink).background(ExperienceStyle.paper,in:RoundedRectangle(cornerRadius:5))
                }
                Spacer()
                Text("模型の1秒を観察").font(.system(size:14,weight:.semibold)).foregroundStyle(ExperienceStyle.cyan)
            }.frame(height:26)
        }.padding(20).frame(width:1160,height:550)
            .onChange(of:model.quantum) { if $0 == 0 { playbackEpoch += 1 } }
    }
    private func filmRow(_ label: String, frames: [ParallelFrame],selectable: Bool) -> some View {
        HStack(spacing:8) {
            Text(label).font(.system(size:17,weight:.bold)).foregroundStyle(.white).frame(width:118,alignment:.leading)
            HStack(spacing:8) {
                if frames.isEmpty { Text("1更新ずつ進めると、ここにコマが残るよ").font(.system(size:16)).foregroundStyle(.white.opacity(0.4)).frame(maxWidth:.infinity,minHeight:63) }
                ForEach(frames) { frame in
                    Button {
                        if selectable,let i = model.displayed.firstIndex(where:{$0.quantum == frame.quantum}) { send(.inspect(i)) }
                    } label: {
                        VStack(spacing:3) {
                            HStack { Text("F\(frame.frameID)").bold(); Spacer(); Text("\(String(format:"%.0f",Double(frame.quantum)*1000/120))ms") }.font(.system(size:12,design:.monospaced))
                            GeometryReader { g in
                                ZStack(alignment:.leading) { RoundedRectangle(cornerRadius:3).fill(ExperienceStyle.dark); Rectangle().fill(.white.opacity(0.6)).frame(height:1).padding(.horizontal,5); Circle().fill(ExperienceStyle.cyan).frame(width:13,height:13).offset(x:5 + CGFloat(frame.position) * max(0,g.size.width-23)) }
                            }.frame(height:30)
                        }.padding(8).frame(width:139,height:69).foregroundStyle(ExperienceStyle.ink).background(ExperienceStyle.paper,in:RoundedRectangle(cornerRadius:5))
                    }.buttonStyle(.plain).accessibilityLabel("\(label)、フレーム\(frame.frameID)、時点\(frame.quantum)")
                }
                Spacer(minLength:0)
            }.padding(7).background(.black.opacity(0.35),in:RoundedRectangle(cornerRadius:7))
        }.frame(height:77)
    }
}
