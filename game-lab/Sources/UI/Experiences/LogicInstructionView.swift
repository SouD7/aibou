import SwiftUI

struct LogicInstructionView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(LogicInstructionModel(stage: 1))
    var body: some View {
        ExperienceScreen(store: store, onExit: onExit) { model, send in
            LogicInstructionApparatus(model: model, send: send)
        }
    }
}

struct LogicInstructionApparatus: View {
    let model: LogicInstructionModel
    let send: (LogicInstructionModel.Action) -> Void
    @State private var selected: Int?
    @State private var running = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 15) {
            HStack(alignment: .center, spacing: 10) {
                LogicInstructionConveyor(title: "入力", subtitle: "残り \(model.input.count - model.inputIndex) 枚", active: model.inputIndex < model.input.count) {
                    HStack(spacing: 8) {
                        ForEach(model.input.indices, id: \.self) { i in
                            LogicNumberTile(value: String(model.input[i]), caption: i < model.inputIndex ? "読取済" : i == model.inputIndex ? "次の札" : "待機", active: i == model.inputIndex)
                                .overlay(alignment: .topTrailing) { if i < model.inputIndex { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan).background(Circle().fill(.black)).offset(x: 3,y: -4) } }
                                .opacity(i < model.inputIndex ? 0.75 : 1)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 100)
                }.frame(width: 240, height: 220)
                LogicSignalCable(active: model.inputIndex > 0).frame(width: 36,height: 30)
                VStack(spacing: 8) {
                    LogicInstructionRegister(title: "手元",value: model.accumulator.map(String.init) ?? "空",active: model.accumulator != nil,color: .cyan).frame(height: 125)
                    LogicInstructionRegister(title: "一時記憶 M0",value: model.memory[0].map(String.init) ?? "?",active: model.memory[0] != nil,color: .orange).frame(height: 102)
                }.frame(width: 205)
                LogicSignalCable(active: !model.output.isEmpty).frame(width: 36,height: 30)
                LogicInstructionConveyor(title: "出力", subtitle: "目標: \(model.expected.map(String.init).joined(separator: " · "))", active: !model.output.isEmpty) {
                    HStack(spacing: 6) {
                        if model.output.isEmpty { VStack(spacing: 8) { Image(systemName: "arrow.down").font(.system(size: 26));Text("まだ空").font(.system(size: 14)) }.foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity, minHeight: 100) }
                        ForEach(Array(model.output.enumerated()), id: \.offset) { _, value in LogicNumberTile(value: String(value), caption: "出た札", active: true) }
                    }.frame(maxWidth: .infinity, minHeight: 100)
                }.frame(width: 230, height: 220)
                VStack(alignment: .leading, spacing: 9) {
                    Label("実行ログ", systemImage: "list.bullet.rectangle").font(.headline)
                    ForEach(Array(model.trace.suffix(4).enumerated()), id: \.offset) { _, row in
                        Text("\(row.step)  \(row.instruction) → \(row.accumulator.map(String.init) ?? "空")")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                    }
                    if model.trace.isEmpty { Text("1命令ずつ動かすと\nここに記録が残るよ。").font(.system(size: 15)).foregroundStyle(.white.opacity(0.6)) }
                }.foregroundStyle(.white).padding(14).frame(width: 180, height: 220, alignment: .topLeading)
                    .background(LogicMachineHousing())
            }.frame(height: 240)
            HStack(spacing: 8) {
                Text("手順").font(.headline).foregroundStyle(.white).frame(width: 48)
                ForEach(0..<8, id: \.self) { index in
                    Group {
                        if model.program.indices.contains(index) {
                            Button { selected = index } label: {
                                VStack(spacing: 6) {
                                    Text("\(index + 1)\(model.pc == index && !model.halted ? "  次" : "")").font(.system(size: 13, weight: .bold))
                                    Image(systemName: model.program[index].symbol).font(.system(size: 23))
                                    Text(model.program[index].title).font(.system(size: 15, weight: .bold))
                                }.frame(width: 99, height: 66)
                            }.buttonStyle(LogicCompactButtonStyle(primary: selected == index || (model.pc == index && model.steps > 0 && !model.halted)))
                        } else {
                            Button { selected = nil } label: {
                                Image(systemName: "plus").font(.title2).foregroundStyle(.white.opacity(0.2)).frame(width: 99, height: 66)
                            }.buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5])))
                        }
                    }.accessibilityIdentifier("instruction.slot.\(index)")
                    .onDrop(of: ["public.text"], isTargeted: nil) { providers in
                        LogicDrop.text(providers) { raw in if let instruction = LogicInstructionModel.Instruction(rawValue: raw) { send(.append(instruction)) } }
                    }
                }
            }.padding(.horizontal, 19).padding(.vertical, 14)
                .background(LogicConveyorBed(active: running).padding(3))
                .background(LogicMachineHousing(active: running))
            HStack(spacing: 9) {
                Text("命令").font(.headline).foregroundStyle(.white).frame(width: 48)
                ForEach(model.available, id: \.self) { instruction in
                    Button { running = false; send(.append(instruction)) } label: { Label(instruction.title, systemImage: instruction.symbol).font(.system(size: 15, weight: .bold)) }
                        .buttonStyle(LogicCompactButtonStyle()).onDrag { NSItemProvider(object: instruction.rawValue as NSString) }
                        .accessibilityIdentifier("instruction.add.\(instruction.rawValue)")
                }
                Spacer()
                Button { if let selected, selected > 0 { send(.move(selected, selected - 1)); self.selected = selected - 1 }; running = false } label: { Image(systemName: "arrow.left") }
                    .disabled(selected == nil || selected == 0)
                Button { if let selected, selected + 1 < model.program.count { send(.move(selected, selected + 1)); self.selected = selected + 1 }; running = false } label: { Image(systemName: "arrow.right") }
                    .disabled(selected == nil || selected == model.program.count - 1)
                Button { if let selected { send(.remove(selected)); self.selected = nil }; running = false } label: { Image(systemName: "trash") }.disabled(selected == nil)
            }.buttonStyle(LogicCompactButtonStyle())
            HStack(spacing: 12) {
                Button { running = false; send(.step) } label: { Label("1命令進む", systemImage: "play.fill") }.buttonStyle(LogicCompactButtonStyle(primary: true)).keyboardShortcut(.space, modifiers: [])
                    .disabled(model.halted || model.fault != nil).accessibilityIdentifier("instruction.step")
                Button { running.toggle() } label: { Label(running ? "一時停止" : "再生", systemImage: running ? "pause.fill" : "play") }.buttonStyle(LogicCompactButtonStyle()).disabled(model.halted || model.fault != nil)
                Button { running = false; send(.rewind) } label: { Label("同じ入力で最初へ", systemImage: "backward.end") }.buttonStyle(LogicCompactButtonStyle())
                Spacer()
                if model.stage >= 4 {
                    ForEach(LogicInstructionModel.inputs(for: model.stage).indices, id: \.self) { index in
                        Button("入力\(index + 1)") { running = false; send(.selectCase(index)) }.buttonStyle(LogicCompactButtonStyle())
                    }
                }
                Button { running = false; send(.verify) } label: { Label("全入力で確かめる", systemImage: "checklist") }.buttonStyle(LogicCompactButtonStyle())
            }
        }.padding(20).frame(width: 1160, height: 550)
        .task(id: running) {
            guard running else { return }
            while !Task.isCancelled && running {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled && running else { break }
                send(.step)
                if model.halted || model.fault != nil { running = false }
            }
        }.onChange(of: model.stage) { _ in running = false; selected = nil }
        .onChange(of: model.halted) { if $0 { running = false } }
        .onChange(of: model.fault) { if $0 != nil { running = false } }
        .onChange(of: scenePhase) { if $0 != .active { running = false } }
        .onChange(of: model.program) { _ in running = false }
        .onDisappear { running = false }
    }
}

private struct LogicInstructionConveyor<Content: View>: View {
    let title: String
    let subtitle: String
    let active: Bool
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            LogicMachineHousing(active: active)
            LogicConveyorBed(vertical: true,active: active).padding(.horizontal,21).padding(.top,51).padding(.bottom,37)
            VStack(spacing: 0) {
                HStack(spacing: 7) { Text(title);Image(systemName: "arrow.down").font(.system(size: 14,weight: .heavy)) }
                    .font(.system(size: 20,weight: .bold)).foregroundStyle(ExperienceStyle.ink)
                    .frame(height: 32).frame(maxWidth: .infinity).background(WorkshopChamfer(corner: 6).fill(ExperienceStyle.paper)).padding(.horizontal,26).padding(.top,14)
                Spacer(minLength: 3)
                content.padding(.horizontal,30)
                Spacer(minLength: 3)
                Text(subtitle).font(.system(size: 14,weight: .semibold)).foregroundStyle(.white.opacity(0.8)).frame(height: 31)
            }
            HStack { Capsule().fill(active ? Color.cyan : .gray).frame(width: 5,height: 44);Spacer();Capsule().fill(active ? Color.cyan : .gray).frame(width: 5,height: 44) }.padding(.horizontal,15)
        }
    }
}

private struct LogicInstructionRegister: View {
    let title: String
    let value: String
    let active: Bool
    let color: Color
    var body: some View {
        ZStack {
            LogicMachineHousing(accent: color,active: active)
            VStack(spacing: 4) {
                Text(title).font(.system(size: 16,weight: .bold)).foregroundStyle(.white.opacity(0.85))
                Text(value).font(.system(size: 40,weight: .bold,design: .monospaced)).foregroundStyle(active ? color : Color.gray)
                    .frame(width: 103,height: 51).background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.4)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15),lineWidth: 2))
            }.padding(.vertical,11)
            HStack { Capsule().fill(active ? color : .gray).frame(width: 7,height: 44);Spacer();Capsule().fill(active ? color : .gray).frame(width: 7,height: 44) }.padding(.horizontal,23)
        }
    }
}

struct LogicNumberTile: View {
    let value: String
    var caption = ""
    var active = false
    var body: some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
            if !caption.isEmpty { Text(caption).font(.system(size: 12, weight: .medium)) }
        }.foregroundStyle(ExperienceStyle.ink).frame(minWidth: 40, minHeight: 70).padding(6)
            .background(RoundedRectangle(cornerRadius: 7).fill(active ? Color(red: 0.65,green: 0.95,blue: 0.98) : ExperienceStyle.paper))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(active ? ExperienceStyle.cyan : ExperienceStyle.muted, lineWidth: 2))
            .compositingGroup()
            .shadow(color: .black.opacity(0.25), radius: 1, y: 5)
    }
}

enum LogicDrop {
    static func text(_ providers: [NSItemProvider], receive: @escaping (String) -> Void) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: String.self) { string, _ in
            if let string { DispatchQueue.main.async { receive(string) } }
        }
        return true
    }
}
