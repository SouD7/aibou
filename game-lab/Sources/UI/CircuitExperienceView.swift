import SwiftUI

/// The workshop and free experiment share a window, with independent working boards.
struct CircuitLabView: View {
    @StateObject private var store: CircuitLabStore
    private var embeddedInExhibition: Bool

    init() { _store = StateObject(wrappedValue: CircuitLabStore()); embeddedInExhibition = false }
    init(store: CircuitLabStore, embeddedInExhibition: Bool = false) {
        _store = StateObject(wrappedValue: store); self.embeddedInExhibition = embeddedInExhibition
    }

    var body: some View {
        Group {
            if store.showsSandbox {
                VStack(spacing: 0) {
                    HStack {
                        Button { store.showsSandbox = false } label: { Label("相棒とのアトリエへ", systemImage: "arrow.left") }
                            .accessibilityIdentifier("workshop.return")
                        Spacer()
                        Text("自由実験 · AND / OR / XOR").font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal, 24).padding(.vertical, 9)
                    CircuitSandboxView(store: store)
                }
            } else {
                WorkshopView(store: store.workshop, minimumHeight: embeddedInExhibition ? 650 : 750) { store.showsSandbox = true }
            }
        }.preferredColorScheme(.light)
    }
}
