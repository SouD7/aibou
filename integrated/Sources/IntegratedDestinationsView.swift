import SwiftUI
import AIBOULearning

/// Keeping both destinations mounted preserves the room selection and learning state.
struct IntegratedDestinationsView: View {
    @ObservedObject var app: IntegratedStore

    var body: some View {
        ZStack {
            IntegratedWindow(app: app)
                .opacity(app.showingLearning ? 0 : 1)
                .allowsHitTesting(!app.showingLearning)
                .disabled(app.showingLearning)
                .accessibilityHidden(app.showingLearning)

            if app.hasOpenedLearning {
                AIBOULearningView(isActive: app.showingLearning, onReturnToLab: app.returnFromLearning)
                    .opacity(app.showingLearning ? 1 : 0)
                    .allowsHitTesting(app.showingLearning)
                    .disabled(!app.showingLearning)
                    .accessibilityHidden(!app.showingLearning)
            }
        }
    }
}
