import AppKit
import Foundation

@main
struct AvatarWindowEventTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        // No asset bundle is needed to reproduce the old false pause from a sheet.
        let store = AvatarStore()
        let unrelatedSheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                      styleMask: [.titled], backing: .buffered, defer: false)
        let notifications = NotificationCenter.default
        precondition(!store.effectivelyPaused)
        notifications.post(name: NSWindow.didChangeOcclusionStateNotification, object: unrelatedSheet)
        precondition(!store.effectivelyPaused, "Closing a different window must not pause the room")
        notifications.post(name: NSWindow.didMiniaturizeNotification, object: unrelatedSheet)
        precondition(!store.effectivelyPaused, "Other windows cannot set the room's visibility")
        store.paused = true
        notifications.post(name: NSWindow.didDeminiaturizeNotification, object: unrelatedSheet)
        precondition(store.effectivelyPaused, "Other windows cannot override manual pause")
        store.paused = false
        notifications.post(name: NSApplication.didHideNotification, object: NSApplication.shared)
        precondition(store.effectivelyPaused)
        notifications.post(name: NSApplication.didUnhideNotification, object: NSApplication.shared)
        precondition(!store.effectivelyPaused)
        print("AvatarWindowEventTests: OK (sheet events do not pause the room)")
    }
}
