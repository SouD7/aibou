import SwiftUI
import UniformTypeIdentifiers

struct ParallelConnectionExperienceView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(ParallelConnectionModel(stage:1))
    var body: some View { ExperienceScreen(store:store,onExit:onExit) { model,send in ParallelConnectionApparatus(model:model,send:send) } }
}

struct ParallelConnectionApparatus: View {
    let model: ParallelConnectionModel
    let send: (ParallelConnectionModel.Action) -> Void
    @State private var selectedDevice = 0
    private var selection: ParallelConnection { model.connections.first(where:{$0.id == selectedDevice}) ?? model.connections[0] }
    var body: some View {
        VStack(spacing:12) {
            HStack(spacing:18) {
                ExperienceDevice(title:"ホスト装置",subtitle:"架空の条件カード") {
                    ForEach(model.availablePorts,id:\.self) { port in
                        Button { send(.port(selection.id,port)) } label: {
                            HStack {
                                Text(port).font(.system(size:22,weight:.bold)).frame(width:65,alignment:.leading)
                                Capsule().fill(ExperienceStyle.dark).frame(width:57,height:22).overlay(Capsule().strokeBorder(selection.port == port ? ExperienceStyle.cyan : .gray,lineWidth:3))
                            }.padding(.vertical,5)
                        }.buttonStyle(.plain).accessibilityLabel("\(selection.device)を\(port)へつなぐ")
                    }
                    Text(selection.port == "A" ? "映像なし / 容量4\n給電15W" : "映像あり / 容量8\n給電60W").font(.system(size:16,weight:.medium)).multilineTextAlignment(.center)
                }.frame(width:232,height:300)
                VStack(spacing:11) {
                    ForEach(model.connections) { connection in
                        connectionRow(connection)
                    }
                }.frame(width:844,height:300)
            }
            HStack(spacing:12) {
                Text("ケーブル").font(.system(size:18,weight:.bold)).foregroundStyle(.white).frame(width:84)
                ForEach(model.availableCables,id:\.self) { cable in
                    Button { send(.cable(selection.id,cable)) } label: {
                        HStack(spacing:12) {
                            ZStack { Circle().stroke(ExperienceStyle.ink,lineWidth:9).frame(width:39,height:37); RoundedRectangle(cornerRadius:3).fill(ExperienceStyle.cyan).frame(width:18,height:11).offset(x:18,y:15); Text(cable).font(.system(size:19,weight:.bold)).foregroundStyle(ExperienceStyle.ink) }
                            Text(model.cableDescription(cable)).font(.system(size:14,weight:.semibold)).multilineTextAlignment(.leading)
                        }.padding(10).frame(width:model.availableCables.count > 1 ? 283 : 600,height:72)
                            .foregroundStyle(ExperienceStyle.ink).background(ExperienceStyle.paper,in:RoundedRectangle(cornerRadius:9))
                            .overlay(RoundedRectangle(cornerRadius:9).strokeBorder(selection.cable == cable ? ExperienceStyle.cyan : .gray,lineWidth:selection.cable == cable ? 4 : 2))
                    }.buttonStyle(.plain).onDrag { NSItemProvider(object:cable as NSString) }.accessibilityLabel("ケーブル\(cable)、\(model.cableDescription(cable))")
                }
                Spacer(minLength:0)
            }.frame(height:76)
            HStack(spacing:12) {
                Button { send(.inspect) } label:{ Label("接続を確かめる",systemImage:"play.fill") }.buttonStyle(ExperienceButtonStyle(primary:true)).keyboardShortcut(.return,modifiers:[])
                if model.stage == 5 { Button(model.revealed ? "仕様を確認済み" : "仕様を見る") { send(.reveal) }.buttonStyle(ExperienceButtonStyle()).disabled(model.revealed) }
                Button(model.connectedIDs.contains(selection.id) ? "選んだ機器を外す" : "両端をつなぐ") { send(model.connectedIDs.contains(selection.id) ? .disconnect(selection.id) : .connect(selection.id)) }.buttonStyle(ExperienceButtonStyle())
                Spacer()
                if model.stage == 4 {
                    VStack(alignment:.trailing,spacing:4) {
                        Text("入口B1：\(portLoad("B1")) / 8").foregroundStyle(portLoad("B1") > 8 ? ExperienceStyle.coral : ExperienceStyle.cyan)
                        Text("入口B2：\(portLoad("B2")) / 8").foregroundStyle(portLoad("B2") > 8 ? ExperienceStyle.coral : ExperienceStyle.cyan)
                    }.font(.system(size:18,weight:.bold))
                } else { Text("形だけでなく、機能と必要量も確認").font(.system(size:15)).foregroundStyle(.white.opacity(0.6)) }
            }.frame(height:57)
        }.padding(22).frame(width:1160,height:550)
            .onChange(of:model.stage) { _ in selectedDevice = 0 }
    }
    private func portLoad(_ port: String) -> Int { model.connections.filter { model.connectedIDs.contains($0.id) && ($0.port == "ハブ" ? "B1" : $0.port) == port }.reduce(0) { $0 + model.requirement($1.device).capacity } }
    private func connectionRow(_ con: ParallelConnection) -> some View {
        let compact = model.connections.count > 1
        let isConnected = model.connectedIDs.contains(con.id)
        let checks = model.checks.filter { model.connections.count == 1 || $0.label.hasPrefix(con.device + "・") }
        let functional = !checks.isEmpty && checks.allSatisfy { $0.status == 1 } && !model.checks.contains { ($0.label.contains("共有") || $0.label.contains("物理接続")) && $0.status != 1 }
        let req = model.requirement(con.device)
        return HStack(spacing:16) {
            VStack(spacing:10) {
                HStack { Text(con.port); Image(systemName:isConnected ? "link" : "link.badge.plus"); Text(con.cable) }.font(.system(size:19,weight:.bold)).foregroundStyle(.white)
                ZStack {
                    Path { p in p.move(to:CGPoint(x:0,y:10)); p.addCurve(to:CGPoint(x:225,y:10),control1:CGPoint(x:85,y:compact ? 30 : 90),control2:CGPoint(x:145,y:compact ? 30 : 90)) }
                        .stroke(ExperienceStyle.ink,lineWidth:15)
                    Path { p in p.move(to:CGPoint(x:0,y:10)); p.addCurve(to:CGPoint(x:225,y:10),control1:CGPoint(x:85,y:compact ? 30 : 90),control2:CGPoint(x:145,y:compact ? 30 : 90)) }
                        .stroke(isConnected ? ExperienceStyle.cyan.opacity(0.75) : .gray,lineWidth:3)
                }.frame(width:230,height:compact ? 28 : 90)
            }.frame(width:245)
            Button { selectedDevice = con.id } label: {
                if compact {
                    HStack(spacing:15) {
                        Image(systemName:con.device == "画面" ? "display" : con.device == "カメラ" ? "camera.fill" : "externaldrive.fill")
                            .font(.system(size:28)).foregroundStyle(functional ? ExperienceStyle.cyan : ExperienceStyle.muted).frame(width:43)
                        VStack(alignment:.leading,spacing:7) {
                            Text(con.device).font(.system(size:21,weight:.bold))
                            Text("容量\(req.capacity)・\(req.power)W").font(.system(size:15,weight:.medium)).foregroundStyle(ExperienceStyle.muted)
                        }
                        Spacer(minLength:0)
                    }.padding(.horizontal,20).frame(maxWidth:.infinity,maxHeight:.infinity)
                        .foregroundStyle(ExperienceStyle.ink)
                        .background(WorkshopChamfer(corner:14).fill(LinearGradient(colors:[.white,ExperienceStyle.paper],startPoint:.topLeading,endPoint:.bottomTrailing)))
                        .overlay(WorkshopChamfer(corner:14).strokeBorder(selectedDevice == con.id ? ExperienceStyle.cyan : .gray,lineWidth:3))
                        .compositingGroup()
                        .shadow(color:.black.opacity(0.3),radius:0,x:2,y:5)
                } else {
                ExperienceDevice(title:con.device,subtitle:"必要：容量\(req.capacity) / 給電\(req.power)W",active:selectedDevice == con.id) {
                    HStack(spacing:15) {
                        Image(systemName:con.device == "画面" ? (functional ? "display" : "display.trianglebadge.exclamationmark") : con.device == "カメラ" ? "camera.fill" : "externaldrive.fill")
                            .font(.system(size:62)).foregroundStyle(functional ? ExperienceStyle.cyan : ExperienceStyle.muted)
                        Text(functional ? "届いた！" : isConnected ? (checks.isEmpty ? "未検査" : con.device == "画面" ? "映像なし" : "届かない") : "未接続").font(.system(size:20,weight:.bold))
                    }.frame(maxWidth:.infinity)
                }
                }
            }.buttonStyle(.plain).frame(width:compact ? 290 : 350,height:compact ? 92 : 263)
                .onDrop(of:[UTType.text],isTargeted:nil) { providers in parallelAcceptDrop(providers) { send(.cable(con.id,$0)) } }
                .accessibilityLabel("\(con.device)を選ぶ。必要容量\(req.capacity)、給電\(req.power)W")
            VStack(alignment:.leading,spacing:5) {
                if checks.isEmpty { Text("未検査").foregroundStyle(.white.opacity(0.5)) }
                ForEach(Array(checks.prefix(4))) { check in
                    HStack { Image(systemName:check.status < 0 ? "questionmark.circle" : check.status == 1 ? "checkmark.circle.fill" : "xmark.circle.fill"); Text(check.label.replacingOccurrences(of:con.device + "・",with:"")) }
                        .foregroundStyle(check.status == 1 ? ExperienceStyle.cyan : check.status == 0 ? ExperienceStyle.coral : ExperienceStyle.amber)
                }
            }.font(.system(size:compact ? 13 : 16,weight:.semibold)).frame(width:compact ? 125 : 185,alignment:.leading)
        }.frame(maxWidth:.infinity).frame(height:compact ? 92 : 278)
    }
}
