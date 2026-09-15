import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MemoryDockExperienceView: View {
    @StateObject private var store = ExperienceStore(MemoryDockModel(stage: 1))
    var onExit: () -> Void
    var body: some View { ExperienceScreen(store: store, onExit: onExit) { model, send in MemoryDockApparatus(model: model, send: send) } }
}

struct MemoryDockApparatus: View {
    let model: MemoryDockModel
    let send: (MemoryDockModel.Action) -> Void
    private var waitingDocuments: [MemoryDocument] { model.documents.filter { $0.workVersion == nil } }
    var body: some View {
        ZStack(alignment: .topLeading) {
            ExperienceDevice(title: "待機 / 保存データ") {
                VStack(spacing: 8) {
                    ForEach(waitingDocuments) { doc in
                        Button { send(.select(doc.id)) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: doc.icon).font(.system(size: 23))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(doc.title).font(.system(size: waitingDocuments.count > 3 ? 12 : 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                                    Text("\(doc.size)枠").font(.system(size: waitingDocuments.count > 3 ? 10 : 13, weight: .medium))
                                }
                                Spacer(minLength: 0)
                            }.padding(.horizontal, 17).frame(height: waitingDocuments.count > 3 ? 54 : 64)
                                .foregroundStyle(ExperienceStyle.ink)
                                .background(MemoryCartridgeShell(color: memoryColor(doc.id), selected: model.selectedID == doc.id))
                        }.buttonStyle(.plain).onDrag { NSItemProvider(object: doc.id as NSString) }
                        .accessibilityLabel("\(doc.title)、\(doc.size)枠、作業場にはありません")
                    }
                    if model.documents.allSatisfy({ $0.workVersion != nil }) { Text("待機なし").foregroundStyle(ExperienceStyle.muted).frame(maxHeight: .infinity) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }.frame(width: 180, height: 350).offset(x: 15, y: 25)

            ExperienceDevice(title: "RAM 作業ドック", subtitle: "\(model.usedRAM) / \(model.ramCapacity) 枠　　空き \(model.ramCapacity-model.usedRAM)", active: model.powered) {
                VStack(spacing: 18) {
                    HStack(spacing: 3) {
                        ForEach(model.documents.filter { $0.workVersion != nil }) { doc in
                            Button { send(.select(doc.id)) } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: doc.icon).font(.system(size: 27))
                                    Text(doc.title).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                                    Text("\(doc.size)枠 · v\(doc.workVersion ?? 0)").font(.system(size: 14, weight: .semibold))
                                    Label(doc.isDirty ? "未保存" : "保存済み", systemImage: doc.isDirty ? "pencil" : "checkmark.circle.fill").font(.system(size: 12, weight: .bold))
                                }.foregroundStyle(ExperienceStyle.ink).frame(width: CGFloat(doc.size) / CGFloat(model.ramCapacity) * 570 - 3, height: 160)
                                    .background(MemoryCartridgeShell(color: memoryColor(doc.id), units: doc.size, selected: model.selectedID == doc.id))
                            }.buttonStyle(.plain).onDrag { NSItemProvider(object: doc.id as NSString) }
                            .accessibilityLabel("\(doc.title)、\(doc.size)枠、作業v\(doc.workVersion ?? 0)、\(doc.isDirty ? "未保存" : "保存済み")")
                        }
                        ForEach(0..<max(0, model.ramCapacity-model.usedRAM), id: \.self) { _ in
                            ZStack {
                                RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.24)).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.22)))
                                VStack { Capsule().fill(.white.opacity(0.15)).frame(width: 12, height: 3); Spacer(); Capsule().fill(ExperienceStyle.amber.opacity(0.35)).frame(width: 12, height: 4) }.padding(.vertical, 12)
                            }.frame(width: 570/CGFloat(model.ramCapacity)-3, height: 160)
                        }
                    }.frame(width: 575, height: 166).padding(8).background(ExperienceStyle.dark, in: WorkshopChamfer())
                    Text(model.powered ? "選んだデータを操作しよう。ここへドラッグしてもひらけます。" : "電源 OFF · 作業中のデータは空です")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(ExperienceStyle.muted)
                }
            }.frame(width: 630, height: 330).offset(x: 210, y: 25)
                .memoryDrop { id in send(.select(id)); send(.open) }

            ExperienceDevice(title: "保存庫", subtitle: "\(model.usedStorage) / \(model.storageCapacity) 枠") {
                VStack(spacing: 10) {
                    ForEach(model.documents.filter { $0.savedVersion != nil }) { doc in
                        Button { send(.select(doc.id)) } label: {
                            HStack { Image(systemName: doc.icon); Text(doc.title); Spacer(); Text("v\(doc.savedVersion ?? 0)") }
                                .font(.system(size: 16, weight: .bold)).padding(.horizontal, 20).frame(height: 53).foregroundStyle(ExperienceStyle.ink)
                                .background(MemoryCartridgeShell(color: memoryColor(doc.id), selected: model.selectedID == doc.id))
                        }.buttonStyle(.plain).onDrag { NSItemProvider(object: doc.id as NSString) }
                    }
                    Spacer(minLength: 0)
                }
            }.frame(width: 270, height: 310).offset(x: 865, y: 25)
                .memoryDrop { id in send(.select(id)); send(.save) }

            HStack(spacing: 10) {
                Button("ひらく") { send(.open) }.buttonStyle(ExperienceButtonStyle(primary: true)).keyboardShortcut("o", modifiers: [])
                if model.stage == 1 { Button("編集") { send(.edit) }.buttonStyle(ExperienceButtonStyle()).keyboardShortcut("e", modifiers: []) }
                Button("保存") { send(.save) }.buttonStyle(ExperienceButtonStyle()).keyboardShortcut("s", modifiers: [])
                if model.stage == 2 { Button("閉じる") { send(.close(confirm: false)) }.buttonStyle(ExperienceButtonStyle()) }
                Button("観察を記録") { send(.observe) }.buttonStyle(ExperienceButtonStyle())
                if model.stage >= 4 {
                    Button("RAMを増やす") { send(.expandRAM) }.buttonStyle(ExperienceButtonStyle())
                    Button("保存庫を増やす") { send(.expandStorage) }.buttonStyle(ExperienceButtonStyle())
                }
                if model.stage == 3 || model.stage == 5 {
                    Button(model.powered ? "電源 OFF" : "電源 ON") { send(.power(confirm: false)) }.buttonStyle(ExperienceButtonStyle())
                }
            }.offset(x: 210, y: 365)

            if let confirmation = model.pendingConfirmation {
                HStack(spacing: 16) {
                    Text(confirmation).font(.system(size: 15, weight: .medium)).frame(maxWidth: 660, alignment: .leading)
                    Button(model.stage == 2 ? "変更を捨てて閉じる" : "電源を切る") { send(model.stage == 2 ? .close(confirm: true) : .power(confirm: true)) }.buttonStyle(ExperienceButtonStyle())
                }.foregroundStyle(ExperienceStyle.ink).padding(14).background(ExperienceStyle.paper, in: WorkshopChamfer()).offset(x: 210, y: 435)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("観察の記録").font(.system(size: 14, weight: .bold)).foregroundStyle(ExperienceStyle.cyan)
                    Text(model.observations.last ?? "操作した前後で、RAMと保存庫を見比べよう。").font(.system(size: 16)).foregroundStyle(.white)
                }.frame(width: 900, alignment: .leading).offset(x: 210, y: 450)
            }
        }.frame(width: 1160, height: 550, alignment: .topLeading)
    }
}

func memoryColor(_ id: String) -> Color {
    switch id { case "music", "B": return ExperienceStyle.purple; case "video", "C": return ExperienceStyle.amber; case "drawing", "new": return ExperienceStyle.coral; default: return ExperienceStyle.cyan }
}

extension View {
    func memoryDrop(_ accept: @escaping (String) -> Void) -> some View {
        onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                if let text { DispatchQueue.main.async { accept(text) } }
            }
            return true
        }
    }
}
