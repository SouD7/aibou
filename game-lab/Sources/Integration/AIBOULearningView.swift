import SwiftUI

/// The host keeps this view mounted when switching back to the lab.
/// All gameplay, progress and avatar implementation stays inside this module.
@MainActor
public struct AIBOULearningView: View {
    @StateObject private var game = CircuitLabStore()
    @StateObject private var exhibition = ExhibitionStore()
    @Environment(\.scenePhase) private var scenePhase
    private let isActive: Bool
    private let onReturnToLab: () -> Void

    public init(isActive: Bool, onReturnToLab: @escaping () -> Void) {
        self.isActive = isActive
        self.onReturnToLab = onReturnToLab
    }

    public var body: some View {
        ExhibitionHomeView(gameStore: game, exhibition: exhibition, onReturnToLab: onReturnToLab)
            .environment(\.scenePhase, isActive ? scenePhase : .inactive)
    }
}
