import SwiftUI

/// Opt in at the integrated room's sheet boundary; standalone Monitor keeps its native appearance.
enum MonitorAppearance {
    case system, room

    static let roomBackground = Color(red: 0.045, green: 0.085, blue: 0.11)
    static let roomAccent = Color(red: 0.14, green: 0.48, blue: 0.53)
    static let roomBorder = Color.white.opacity(0.2)
    static let roomCard = Color(red: 0.075, green: 0.13, blue: 0.17)
}

private struct MonitorAppearanceKey: EnvironmentKey {
    static let defaultValue: MonitorAppearance = .system
}

extension EnvironmentValues {
    var monitorAppearance: MonitorAppearance {
        get { self[MonitorAppearanceKey.self] }
        set { self[MonitorAppearanceKey.self] = newValue }
    }
}

extension View {
    func monitorCircuitExclusion() -> some View {
        anchorPreference(key: MonitorCircuitExclusions.self, value: .bounds) { [$0] }
    }
    func monitorSurface() -> some View { modifier(MonitorSurface()) }
    func monitorCard(cornerRadius: CGFloat, nativeBorder: Bool = false) -> some View {
        modifier(MonitorCard(cornerRadius: cornerRadius, nativeBorder: nativeBorder))
    }
}

private struct MonitorCircuitExclusions: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

private struct MonitorSurface: ViewModifier {
    @Environment(\.monitorAppearance) private var appearance

    @ViewBuilder func body(content: Content) -> some View {
        if appearance == .room {
            content
                .foregroundStyle(.white)
                .tint(MonitorAppearance.roomAccent)
                .accentColor(MonitorAppearance.roomAccent)
                .buttonStyle(RoomMonitorButtonStyle())
                .groupBoxStyle(RoomMonitorGroupBoxStyle())
                .environment(\.colorScheme, .dark)
                .preferredColorScheme(.dark)
                .backgroundPreferenceValue(MonitorCircuitExclusions.self) { anchors in
                    GeometryReader { geometry in
                        ZStack {
                            MonitorAppearance.roomBackground.opacity(0.97)
                            MonitorCircuitFlow(exclusions: anchors.map { geometry[$0].insetBy(dx: -5, dy: -4) })
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MonitorAppearance.roomBorder).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        } else {
            content
        }
    }
}

private struct MonitorCard: ViewModifier {
    @Environment(\.monitorAppearance) private var appearance
    let cornerRadius: CGFloat
    let nativeBorder: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: appearance == .room ? max(10, cornerRadius) : cornerRadius)
        content
            .background(appearance == .room ? MonitorAppearance.roomCard : Color(nsColor: .controlBackgroundColor), in: shape)
            .overlay(shape.strokeBorder(appearance == .room ? Color.white.opacity(0.12) : Color.primary.opacity(nativeBorder ? 0.06 : 0))
                .allowsHitTesting(false))
    }
}

private struct RoomMonitorGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label.font(.headline)
            configuration.content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .monitorCard(cornerRadius: 10)
    }
}

private struct RoomMonitorButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(configuration.role == .destructive ? Color.red.opacity(0.65) : MonitorAppearance.roomAccent,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(configuration.isPressed ? 0.35 : 0.12)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
