import SwiftUI
import AppKit
#if canImport(CircuitCore)
import CircuitCore
#endif

enum ExhibitionStyle {
    static let ink = Color(red: 0.09, green: 0.13, blue: 0.19)
    static let paper = Color(red: 0.975, green: 0.954, blue: 0.915)
    static let muted = Color(red: 0.40, green: 0.43, blue: 0.46)
    static func color(_ area: ExhibitionAreaID) -> Color {
        switch area {
        case .a: return Color(red: 0.27, green: 0.82, blue: 0.90)
        case .b: return Color(red: 0.99, green: 0.77, blue: 0.35)
        case .c: return Color(red: 0.71, green: 0.61, blue: 0.89)
        case .d: return Color(red: 0.30, green: 0.81, blue: 0.72)
        case .e: return Color(red: 0.99, green: 0.61, blue: 0.56)
        }
    }
}

/// Fit the entire illustrated room and its hit regions together. There is no
/// scroll container or independently cropped background in the exhibition.
struct ExhibitionStage<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 1600, geometry.size.height / 900)
            content().frame(width: 1600, height: 900)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: 1600 * scale, height: 900 * scale, alignment: .topLeading)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.clipped().background(ExhibitionStyle.paper)
    }
}

enum ExhibitionArtwork {
    private static let names = ["lobby", "area-a", "area-b", "area-c", "area-d", "area-e", "circuit-entry"]
    static let images: [String: NSImage] = Dictionary(uniqueKeysWithValues: names.compactMap { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "ExhibitionArt"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (name, image)
    })
}

struct ExhibitionRoomArt: View {
    let name: String
    var body: some View {
        Group {
            if let art = ExhibitionArtwork.images[name] {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    ExhibitionStyle.paper
                    VStack(spacing: 20) {
                        Image(systemName: "building.2.crop.circle").font(.system(size: 70, weight: .ultraLight))
                        Text("展示室の画像を読み込めませんでした").font(.system(size: 24))
                    }.foregroundStyle(ExhibitionStyle.muted)
                }
            }
        }.frame(width: 1600, height: 900).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ExhibitionButtonStyle: ButtonStyle {
    var accent: Color = ExhibitionStyle.paper
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 14 : 22, weight: .semibold, design: .rounded))
            .padding(.horizontal, compact ? 17 : 25).padding(.vertical, compact ? 11 : 16)
            .foregroundStyle(ExhibitionStyle.ink)
            .background(RoundedRectangle(cornerRadius: compact ? 9 : 13).fill(accent)
                .shadow(color: ExhibitionStyle.ink.opacity(0.16), radius: 0, y: configuration.isPressed ? 0 : 3))
            .overlay(RoundedRectangle(cornerRadius: compact ? 9 : 13).stroke(ExhibitionStyle.ink.opacity(0.8), lineWidth: 1.5))
            .offset(y: configuration.isPressed ? 2 : 0)
            .opacity(enabled ? 1 : 0.45)
    }
}

struct ExhibitPlacement {
    var bounds: CGRect
    var plaque: CGRect
    init(_ bounds: [Double], _ plaque: [Double]) {
        self.bounds = CGRect(x: bounds[0] * 1600, y: bounds[1] * 900, width: bounds[2] * 1600, height: bounds[3] * 900)
        self.plaque = CGRect(x: plaque[0] * 1600, y: plaque[1] * 900, width: plaque[2] * 1600, height: plaque[3] * 900)
        self.bounds = self.bounds.union(self.plaque)
    }
}

enum ExhibitionLayout {
    static let doors: [ExhibitionAreaID: ExhibitPlacement] = [
        .a: ExhibitPlacement([0.205,0.085,0.145,0.54], [0.244,0.125,0.098,0.069]),
        .b: ExhibitPlacement([0.38,0.158,0.126,0.45], [0.414,0.177,0.085,0.067]),
        .c: ExhibitPlacement([0.526,0.157,0.122,0.45], [0.566,0.177,0.073,0.067]),
        .d: ExhibitPlacement([0.671,0.121,0.126,0.50], [0.708,0.137,0.082,0.073]),
        .e: ExhibitPlacement([0.824,0.076,0.154,0.60], [0.861,0.098,0.110,0.070])
    ]
    static let doorSubtitles: [ExhibitionAreaID: CGPoint] = [
        .a: CGPoint(x: 0.278 * 1600, y: 0.225 * 900), .b: CGPoint(x: 0.443 * 1600, y: 0.264 * 900),
        .c: CGPoint(x: 0.585 * 1600, y: 0.264 * 900), .d: CGPoint(x: 0.735 * 1600, y: 0.252 * 900),
        .e: CGPoint(x: 0.903 * 1600, y: 0.216 * 900)
    ]
    static func doorAngle(_ id: ExhibitionAreaID) -> Double {
        switch id { case .a: return 12; case .d, .e: return -10; default: return 0 }
    }
    /// Ordered to match ExhibitionCatalog.games(in:). Coordinates refer to
    /// each complete 16:9 production background, independent of window size.
    static func exhibits(_ area: ExhibitionAreaID) -> [ExhibitPlacement] {
        switch area {
        case .a: return [
            ExhibitPlacement([0.102,0.085,0.24,0.49], [0.122,0.094,0.198,0.071]),
            ExhibitPlacement([0.117,0.628,0.53,0.30], [0.126,0.839,0.268,0.083]),
            ExhibitPlacement([0.539,0.085,0.198,0.278], [0.554,0.099,0.156,0.069]),
            ExhibitPlacement([0.793,0.148,0.185,0.60], [0.806,0.163,0.161,0.074])
        ]
        case .b: return [
            ExhibitPlacement([0.306,0.205,0.376,0.340], [0.31,0.214,0.235,0.075]),
            ExhibitPlacement([0.019,0.085,0.175,0.682], [0.027,0.101,0.153,0.074]),
            ExhibitPlacement([0.48,0.594,0.477,0.364], [0.692,0.61,0.230,0.073]),
            ExhibitPlacement([0.71,0.114,0.226,0.423], [0.719,0.112,0.202,0.072])
        ]
        case .c: return [
            ExhibitPlacement([0.012,0.213,0.173,0.675], [0.022,0.230,0.154,0.083]),
            ExhibitPlacement([0.281,0.083,0.425,0.162], [0.231,0.094,0.153,0.070]),
            ExhibitPlacement([0.548,0.31,0.178,0.30], [0.541,0.310,0.174,0.079]),
            ExhibitPlacement([0.781,0.092,0.212,0.775], [0.795,0.120,0.163,0.08])
        ]
        case .d: return [
            ExhibitPlacement([0.074,0.086,0.271,0.436], [0.097,0.095,0.235,0.073]),
            ExhibitPlacement([0.379,0.133,0.357,0.218], [0.448,0.134,0.169,0.07]),
            ExhibitPlacement([0.046,0.58,0.58,0.40], [0.081,0.837,0.166,0.082]),
            ExhibitPlacement([0.837,0.119,0.16,0.715], [0.846,0.153,0.139,0.076])
        ]
        case .e: return [
            ExhibitPlacement([0.055,0.624,0.52,0.314], [0.061,0.631,0.16,0.083]),
            ExhibitPlacement([0.075,0.08,0.227,0.426], [0.108,0.098,0.175,0.07]),
            ExhibitPlacement([0.311,0.148,0.30,0.437], [0.381,0.155,0.193,0.077]),
            ExhibitPlacement([0.743,0.076,0.244,0.538], [0.759,0.086,0.224,0.08])
        ]
        }
    }
}

struct ExhibitionHotspot: View {
    let placement: ExhibitPlacement
    let title: String
    let subtitle: String
    let accent: Color
    let id: String
    var active = false
    var door = false
    var reduceMotion = false
    var onHover: (Bool) -> Void = { _ in }
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    private var reduced: Bool { reduceMotion || systemReducedMotion }

    var body: some View {
        let bounds = placement.bounds
        let plaque = placement.plaque
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(hovered || active ? 0.08 : 0.001))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(hovered || active ? 0.95 : 0), lineWidth: 4))
                    .shadow(color: accent.opacity(hovered || active ? 0.5 : 0), radius: 16)
                    .frame(width: bounds.width, height: bounds.height)
                if door, let area = ExhibitionAreaID(rawValue: String(id.suffix(1))), let sub = ExhibitionLayout.doorSubtitles[area] {
                    Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.80)
                        .multilineTextAlignment(.center)
                        .frame(width: plaque.width, height: plaque.height)
                        .rotationEffect(.degrees(ExhibitionLayout.doorAngle(area)))
                        .offset(x: plaque.minX - bounds.minX, y: plaque.minY - bounds.minY)
                    Text(subtitle).font(.system(size: 18, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(width: 180, height: 35).rotationEffect(.degrees(ExhibitionLayout.doorAngle(area) * 0.7))
                        .position(x: sub.x - bounds.minX, y: sub.y - bounds.minY)
                } else {
                VStack(spacing: 5) {
                    Text(title).font(.system(size: door ? 23 : 24, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.80)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        if subtitle == "あそべる" || subtitle == "つづきから" { Circle().fill(Color(red: 0.0, green: 0.49, blue: 0.54)).frame(width: 7, height: 7) }
                        Text(subtitle).font(.system(size: 16, weight: .medium))
                        if hovered { Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)) }
                    }.foregroundStyle(ExhibitionStyle.ink.opacity(0.65))
                }
                .frame(width: plaque.width, height: plaque.height)
                .background(RoundedRectangle(cornerRadius: 9).fill(door ? accent : ExhibitionStyle.paper)
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 3))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ExhibitionStyle.ink.opacity(0.9), lineWidth: 2))
                .offset(x: plaque.minX - bounds.minX, y: plaque.minY - bounds.minY - (hovered && !reduced ? 3 : 0))
                }
            }.frame(width: bounds.width, height: bounds.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(ExhibitionStyle.ink)
        .accessibilityLabel("\(title)、\(subtitle)")
        .accessibilityIdentifier(id)
        .help("\(title)を開く")
        .onHover { inside in
            withAnimation(reduced ? nil : .easeOut(duration: 0.18)) { hovered = inside }
            onHover(inside)
        }
        .position(x: bounds.midX, y: bounds.midY)
    }
}
