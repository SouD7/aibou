import Foundation

public struct MemoryDocument: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var size: Int
    public var workVersion: Int?
    public var savedVersion: Int?
    public var icon: String
    public var isDirty: Bool { workVersion != nil && workVersion != savedVersion }
}

public struct MemoryDockModel: ExperienceModel {
    public static let gameID = "memory-dock"
    public enum Action { case select(String), open, edit, save, close(confirm: Bool), power(confirm: Bool), expandRAM, expandStorage, observe }
    public private(set) var stage: Int
    public private(set) var documents: [MemoryDocument]
    public private(set) var selectedID = "photo"
    public private(set) var powered = true
    public private(set) var ramCapacity: Int
    public private(set) var storageCapacity: Int
    public private(set) var observations: [String] = []
    public private(set) var evidence: Set<String> = []
    public private(set) var pendingConfirmation: String?
    public private(set) var message = ""
    public var usedRAM: Int { documents.filter { $0.workVersion != nil }.reduce(0) { $0 + $1.size } }
    public var usedStorage: Int { documents.filter { $0.savedVersion != nil }.reduce(0) { $0 + $1.size } }
    public var selected: MemoryDocument? { documents.first { $0.id == selectedID } }
    public var metrics: [ExperienceMetric] {
        [.init("RAM", "\(usedRAM) / \(ramCapacity) 枠", detail: "空き \(ramCapacity-usedRAM) 枠"), .init("保存庫", "\(usedStorage) / \(storageCapacity) 枠"), .init("作業版", selected?.workVersion.map { "v\($0)" } ?? "なし"), .init("保存版", selected?.savedVersion.map { "v\($0)" } ?? "なし")]
    }
    public var isValid: Bool {
        (1...5).contains(stage) && (1...20).contains(ramCapacity) && (1...24).contains(storageCapacity)
        && (1...8).contains(documents.count) && Set(documents.map(\.id)).count == documents.count
        && documents.allSatisfy { (1...4).contains($0.size) && ($0.workVersion == nil || (1...3).contains($0.workVersion!)) && ($0.savedVersion == nil || (1...3).contains($0.savedVersion!)) }
        && usedRAM <= ramCapacity && usedStorage <= storageCapacity && (powered || usedRAM == 0)
        && documents.contains { $0.id == selectedID } && observations.count <= 30
    }
    public var stageTitle: String { ["開いて編集", "保存と空き", "電源を切ると", "どちらを増やす", "保存先がいっぱい"][stage-1] }
    public var goal: String { ["写真をひらいて編集。作業版と保存版の違いを記録してから保存しよう。", "保存済みの写真を残して、待っているお絵描きを始めよう。", "写真v3を保存し、電源OFF→ONのあとでもう一度ひらこう。", "保存先だけを増やした結果を観察してから、二つの仕事を同時にひらこう。", "RAMだけを増やした結果を観察してから写真を保存し、再起動してひらこう。"][stage-1] }
    public var hints: [String] {
        switch stage {
        case 1: return ["保存庫と作業場の写真は、同じ版かな？", "『編集』は作業場だけを変えるよ。変わったあと『観察を記録』。", "写真をひらく→編集→観察を記録→保存、の順に試そう。"]
        case 2: return ["残したいものと、いま使うものを分けよう。", "写真は保存庫にもあるよ。", "写真を『閉じる』と3枠空くよ。お絵描きを選んで『ひらく』。"]
        case 3: return ["切る前に、保存版を見てみよう。", "作業v3と保存v2は違うね。", "写真を保存→電源OFF→ON→写真をひらく。"]
        case 4: return ["足りないのは、どちらの置き場かな？", "保存先だけを増やして、新しい仕事がひらくか確かめよう。", "保存庫を増やす→新規をひらく→RAMを増やす→新規をひらく。"]
        default: return ["写真は作業中だけど、保存先に3枠あるかな？", "RAMだけを増やして保存を試すと、違いが見えるよ。", "RAMを増やす→保存を試す→保存庫を増やす→保存→再起動→ひらく。"]
        }
    }
    public var isComplete: Bool {
        let photo = documents.first { $0.id == "photo" }
        switch stage {
        case 1: return evidence.contains("versionsObserved") && photo?.workVersion == 2 && photo?.savedVersion == 2
        case 2: return photo?.savedVersion == 2 && documents.first { $0.id == "drawing" }?.workVersion != nil && usedRAM == 7
        case 3: return evidence.contains("rebooted") && photo?.workVersion == 3 && photo?.savedVersion == 3
        case 4: return evidence.contains("storageDoesNotHelp") && usedRAM == 6
        default: return evidence.contains("ramDoesNotHelp") && evidence.contains("photoSavedAtBoot") && photo?.workVersion == 1 && photo?.savedVersion == 1
        }
    }
    public var guide: String {
        if isComplete { return stage == 2 ? "写真を残して、次の仕事も始められたね。保存と閉じるは違う働きだったよ。" : "作業する場所と、残しておく場所。それぞれの変化を確かめられたね。" }
        if !message.isEmpty { return message }
        return "ここは、いま使うデータの作業場。\(stage == 1 ? "保存庫の写真を一枚ひらいてみよう。" : goal)"
    }
    public init(stage: Int) {
        self.stage = min(5, max(1, stage)); ramCapacity = 6; storageCapacity = 12
        documents = [.init(id: "photo", title: "写真", size: 3, savedVersion: 1, icon: "photo")]
        switch self.stage {
        case 2:
            ramCapacity = 8
            documents = [.init(id: "photo", title: "写真", size: 3, workVersion: 2, savedVersion: 2, icon: "photo"), .init(id: "music", title: "音楽", size: 2, workVersion: 1, savedVersion: 1, icon: "music.note"), .init(id: "video", title: "動画", size: 3, workVersion: 1, savedVersion: 1, icon: "play.rectangle.fill"), .init(id: "drawing", title: "お絵描き", size: 2, icon: "pencil.tip")]
        case 3:
            documents[0].workVersion = 3; documents[0].savedVersion = 2
            documents.append(.init(id: "music", title: "音楽", size: 2, savedVersion: 1, icon: "music.note"))
        case 4:
            ramCapacity = 4; documents[0].workVersion = 1
            documents.append(.init(id: "new", title: "新しい仕事", size: 3, icon: "doc.badge.plus")); selectedID = "new"
        case 5:
            ramCapacity = 8; storageCapacity = 6; documents[0].workVersion = 1; documents[0].savedVersion = nil
            documents += [.init(id: "music", title: "音楽", size: 2, savedVersion: 1, icon: "music.note"), .init(id: "video", title: "動画", size: 4, savedVersion: 1, icon: "play.rectangle.fill")]
        default: break
        }
    }
    private mutating func note(_ value: String) { message = value; observations.append(value); if observations.count > 30 { observations.removeFirst() } }
    public mutating func send(_ action: Action) {
        if case .select(let id) = action { guard documents.contains(where: { $0.id == id }) else { return }; selectedID = id; pendingConfirmation = nil; message = "\(selected!.title)を選んだね。次は、どこへ動かす？"; return }
        if case .power(let confirmed) = action {
            guard stage == 3 || stage == 5 else { return }
            if powered {
                if !confirmed {
                    let dirty = documents.filter(\.isDirty).map(\.title).joined(separator: "、")
                    pendingConfirmation = "電源を切ると作業中のデータは消えます。" + (dirty.isEmpty ? "保存したデータは残ります。" : "\(dirty)の未保存の変更も失われます。")
                    return
                }
                documents.indices.forEach { documents[$0].workVersion = nil }; powered = false; pendingConfirmation = nil; evidence.insert("poweredOff"); note("作業場が空になったね。保存庫には、残っているよ。")
            } else {
                powered = true; evidence.insert("rebooted")
                if documents.first(where: { $0.id == "photo" })?.savedVersion != nil { evidence.insert("photoSavedAtBoot") }
                note("電源が入ったよ。保存庫から、もう一度ひらいてみよう。")
            }
            return
        }
        guard powered else { message = "まず教材の電源を入れてみよう。"; return }
        guard let i = documents.firstIndex(where: { $0.id == selectedID }) else { return }
        switch action {
        case .open:
            guard documents[i].workVersion == nil else { message = "もう作業場でひらいているよ。"; return }
            guard usedRAM + documents[i].size <= ramCapacity else {
                if stage == 4 && storageCapacity > 12 { evidence.insert("storageDoesNotHelp") }
                note("RAMの空きがあと\(usedRAM + documents[i].size - ramCapacity)枠必要だね。保存庫を広げても、この空きは変わらないよ。"); return
            }
            documents[i].workVersion = documents[i].savedVersion ?? 1
            note("\(documents[i].title)がひらいたよ。RAMは\(usedRAM)/\(ramCapacity)枠になったね。")
        case .edit:
            guard stage == 1, let v = documents[i].workVersion else { message = "まず写真を作業場へひらこう。"; return }
            documents[i].workVersion = min(2, v + 1); note("作業版がv2になったね。保存庫の版と見比べて、観察を残そう。")
        case .save:
            guard let v = documents[i].workVersion else { message = "保存する作業版がまだないよ。"; return }
            let extra = documents[i].savedVersion == nil ? documents[i].size : 0
            guard usedStorage + extra <= storageCapacity else {
                if stage == 5 && ramCapacity > 8 { evidence.insert("ramDoesNotHelp") }
                note("保存庫にあと\(usedStorage + extra - storageCapacity)枠必要。RAMの広さとは別なんだね。"); return
            }
            documents[i].savedVersion = v; note("保存できたね。RAMは\(usedRAM)/\(ramCapacity)のまま。作業場の空きは変わったかな？")
        case .close(let confirmed):
            guard stage == 2, documents[i].workVersion != nil else { message = "この課題では作業中のデータを残して進めよう。"; return }
            if documents[i].isDirty && !confirmed { pendingConfirmation = "\(documents[i].title)の未保存の変更を捨てて閉じますか？"; return }
            documents[i].workVersion = nil; pendingConfirmation = nil; note("作業場が\(ramCapacity-usedRAM)枠空いたね。保存庫の版はそのままだよ。")
        case .expandRAM:
            guard stage == 4 || stage == 5 else { return }; ramCapacity = stage == 4 ? 6 : 12; note("RAMを\(ramCapacity)枠にしたよ。保存できる量も変わったかな？")
        case .expandStorage:
            guard stage == 4 || stage == 5 else { return }; storageCapacity = stage == 4 ? 18 : 10; note("保存庫を\(storageCapacity)枠にしたよ。同じ操作を試してみよう。")
        case .observe:
            if documents[i].workVersion == 2 && documents[i].savedVersion == 1 { evidence.insert("versionsObserved") }
            note("観察：作業\(documents[i].workVersion.map { "v\($0)" } ?? "なし")／保存\(documents[i].savedVersion.map { "v\($0)" } ?? "なし")、RAM \(usedRAM)/\(ramCapacity)、保存庫 \(usedStorage)/\(storageCapacity)。")
        default: break
        }
    }
}
