import SwiftUI

struct ParallelPacketExperienceView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(ParallelPacketModel(stage:1))
    var body: some View { ExperienceScreen(store:store,onExit:onExit) { model,send in ParallelPacketApparatus(model:model,send:send) } }
}

struct ParallelPacketApparatus: View {
    let model: ParallelPacketModel
    let send: (ParallelPacketModel.Action) -> Void
    @State private var playbackEpoch = 0
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var returningReply: Bool { model.stage == 4 && model.packets.contains { $0.id % 2 == 0 && $0.sentAt != nil && !$0.delivered } }
    var body: some View {
        VStack(spacing:12) {
            HStack(spacing:18) {
                ExperienceDevice(title:model.stage == 4 ? "対話の順番" : "送り元",subtitle:model.stage == 4 ? "要求と返事を3往復" : "同じ\(model.count)通を送る") {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:7) {
                        ForEach(model.packets.filter {$0.sentAt == nil}) { packet in envelope(packet.id,color:.gray).frame(width:51,height:31) }
                    }.padding(7).frame(height:167,alignment:.top)
                        .background(RoundedRectangle(cornerRadius:7).fill(ExperienceStyle.dark).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(.gray,lineWidth:2)))
                }.frame(width:178,height:286)
                GeometryReader { g in
                    ZStack {
                        RoundedRectangle(cornerRadius:15).fill(.black.opacity(0.23)).overlay(RoundedRectangle(cornerRadius:15).strokeBorder(.white.opacity(0.15),lineWidth:2))
                        ForEach(0..<model.bandwidth,id:\.self) { lane in
                            let y = (CGFloat(lane)+0.5) * g.size.height / CGFloat(model.bandwidth)
                            ParallelTransportChannel(active:model.connected,returning:returningReply,tick:model.tick)
                                .frame(width:g.size.width-8,height:model.bandwidth == 4 ? 53 : 62).position(x:g.size.width/2,y:y)
                            if !model.connected {
                                Button { send(.connection(true)) } label: {
                                    Image(systemName:"link.badge.plus").font(.system(size:31)).foregroundStyle(ExperienceStyle.cyan)
                                        .frame(width:68,height:60).background(ExperienceStyle.dark,in:RoundedRectangle(cornerRadius:6))
                                        .overlay(RoundedRectangle(cornerRadius:6).strokeBorder(ExperienceStyle.cyan,lineWidth:2))
                                }.buttonStyle(.plain).position(x:g.size.width/2,y:y).accessibilityLabel("切れた道をつなぐ")
                            }
                        }
                        ForEach(model.packets.filter { !$0.delivered && $0.sentAt != nil }) { packet in
                            let progress = packet.lost ? 0.55 : min(1,max(0,Double(model.tick - (packet.sentAt ?? 0)) / Double(model.latency+1)))
                            let backwards = model.stage == 4 && packet.id % 2 == 0
                            let y = (CGFloat((packet.id-1) % model.bandwidth)+0.5) * g.size.height / CGFloat(model.bandwidth)
                            envelope(packet.id,color:packet.lost ? .gray : packet.id % 2 == 0 ? ExperienceStyle.amber : ExperienceStyle.cyan)
                                .overlay { if packet.lost { Image(systemName:"xmark.circle.fill").font(.system(size:26)).foregroundStyle(ExperienceStyle.coral) } }
                                .frame(width:62,height:46).position(x:40 + CGFloat(backwards ? 1-progress : progress) * (g.size.width-80),y:y)
                                .animation(reducedMotion ? nil : .easeInOut(duration:0.35),value:model.tick)
                        }
                    }
                }.frame(width:620,height:276)
                ExperienceDevice(title:model.stage == 4 ? "往復の記録" : "到着した便り",subtitle:"\(model.deliveredCount) / \(model.count)",active:model.deliveredCount > 0) {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:9) {
                        ForEach(1...model.count,id:\.self) { id in
                            ZStack {
                                RoundedRectangle(cornerRadius:5).fill(ExperienceStyle.dark).overlay(RoundedRectangle(cornerRadius:5).strokeBorder(.gray,lineWidth:2))
                                if model.packets[id-1].delivered { envelope(id,color:ExperienceStyle.cyan).padding(3) }
                                else { Text("\(id)").font(.system(size:16,weight:.bold)).foregroundStyle(.white.opacity(0.2)) }
                            }.frame(height:35)
                        }
                    }
                }.frame(width:222,height:286)
            }.padding(8).background(ParallelMachineHousing())
            HStack(spacing:14) {
                Text("道幅").font(.system(size:18,weight:.bold)).foregroundStyle(.white)
                ForEach(model.stage == 5 ? [2] : [1,4],id:\.self) { b in Button("\(b)個 / 手") { send(.bandwidth(b)) }.buttonStyle(ExperienceButtonStyle(primary:model.bandwidth == b)).disabled(![2,4].contains(model.stage)) }
                Text("追加の移動").font(.system(size:18,weight:.bold)).foregroundStyle(.white).padding(.leading,15)
                ForEach([1,3],id:\.self) { l in Button("\(l)手") { send(.latency(l)) }.buttonStyle(ExperienceButtonStyle(primary:model.latency == l)).disabled(![3,4].contains(model.stage)) }
                if model.stage == 5 { Button(model.retryEnabled ? "再送あり" : "再送なし") { send(.retry(!model.retryEnabled)) }.buttonStyle(ExperienceButtonStyle(primary:model.retryEnabled)) }
                Spacer(minLength:0)
            }.frame(height:56)
            HStack(spacing:12) {
                ExperiencePlaybackControls(canStep:model.connected && !model.runFinished && !model.stalled && model.tick < 64) { send(.step) }
                    .id("\(model.stage)-\(model.bandwidth)-\(model.latency)-\(model.retryEnabled)-\(model.connected)-\(playbackEpoch)")
                Button("同じ便りで最初から") { playbackEpoch += 1; send(.reset) }.buttonStyle(ExperienceButtonStyle())
                Spacer()
                Text("送り出す1手 ＋ 移動\(model.latency)手").font(.system(size:17,weight:.medium)).foregroundStyle(.white.opacity(0.7))
            }.frame(height:55)
            ParallelTrialStrip(trials:model.trials)
        }.padding(18).frame(width:1160,height:550)
            .onChange(of:model.tick) { if $0 == 0 { playbackEpoch += 1 } }
    }
    private func envelope(_ id: Int,color: Color) -> some View {
        GeometryReader { g in
            ZStack {
                WorkshopChamfer(corner:5).fill(LinearGradient(colors:[Color(white:0.76),Color(white:0.29),Color(white:0.48)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    .overlay(WorkshopChamfer(corner:5).strokeBorder(ExperienceStyle.ink,lineWidth:1.5))
                RoundedRectangle(cornerRadius:3).fill(color.gradient).padding(4)
                    .overlay(RoundedRectangle(cornerRadius:3).strokeBorder(.white.opacity(0.5),lineWidth:1).padding(5))
                Image(systemName:"envelope").resizable().scaledToFit().padding(7).foregroundStyle(ExperienceStyle.ink.opacity(0.35))
                ForEach(0..<2,id:\.self) { side in
                    Capsule().fill(Color(white:0.78)).frame(width:5,height:g.size.height*0.46)
                        .overlay(Capsule().strokeBorder(ExperienceStyle.ink,lineWidth:1))
                        .position(x:side == 0 ? 3 : g.size.width-3,y:g.size.height/2)
                }
                Text("\(id)").font(.system(size:19,weight:.bold,design:.rounded)).foregroundStyle(ExperienceStyle.ink)
                    .padding(.horizontal,4).background(.white.opacity(0.84),in:RoundedRectangle(cornerRadius:4))
            }.compositingGroup().shadow(color:.black.opacity(0.4),radius:0,x:1,y:3)
        }.accessibilityLabel("便り\(id)")
    }
}
