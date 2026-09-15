import SwiftUI

/// The exhibition destination control.
struct DestinationNavigation: View {
    enum Location { case exhibition }
    var current: Location
    var onExhibition: () -> Void
    var exhibitionIdentifier: String

    var body: some View {
        HStack(spacing: 22) {
            Button(action: onExhibition) { Label("学習", systemImage: "building.2") }
                .buttonStyle(DestinationTabStyle(selected: current == .exhibition))
                .accessibilityValue(current == .exhibition ? "現在の場所" : "")
                .accessibilityIdentifier(exhibitionIdentifier)
        }
    }
}

private struct DestinationTabStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .padding(.horizontal, 17).padding(.vertical, 11)
            .foregroundStyle(ExhibitionStyle.ink)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(selected ? Color(red: 0.12, green: 0.69, blue: 0.79).opacity(0.2) : .clear)
                .shadow(color: ExhibitionStyle.ink.opacity(selected ? 0.16 : 0), radius: 0, y: 3))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(ExhibitionStyle.ink.opacity(selected ? 0.8 : 0), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
