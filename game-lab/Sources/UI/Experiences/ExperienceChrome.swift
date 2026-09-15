import SwiftUI
import AppKit

enum ExperienceStyle {
    static let ink = Color(red: 0.10, green: 0.15, blue: 0.20)
    static let muted = Color(red: 0.46, green: 0.51, blue: 0.55)
    static let cyan = Color(red: 0.12, green: 0.83, blue: 0.90)
    static let dark = Color(red: 0.13, green: 0.17, blue: 0.22)
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.88)
    static let purple = Color(red: 0.72, green: 0.56, blue: 0.93)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.32)
    static let coral = Color(red: 1.0, green: 0.49, blue: 0.43)
}

struct ExperienceButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 19, weight: .semibold, design: .rounded))
            .padding(.horizontal, 19).padding(.vertical, 13)
            .foregroundStyle(ExperienceStyle.ink)
            .background(WorkshopChamfer(corner: 10).fill(LinearGradient(colors: primary ? [Color(red: 0.64, green: 0.97, blue: 1), ExperienceStyle.cyan] : [.white, Color(red: 0.80, green: 0.84, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(WorkshopChamfer(corner: 10).strokeBorder(ExperienceStyle.ink.opacity(0.9), lineWidth: 2))
            .overlay(WorkshopChamfer(corner: 8, insetAmount: 4).strokeBorder(.white.opacity(0.7), lineWidth: 1))
            .compositingGroup()
            .shadow(color: .black.opacity(0.36), radius: 0, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(enabled ? 1 : 0.38)
    }
}

struct ExperienceDevice<Content: View>: View {
    let title: String
    var subtitle = ""
    var active = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 12) {
            if !title.isEmpty { Text(title).font(.system(size: 22, weight: .bold, design: .rounded)).lineLimit(2).multilineTextAlignment(.center) }
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 14, weight: .medium)).foregroundStyle(ExperienceStyle.muted) }
            content()
        }.padding(22).foregroundStyle(ExperienceStyle.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WorkshopChamfer(corner: 17).fill(LinearGradient(colors: [.white, ExperienceStyle.paper, Color(red: 0.76, green: 0.77, blue: 0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(WorkshopChamfer(corner: 17).strokeBorder(active ? ExperienceStyle.cyan : Color(red: 0.35, green: 0.40, blue: 0.44), lineWidth: active ? 4 : 3))
            .overlay(WorkshopChamfer(corner: 12, insetAmount: 6).strokeBorder(.white.opacity(0.7), lineWidth: 2))
            .overlay { GeometryReader { g in
                ForEach(0..<4, id: \.self) { i in
                    ZStack {
                        Circle().fill(LinearGradient(colors: [.gray, ExperienceStyle.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Rectangle().fill(.white.opacity(0.35)).frame(width: 7, height: 1).rotationEffect(.degrees(30))
                    }.frame(width: 9, height: 9).position(x: i % 2 == 0 ? 14 : g.size.width - 14, y: i < 2 ? 14 : g.size.height - 14)
                }
            }.allowsHitTesting(false) }
            .compositingGroup()
            .shadow(color: .black.opacity(0.32), radius: 0, x: 3, y: 8)
            .shadow(color: active ? ExperienceStyle.cyan.opacity(0.25) : .clear, radius: 9)
    }
}

struct ExperienceChip: View {
    let label: String
    var symbol = "square"
    var color: Color = .cyan
    var selected = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26, weight: .semibold))
            Text(label).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(2)
        }.padding(.horizontal, 16).padding(.vertical, 15)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(ExperienceStyle.ink)
            .background(WorkshopChamfer(corner: 9).fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(WorkshopChamfer(corner: 9).strokeBorder(selected ? .white : ExperienceStyle.dark, lineWidth: selected ? 3 : 2))
            .overlay(WorkshopChamfer(corner: 6, insetAmount: 5).strokeBorder(.white.opacity(0.45), lineWidth: 1))
            .compositingGroup()
            .shadow(color: .black.opacity(0.4), radius: 0, x: 2, y: 4)
            .shadow(color: selected ? color.opacity(0.5) : .clear, radius: 9)
    }
}

struct ExperienceSignal: View {
    var active: Bool
    var vertical = false
    var body: some View {
        ZStack {
            Capsule().fill(ExperienceStyle.ink).frame(width: vertical ? 14 : nil, height: vertical ? nil : 14)
            Capsule().fill(active ? ExperienceStyle.cyan : Color.gray.opacity(0.6)).frame(width: vertical ? 7 : nil, height: vertical ? nil : 7)
                .shadow(color: active ? .cyan.opacity(0.7) : .clear, radius: 7)
            Image(systemName: vertical ? "chevron.down" : "chevron.right").font(.system(size: 15, weight: .black)).foregroundStyle(active ? .white : .gray)
        }.frame(minWidth: vertical ? 20 : 20, minHeight: vertical ? 20 : 20)
            .accessibilityLabel(active ? "信号が届いています" : "信号は停止中")
    }
}

struct ExperienceMat: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: [Color(red: 0.23, green: 0.28, blue: 0.33), ExperienceStyle.dark]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            for x in stride(from: 22.0, to: size.width, by: 52) {
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.black.opacity(0.13)), lineWidth: 1)
                for y in stride(from: 22.0, to: size.height, by: 52) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(.white.opacity(0.13)))
                }
            }
        }.clipShape(WorkshopChamfer(corner: 24))
            .overlay(WorkshopChamfer(corner: 24).strokeBorder(Color(red: 0.51, green: 0.55, blue: 0.56), lineWidth: 5))
            .overlay(WorkshopChamfer(corner: 18, insetAmount: 10).strokeBorder(.white.opacity(0.12), lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 0, x: 3, y: 8)
    }
}

struct ExperiencePlaybackControls: View {
    var canStep: Bool
    var step: () -> Void
    @State private var running = false
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 14) {
            Button { running.toggle() } label: { Label(running ? "一時停止" : "再生", systemImage: running ? "pause.fill" : "play.fill") }
                .disabled(!canStep).keyboardShortcut(.space, modifiers: []).buttonStyle(ExperienceButtonStyle(primary: true))
            Button { running = false; step() } label: { Label("1手進む", systemImage: "forward.end.fill") }
                .disabled(!canStep).keyboardShortcut(.rightArrow, modifiers: []).buttonStyle(ExperienceButtonStyle())
        }.onReceive(timer) { _ in if running && canStep { step() } }
            .onChange(of: canStep) { if !$0 { running = false } }
            .onChange(of: scenePhase) { if $0 != .active { running = false } }
            .onDisappear { running = false }
    }
}
