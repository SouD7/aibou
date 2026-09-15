import SwiftUI
import UniformTypeIdentifiers

struct ParallelFactoryExperienceView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(ParallelFactoryModel(stage:1))
    var body: some View { ExperienceScreen(store:store,onExit:onExit) { model,send in ParallelFactoryApparatus(model:model,send:send) } }
}

struct ParallelFactoryApparatus: View {
    let model: ParallelFactoryModel
    let send: (ParallelFactoryModel.Action) -> Void
    @State private var playbackEpoch = 0
    private var selected: Int? { model.inspectedTask }
    var body: some View {
        VStack(spacing:14) {
            HStack(spacing:12) {
                Text("働き手の数").foregroundStyle(.white).font(.system(size:18,weight:.bold))
                ForEach([1,2,4],id:\.self) { n in
                    Button { send(.workers(n)) } label: { Label("\(n)人",systemImage:n == 1 ? "person.fill" : "person.2.fill") }
                        .buttonStyle(ExperienceButtonStyle(primary:model.workers == n)).disabled(model.stage == 5 && n != 2)
                }
                Spacer()
                Text("札を選ぶ → レーンへ配置  /  ドラッグもできる").font(.system(size:14)).foregroundStyle(.white.opacity(0.65))
            }.frame(height:48)
            HStack(spacing:14) {
                preparationStation.frame(width:132,height:310)
                VStack(spacing:10) {
                    ForEach(0..<model.workers,id:\.self) { lane in
                        HStack(spacing:7) {
                            ZStack(alignment:.bottomLeading) {
                                ParallelRobotWorker(active:model.activeTasks.contains { id in model.laneTasks(lane).contains { $0.id == id } },tick:model.tick,compact:model.workers == 4)
                                    .frame(width:60,height:model.workers == 4 ? 45 : 82)
                                Text("\(lane+1)").font(.system(size:12,weight:.bold,design:.monospaced)).foregroundStyle(ExperienceStyle.cyan).padding(3).background(ExperienceStyle.dark,in:Circle())
                            }
                            HStack(spacing:6) {
                                ForEach(model.laneTasks(lane)) { task in taskTile(task).frame(width:90,height:model.workers == 4 ? 49 : 83) }
                                Spacer(minLength:2)
                            }
                            Button { if let selected { send(.assign(selected,lane)) } } label: { Image(systemName:"arrow.down.to.line").font(.system(size:18)) }
                                .buttonStyle(.plain).foregroundStyle(selected == nil ? .gray : ExperienceStyle.cyan).disabled(selected == nil).frame(width:28)
                                .accessibilityLabel("選んだ札をレーン\(lane+1)に置く")
                        }.padding(8).frame(maxWidth:.infinity,maxHeight:.infinity)
                            .background(ParallelMachineHousing())
                            .onDrop(of:[UTType.text],isTargeted:nil) { providers in parallelAcceptDrop(providers) { if let id = Int($0) { send(.assign(id,lane)) } } }
                    }
                }.frame(width:740,height:310)
                assemblyStation.frame(width:212,height:310)
            }
            HStack {
                ExperiencePlaybackControls(canStep:!model.runFinished && model.tick < 40) { send(.step) }
                    .id("\(model.stage)-\(model.workers)-\(model.queueOrder)-\(model.tasks.map(\.lane))-\(playbackEpoch)")
                Button("同じ配置で最初から") { playbackEpoch += 1; send(.reset) }.buttonStyle(ExperienceButtonStyle())
                Spacer()
                Text("\(model.completedCount) / \(model.tasks.count) 工程").font(.system(size:25,weight:.bold,design:.rounded)).foregroundStyle(ExperienceStyle.cyan)
            }.frame(height:56)
            ParallelTrialStrip(trials:model.trials)
        }.padding(22).frame(width:1160,height:550)
            .onChange(of:model.tick) { if $0 == 0 { playbackEpoch += 1 } }
    }
    private var preparationTask: ParallelFactoryTask? { model.tasks.first { ["準備","配布"].contains($0.title) } }
    private var assemblyTask: ParallelFactoryTask? { model.tasks.first { ["組立","集約"].contains($0.title) } }
    private var preparationStation: some View {
        VStack(spacing:12) {
            Text(preparationTask?.title ?? "材料").font(.system(size:19,weight:.bold)).foregroundStyle(ExperienceStyle.paper)
            Button {
                if let task = preparationTask { send(.inspect(task.id)) }
            } label: {
                ZStack {
                    WorkshopChamfer(corner:9).fill(ExperienceStyle.paper.gradient)
                        .overlay(WorkshopChamfer(corner:9).strokeBorder(Color.gray,lineWidth:3))
                    VStack(spacing:12) {
                        HStack(spacing:4) { ForEach(0..<3,id:\.self) { _ in Capsule().fill(ExperienceStyle.dark).frame(width:16,height:4) } }
                        ZStack {
                            RoundedRectangle(cornerRadius:6).fill(ExperienceStyle.dark).frame(width:75,height:66)
                            Image(systemName:preparationTask?.isDone == true ? "shippingbox.fill" : "shippingbox").font(.system(size:42)).foregroundStyle(preparationTask?.isDone == true ? ExperienceStyle.cyan : ExperienceStyle.paper)
                        }
                        Capsule().fill(preparationTask?.isDone == true ? ExperienceStyle.cyan : .gray).frame(width:61,height:5)
                    }
                }.frame(width:102,height:137).compositingGroup().shadow(color:.black.opacity(0.5),radius:0,x:2,y:5)
            }.buttonStyle(.plain).disabled(preparationTask == nil).opacity(1)
            if let task = preparationTask {
                Text(task.isDone ? "準備できた" : "残り \(task.remaining)手").font(.system(size:15,weight:.bold)).foregroundStyle(task.isDone ? ExperienceStyle.cyan : .white)
                Text("札を押して\n工程を調べる").font(.system(size:12)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.6))
            } else {
                Text("同じ材料を\n分担して加工").font(.system(size:14)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75))
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(ParallelMachineHousing())
    }
    private var assemblyStation: some View {
        VStack(spacing:7) {
            HStack {
                Text(assemblyTask?.title ?? "できた工程").font(.system(size:18,weight:.bold))
                Spacer()
                Text("\(model.completedCount)/\(model.tasks.count)").font(.system(size:14,weight:.bold,design:.monospaced)).foregroundStyle(ExperienceStyle.cyan)
            }.foregroundStyle(ExperienceStyle.paper)
            HStack(spacing:8) {
                ForEach(model.tasks.filter { $0.title.hasPrefix("色") || model.stage == 3 }) { task in
                    VStack(spacing:6) {
                        Image(systemName:task.isDone ? "checkmark.square.fill" : "square").font(.system(size:23)).foregroundStyle(task.isDone ? ExperienceStyle.cyan : .gray)
                        Text(task.title.replacingOccurrences(of:"色",with:"").replacingOccurrences(of:"工程",with:"")).font(.system(size:13,weight:.bold)).foregroundStyle(.white)
                    }
                }
            }.frame(maxWidth:.infinity).padding(.vertical,7).background(RoundedRectangle(cornerRadius:8).fill(.black.opacity(0.45)).overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.gray,lineWidth:2)))
            if let id = selected,let task = model.tasks.first(where:{$0.id == id}) {
                VStack(spacing:4) {
                    Text(task.title).font(.system(size:18,weight:.bold)).foregroundStyle(ExperienceStyle.paper)
                    Text(task.prerequisites.isEmpty ? "先に必要な工程なし" : "先に必要：" + model.tasks.filter { task.prerequisites.contains($0.id) }.map(\.title).joined(separator:"・"))
                        .font(.system(size:12)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                    Text(model.waitingFor(task)).font(.system(size:12,weight:.semibold)).foregroundStyle(ExperienceStyle.cyan).lineLimit(2)
                }.frame(height:75)
                Button("一つ前へ") { send(.moveEarlier(id)) }.buttonStyle(ExperienceButtonStyle())
            } else {
                Image(systemName:assemblyTask?.isDone == true || model.runFinished ? "shippingbox.fill" : "shippingbox").font(.system(size:47)).foregroundStyle(assemblyTask?.isDone == true || model.runFinished ? ExperienceStyle.cyan : ExperienceStyle.paper)
                Text("札を押すと、先に必要な\n工程を調べられるよ。").font(.system(size:13)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
            }
        }.padding(14).frame(maxWidth:.infinity,maxHeight:.infinity).background(ParallelMachineHousing())
    }
    private func taskTile(_ task: ParallelFactoryTask) -> some View {
        Button { send(.inspect(task.id)) } label: {
            VStack(spacing:5) {
                HStack(spacing:5) { Image(systemName:task.isDone ? "checkmark.circle.fill" : task.prerequisites.isEmpty ? "drop.fill" : "link"); Text(task.title).lineLimit(1) }.font(.system(size:14,weight:.bold))
                Text(task.isDone ? "完了" : "残り \(task.remaining) / \(task.duration)手").font(.system(size:12,weight:.medium))
                if model.workers < 4 { Text(model.waitingFor(task)).font(.system(size:11)).lineLimit(1) }
            }.foregroundStyle(ExperienceStyle.ink).frame(maxWidth:.infinity,maxHeight:.infinity)
                .background(WorkshopChamfer(corner:8).fill(task.isDone ? ExperienceStyle.cyan : ExperienceStyle.paper))
                .overlay(WorkshopChamfer(corner:8).strokeBorder(selected == task.id ? ExperienceStyle.cyan : .gray,lineWidth:selected == task.id ? 3 : 1))
                .compositingGroup()
                .shadow(color:.black.opacity(0.4),radius:0,x:2,y:4)
        }.buttonStyle(.plain).onDrag { NSItemProvider(object:String(task.id) as NSString) }
            .accessibilityLabel("\(task.title)、\(model.waitingFor(task))、残り\(task.remaining)手")
    }
}
