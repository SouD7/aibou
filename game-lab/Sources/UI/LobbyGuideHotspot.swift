import AppKit
import SwiftUI

/// The clickable region follows the keyed character and stops at the desk.
/// Transparent image margins remain available to the room's door controls.
struct LobbyGuideHotspot: View {
    var action: () -> Void
    var onHover: (Bool) -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                LobbyGuideHitShape().fill(Color.cyan.opacity(hovered ? 0.07 : 0))
            }.frame(width: 374, height: 448.8).contentShape(LobbyGuideHitShape())
        }.buttonStyle(.plain).contentShape(LobbyGuideHitShape())
            .onHover { hovered = $0; onHover($0) }
            .overlay(alignment: .top) {
                Label("aibou に教わる", systemImage: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(ExhibitionStyle.paper, in: Capsule())
                    .overlay(Capsule().stroke(ExhibitionStyle.color(.a), lineWidth: 2))
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                    .offset(y: -42).opacity(hovered ? 1 : 0).allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("aibouに教わる。20のハードウェアの授業")
            .accessibilityHint("授業ノートを開きます")
            .accessibilityIdentifier("ex.lobby.lessons")
            .help("aibouに教わる · 20の小さな授業")
            .position(x: 285, y: 450)
    }
}

struct LobbyGuideHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        Self.mask.applying(CGAffineTransform(scaleX: rect.width / 374, y: rect.height / 448.8))
    }
    private static let mask: Path = {
        guard let url = Bundle.main.url(forResource: "guide-notebook", withExtension: "png", subdirectory: "ExhibitionArt"),
              let image = NSImage(contentsOf: url), let keyed = ImageProcessing.removeGreenScreen(from: image),
              let cg = keyed.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return Path(ellipseIn: CGRect(x: 48, y: 25, width: 265, height: 385))
        }
        let width = cg.width, height = cg.height
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info),
              let data = context.data else { return Path() }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let sx = 374.0 / Double(width), sy = 448.8 / Double(height)
        let foreground = LobbyReceptionForeground().path(in: CGRect(x: 0, y: 0, width: 1600, height: 900))
        var result = Path()
        let strideSize = 4
        for y in stride(from: 0, to: height, by: strideSize) {
            var run: Int?
            for x in stride(from: 0, through: width + strideSize, by: strideSize) {
                let inside = x < width && pixels[(y * width + x) * 4 + 3] > 128
                    && !foreground.contains(CGPoint(x: 98 + Double(x) * sx, y: 225.6 + Double(y) * sy))
                if inside && run == nil { run = x }
                if !inside, let start = run {
                    result.addRect(CGRect(x: Double(start) * sx, y: Double(y) * sy,
                                          width: Double(x - start) * sx, height: Double(strideSize) * sy))
                    run = nil
                }
            }
        }
        return result
    }()
}
