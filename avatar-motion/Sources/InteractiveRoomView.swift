import SwiftUI
import SpriteKit

struct InteractiveRoomView: NSViewRepresentable {
    let scene: AvatarScene

    func makeNSView(context: Context) -> RoomTrackingView {
        let view = RoomTrackingView()
        view.ignoresSiblingOrder = false
        view.presentScene(scene)
        view.setAccessibilityLabel("部屋。家具をクリックすると詳細を開きます")
        return view
    }
    func updateNSView(_ view: RoomTrackingView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
    }
    static func dismantleNSView(_ view: RoomTrackingView, coordinator: ()) {
        (view.scene as? AvatarScene)?.hoverRoom(at: nil)
        view.presentScene(nil)
    }
}

final class RoomTrackingView: SKView {
    private var pointerTracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking); pointerTracking = tracking
    }

    override func mouseMoved(with event: NSEvent) {
        guard let scene = scene as? AvatarScene else { return }
        let point = scene.convertPoint(fromView: convert(event.locationInWindow, from: nil))
        scene.hoverRoom(at: point)
        (scene.hoveredComponent == nil ? NSCursor.arrow : NSCursor.pointingHand).set()
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        (scene as? AvatarScene)?.hoverRoom(at: nil)
        NSCursor.arrow.set()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let scene = scene as? AvatarScene else { return }
        let point = scene.convertPoint(fromView: convert(event.locationInWindow, from: nil))
        scene.selectRoom(at: point)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { (scene as? AvatarScene)?.selectRoomComponent(nil) }
        else { super.keyDown(with: event) }
    }
}
