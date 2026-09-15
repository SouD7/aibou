import SwiftUI

/// Decorative housing only. The public game actions remain the source of every state change.
struct MemoryCartridgeShell: View {
    var color: Color
    var units: Int = 1
    var selected = false
    var compressed = false

    var body: some View {
        Canvas { context, size in
            let outer = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            let rim = WorkshopChamfer(corner: 9).path(in: outer)
            context.fill(rim, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.40, green: 0.47, blue: 0.51), .white.opacity(0.85), ExperienceStyle.ink]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            context.stroke(rim, with: .color(selected ? ExperienceStyle.cyan : ExperienceStyle.ink), lineWidth: selected ? 3 : 2)
            let gasket = WorkshopChamfer(corner: 7).path(in: outer.insetBy(dx: 5, dy: 5))
            context.fill(gasket, with: .color(ExperienceStyle.ink))
            let faceRect = outer.insetBy(dx: 10, dy: 10)
            let face = WorkshopChamfer(corner: 5).path(in: faceRect)
            context.fill(face, with: .linearGradient(Gradient(colors: [color.opacity(0.70), color, color.opacity(0.76)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(face, with: .color(.white.opacity(0.5)), lineWidth: 1.3)

            if compressed {
                let foldCount = 7
                let step = faceRect.width / CGFloat(foldCount)
                for i in 0..<foldCount {
                    let x = faceRect.minX + CGFloat(i) * step
                    let fold = CGRect(x: x, y: faceRect.minY, width: step, height: faceRect.height)
                    context.fill(Path(fold), with: .linearGradient(Gradient(colors: [color.opacity(0.45), .white.opacity(0.65), color.opacity(0.55)]), startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + step, y: 0)))
                }
                for y in [faceRect.minY + 12, faceRect.maxY - 19] {
                    context.fill(Path(CGRect(x: 5, y: y, width: size.width - 10, height: 7)), with: .color(ExperienceStyle.ink.opacity(0.8)))
                    context.fill(Path(CGRect(x: 6, y: y, width: size.width - 12, height: 2)), with: .color(.white.opacity(0.7)))
                }
            } else if units > 1 {
                for i in 1..<units {
                    let x = faceRect.minX + faceRect.width * CGFloat(i) / CGFloat(units)
                    var seam = Path(); seam.move(to: CGPoint(x: x, y: faceRect.minY)); seam.addLine(to: CGPoint(x: x, y: faceRect.maxY))
                    context.stroke(seam, with: .color(ExperienceStyle.ink.opacity(0.21)), lineWidth: 2)
                    var edge = Path(); edge.move(to: CGPoint(x: x + 2, y: faceRect.minY)); edge.addLine(to: CGPoint(x: x + 2, y: faceRect.maxY))
                    context.stroke(edge, with: .color(.white.opacity(0.29)), lineWidth: 1)
                }
            }
            for x in [CGFloat(2), size.width - 14] {
                for y in [size.height * 0.24, size.height * 0.65] {
                    let latch = CGRect(x: x, y: y, width: 12, height: 20)
                    context.fill(Path(roundedRect: latch, cornerRadius: 2), with: .linearGradient(Gradient(colors: [.white, Color.gray, ExperienceStyle.ink]), startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + 12, y: y)))
                    context.stroke(Path(roundedRect: latch, cornerRadius: 2), with: .color(ExperienceStyle.ink), lineWidth: 1)
                    context.fill(Path(ellipseIn: CGRect(x: x + 4, y: y + 8, width: 4, height: 4)), with: .color(ExperienceStyle.ink))
                }
            }
            let pinCount = max(3, min(10, units * 3))
            let pinWidth = min(7, (size.width - 34) / CGFloat(pinCount * 2))
            for i in 0..<pinCount {
                let x = size.width / 2 + (CGFloat(i) - CGFloat(pinCount - 1) / 2) * (pinWidth + 5)
                context.fill(Path(CGRect(x: x - pinWidth / 2, y: size.height - 8, width: pinWidth, height: 5)), with: .color(ExperienceStyle.amber.opacity(0.85)))
            }
            context.fill(Path(roundedRect: CGRect(x: 18, y: 14, width: max(0, size.width - 36), height: 3), cornerRadius: 1.5), with: .color(.white.opacity(0.58)))
        }.allowsHitTesting(false)
    }
}

struct MemoryParcel: View {
    let label: String
    var symbol = "doc.fill"
    var color: Color = ExperienceStyle.cyan
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold))
            Text(label).font(.system(size: 15, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
        }.foregroundStyle(ExperienceStyle.ink).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MemoryCartridgeShell(color: color))
    }
}

struct MemoryCompressionMechanism: View {
    let compressed: Bool
    var body: some View {
        ZStack {
            Canvas { context, size in
                let bay = CGRect(x: 17, y: 3, width: size.width - 34, height: size.height - 6)
                context.fill(Path(roundedRect: bay, cornerRadius: 7), with: .color(ExperienceStyle.dark))
                context.stroke(Path(roundedRect: bay, cornerRadius: 7), with: .color(ExperienceStyle.ink), lineWidth: 3)
                for x in [CGFloat(23), size.width - 29] {
                    let rail = CGRect(x: x, y: 8, width: 6, height: size.height - 16)
                    context.fill(Path(rail), with: .linearGradient(Gradient(colors: [.gray, .white, .gray]), startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + 6, y: 0)))
                }
                for x in [CGFloat(1), size.width - 14] {
                    let port = CGRect(x: x, y: size.height - 46, width: 13, height: 29)
                    context.fill(Path(roundedRect: port, cornerRadius: 3), with: .color(ExperienceStyle.ink))
                    context.fill(Path(CGRect(x: x + 4, y: port.minY + 5, width: 5, height: 19)), with: .color(ExperienceStyle.cyan))
                }
            }
            Rectangle().fill(LinearGradient(colors: [.gray, .white, .gray], startPoint: .leading, endPoint: .trailing))
                .frame(width: 24, height: compressed ? 53 : 20).frame(maxHeight: .infinity, alignment: .top).padding(.top, 7)
            MemoryCartridgeShell(color: ExperienceStyle.purple, compressed: true)
                .frame(width: 75, height: compressed ? 33 : 55).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 20)
            Text("B").font(.system(size: 18, weight: .black)).foregroundStyle(ExperienceStyle.ink)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, compressed ? 25 : 37)
            MemoryPressJaw().frame(width: 108, height: 15).offset(y: compressed ? 5 : -28)
            MemoryPressJaw().frame(width: 108, height: 15).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 8)
        }.frame(width: 156, height: 105)
        .accessibilityLabel(compressed ? "Bを圧縮した蛇腹、3枠から1枠" : "圧縮前のB、3枠")
    }
}

private struct MemoryPressJaw: View {
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(roundedRect: bounds, cornerRadius: 3), with: .linearGradient(Gradient(colors: [.white, .gray]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.clip(to: Path(bounds.insetBy(dx: 3, dy: 3)))
            context.fill(Path(bounds), with: .color(ExperienceStyle.amber))
            for i in -1..<9 {
                var stripe = Path(); let x = CGFloat(i) * 18
                stripe.move(to: CGPoint(x: x, y: 0)); stripe.addLine(to: CGPoint(x: x + 9, y: 0)); stripe.addLine(to: CGPoint(x: x - 2, y: size.height)); stripe.addLine(to: CGPoint(x: x - 11, y: size.height)); stripe.closeSubpath()
                context.fill(stripe, with: .color(ExperienceStyle.ink))
            }
        }.allowsHitTesting(false)
    }
}

struct MemoryLoadingPort: View {
    let label: String
    let preparing: Bool
    let hasParcel: Bool
    var color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(ExperienceStyle.dark).overlay(RoundedRectangle(cornerRadius: 7).stroke(ExperienceStyle.ink, lineWidth: 3))
            if hasParcel { MemoryParcel(label: label, color: color).frame(width: 84, height: 80) }
            HStack {
                VStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Capsule().fill(preparing ? ExperienceStyle.amber : ExperienceStyle.cyan).frame(width: 5, height: 12) } }.padding(7).background(ExperienceStyle.ink)
                Spacer()
                VStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Capsule().fill(preparing ? ExperienceStyle.amber : ExperienceStyle.cyan).frame(width: 5, height: 12) } }.padding(7).background(ExperienceStyle.ink)
            }
            VStack { MemoryPressJaw().frame(height: 12); Spacer(); MemoryPressJaw().frame(height: 12) }
        }.frame(height: 103)
    }
}

struct MemoryConveyor: View {
    let phase: String
    let parcel: String
    let progress: Double
    let color: Color
    var body: some View {
        ZStack(alignment: .leading) {
            Canvas { context, size in
                let belt = CGRect(x: 2, y: 36, width: size.width - 4, height: 44)
                context.fill(Path(roundedRect: belt, cornerRadius: 19), with: .color(ExperienceStyle.ink))
                context.stroke(Path(roundedRect: belt, cornerRadius: 19), with: .color(.white.opacity(0.58)), lineWidth: 4)
                for i in 0..<8 {
                    let x = CGFloat(i) * (size.width - 22) / 7 + 11
                    context.fill(Path(ellipseIn: CGRect(x: x - 6, y: 51, width: 12, height: 12)), with: .color(.gray))
                    context.fill(Path(ellipseIn: CGRect(x: x - 2, y: 55, width: 4, height: 4)), with: .color(ExperienceStyle.ink))
                }
                for x in [CGFloat(13), size.width - 23] { context.fill(Path(CGRect(x: x, y: 77, width: 10, height: 13)), with: .color(.gray)) }
            }
            if phase == "transfer" {
                MemoryParcel(label: parcel, color: color).frame(width: 66, height: 65)
                    .offset(x: 5 + CGFloat(progress) * 116, y: -12)
            }
        }.frame(height: 95)
    }
}
