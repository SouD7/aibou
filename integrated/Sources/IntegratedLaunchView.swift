import SwiftUI

/// Keep the room mounted under the opening so its first frame is ready before revealing it.
struct IntegratedLaunchView: View {
    @ObservedObject var app: IntegratedStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transitionRequested = false
    @State private var showRoom = false
    @State private var blackOpacity = 0.0

    var body: some View {
        ZStack {
            IntegratedWindow(app: app)
                .opacity(showRoom || !app.showingOpening ? 1 : 0)
                .allowsHitTesting(!app.showingOpening)
                .disabled(app.showingOpening)
                .accessibilityHidden(app.showingOpening)

            if app.showingOpening && !showRoom {
                StartupOpeningView(ready: app.openingReady) { transitionRequested = true }
                    .allowsHitTesting(!transitionRequested)
                    .disabled(transitionRequested)
            }

            Color.black.opacity(blackOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background(Color.black)
        .onChange(of: app.showingOpening) { showing in
            guard showing else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                transitionRequested = false
                showRoom = false
                blackOpacity = 0
            }
        }
        .task(id: transitionRequested) {
            guard transitionRequested, app.showingOpening else { return }
            let fadeOut = reduceMotion ? 0.15 : 0.65
            let fadeIn = reduceMotion ? 0.15 : 0.8
            do {
                withAnimation(.easeInOut(duration: fadeOut)) { blackOpacity = 1 }
                try await Task.sleep(nanoseconds: UInt64(fadeOut * 1_000_000_000))
                // Switch content only under a fully opaque black layer, without an implicit fade.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { showRoom = true }
                try await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.easeInOut(duration: fadeIn)) { blackOpacity = 0 }
                try await Task.sleep(nanoseconds: UInt64(fadeIn * 1_000_000_000))
                app.showingOpening = false
            } catch is CancellationError {
                // Closing the window cancels the transition without changing a later launch.
            } catch {
                NSLog("AIBOU opening transition interrupted: %@", error.localizedDescription)
            }
        }
    }
}
