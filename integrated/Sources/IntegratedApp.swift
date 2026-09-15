import SwiftUI

@MainActor
final class IntegratedDelegate: NSObject, NSApplicationDelegate {
    weak var app: IntegratedStore?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let app else { return .terminateNow }
        app.avatar.voice.stop()
        app.consultation.disconnect()
        app.monitor.shutdown()
        let cleanup = DispatchGroup()
        cleanup.enter()
        app.monitor.afterPendingSaves { cleanup.leave() }
        cleanup.enter()
        app.consultation.afterPendingShutdown { cleanup.leave() }
        cleanup.notify(queue: .main) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

#if !AIBOU_TESTING
@main
struct AIBOUApp: App {
    @NSApplicationDelegateAdaptor(IntegratedDelegate.self) private var delegate
    @StateObject private var app = IntegratedStore()

    var body: some Scene {
        WindowGroup("AIBOU") {
            IntegratedLaunchView(app: app)
                .frame(minWidth: 960, minHeight: 660)
                .background(RoomWindowSetup(ready: { app.openingReady = true }))
                .onAppear { delegate.app = app }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("コンポーネント") {
                RoomComponentMenuItems(app: app, avatar: app.avatar)
                    .disabled(app.showingOpening || app.showingLearning || app.session.isDemo || app.presentation != nil || app.showingConnection)
            }
        }
    }
}
#endif

struct RoomWindowSetup: NSViewRepresentable {
    let ready: () -> Void
    func makeNSView(context: Context) -> RoomWindowSetupView {
        let view = RoomWindowSetupView()
        view.ready = ready
        return view
    }
    func updateNSView(_ view: RoomWindowSetupView, context: Context) {}
}

final class RoomWindowSetupView: NSView {
    var ready: () -> Void = {}
    private var configured = false
    private var observers: [NSObjectProtocol] = []
    private var readinessFallback: DispatchWorkItem?

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func completeSetup() {
        readinessFallback?.cancel()
        readinessFallback = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        ready()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !configured else { return }
        configured = true
        window.title = "AIBOU"
        window.titlebarAppearsTransparent = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        guard !CommandLine.arguments.contains("--windowed"), !window.styleMask.contains(.fullScreen) else {
            DispatchQueue.main.async { [weak self] in self?.completeSetup() }
            return
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.completeSetup()
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak window] in
            guard let self, let window else { return }
            guard !window.styleMask.contains(.fullScreen) else { self.completeSetup(); return }
            // SwiftUI owns the window delegate, including the fullscreen failure callback.
            // Bound the wait if AppKit never posts a successful transition notification.
            let fallback = DispatchWorkItem { [weak self] in
                NSLog("AIBOU opening: fullscreen readiness timed out; continuing in the current window")
                self?.completeSetup()
            }
            self.readinessFallback = fallback
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: fallback)
            window.toggleFullScreen(nil)
        }
    }
}
