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
            IntegratedWindow(app: app)
                .frame(minWidth: 960, minHeight: 660)
                .background(RoomWindowSetup())
                .onAppear { delegate.app = app }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 850)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
#endif

struct RoomWindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> RoomWindowSetupView { RoomWindowSetupView() }
    func updateNSView(_ view: RoomWindowSetupView, context: Context) {}
}

final class RoomWindowSetupView: NSView {
    private var configured = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !configured else { return }
        configured = true
        window.title = "AIBOU"
        window.titlebarAppearsTransparent = true
        window.collectionBehavior.insert(.fullScreenPrimary)
        guard !CommandLine.arguments.contains("--windowed") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak window] in
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }
}
