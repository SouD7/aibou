import SwiftUI
import AppKit

struct WorkshopChamfer: InsettableShape {
    var corner: CGFloat = 12
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cut = min(corner, min(r.width, r.height) / 3)
        return Path { p in
            p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
            p.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + cut, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
            p.closeSubpath()
        }
    }
    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self; copy.insetAmount += amount; return copy
    }
}

struct WorkshopPlate: ViewModifier {
    var dark = false
    func body(content: Content) -> some View {
        content
            .background(WorkshopChamfer().fill(LinearGradient(
                colors: dark ? [Color(red: 0.25, green: 0.28, blue: 0.32), Color(red: 0.13, green: 0.16, blue: 0.20)] : [Color(red: 0.98, green: 0.97, blue: 0.94), Color(red: 0.88, green: 0.88, blue: 0.87)],
                startPoint: .topLeading, endPoint: .bottomTrailing)).shadow(color: .black.opacity(0.16), radius: 1, y: 3))
            .overlay(WorkshopChamfer().strokeBorder(Color(red: 0.22, green: 0.25, blue: 0.29), lineWidth: 1.5))
            .overlay(WorkshopChamfer(corner: 10, insetAmount: 3).strokeBorder(Color.white.opacity(dark ? 0.14 : 0.8), lineWidth: 1))
    }
}

enum WorkshopArtwork {
    static let workbench: NSImage? = Bundle.main.url(forResource: "workbench-v1", withExtension: "png", subdirectory: "WorkshopArt").flatMap(NSImage.init(contentsOf:))
}

struct WorkshopBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            if let art = WorkshopArtwork.workbench {
                Image(nsImage: art).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                Color(red: 0.89, green: 0.88, blue: 0.86)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
