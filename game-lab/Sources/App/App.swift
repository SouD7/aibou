import SwiftUI
import AppKit

@MainActor
final class GameLabDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct AIBOUGameLabApp: App {
    @NSApplicationDelegateAdaptor(GameLabDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("AIBOU · 展示館") {
            if ProcessInfo.processInfo.arguments.contains("--workshop") || ProcessInfo.processInfo.arguments.contains("--sandbox") {
                CircuitLabView()
            } else {
                ExhibitionAppView()
            }
        }.defaultSize(width: 1400, height: 920)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
