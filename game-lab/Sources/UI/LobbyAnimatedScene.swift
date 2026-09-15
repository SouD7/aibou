import AppKit
import SpriteKit
import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

/// Only the lobby uses this separated scene. Other exhibition art is unchanged.
struct LobbyAnimatedScene: View {
    var reducedMotion: Bool
    var active: Bool

    var body: some View {
        Group {
            if let art = LobbyAnimationArt.shared {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: art.background).resizable().frame(width: 1600, height: 900)
                    LobbyCharacterSurface(art: art, reducedMotion: reducedMotion, active: active)
                        .frame(width: 1600, height: 900)
                    // The same clean plate supplies the foreground: there can
                    // be no second, baked-in character around the lamp or desk.
                    Image(nsImage: art.background).resizable().frame(width: 1600, height: 900)
                        .clipShape(LobbyReceptionForeground())
                }
            } else {
                ExhibitionRoomArt(name: "lobby")
            }
        }.frame(width: 1600, height: 900).allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct LobbyReceptionForeground: Shape {
    func path(in rect: CGRect) -> Path {
        // Original artwork coordinates (1672 x 941), scaled with the room.
        let sx = rect.width / 1672, sy = rect.height / 941
        var path = Path()
        let points: [(CGFloat, CGFloat)] = [(0, 640), (164, 665), (636, 708), (636, 941), (0, 941)]
        path.move(to: CGPoint(x: points[0].0 * sx, y: points[0].1 * sy))
        for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0 * sx, y: point.1 * sy)) }
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: 355 * sx, y: 657 * sy, width: 45 * sx, height: 59 * sy))
        path.addRect(CGRect(x: 361 * sx, y: 691 * sy, width: 34 * sx, height: 51 * sy))
        return path
    }
}

final class LobbyAnimationArt {
    let background: NSImage
    let character: SKTexture
    let eyes: [(Rect4, SKTexture)]
    static let shared = load()

    private init(background: NSImage, character: SKTexture, eyes: [(Rect4, SKTexture)]) {
        self.background = background; self.character = character; self.eyes = eyes
    }

    static func load(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("ExhibitionArt")) -> LobbyAnimationArt? {
        guard let base = directory,
              let background = NSImage(contentsOf: base.appendingPathComponent("LobbyMotion/background.png")),
              let original = NSImage(contentsOf: base.appendingPathComponent("guide-notebook.png")),
              let clear = ImageProcessing.removeGreenScreen(from: original),
              let blink = NSImage(contentsOf: base.appendingPathComponent("LobbyMotion/blink.png")) else { return nil }
        // Eye patches use the exact generated pose. Mouth and body are static.
        func normalized(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Rect4 {
            Rect4(x / 1145, y / 1374, w / 1145, h / 1374)
        }
        let eyeRects = [normalized(465, 299, 125, 103), normalized(627, 239, 97, 113)]
        var eyes: [(Rect4, SKTexture)] = []
        for rect in eyeRects {
            guard let crop = ImageProcessing.featheredCrop(from: blink, normalized: rect, featherPixels: 7) else { return nil }
            eyes.append((rect, SKTexture(image: crop)))
        }
        return LobbyAnimationArt(background: background, character: SKTexture(image: clear), eyes: eyes)
    }
}

final class LobbyCharacterScene: SKScene {
    private let character: SKSpriteNode
    private var eyes: [(Rect4, SKSpriteNode)] = []
    private let characterSize = CGSize(width: 374, height: 448.8)
    private let characterCenter = CGPoint(x: 285, y: 450)
    private var elapsed: Double = 0
    private var lastUpdate: TimeInterval?
    var motionEnabled = true

    init(art: LobbyAnimationArt) {
        character = SKSpriteNode(texture: art.character, size: characterSize)
        super.init(size: CGSize(width: 1600, height: 900))
        backgroundColor = .clear
        scaleMode = .resizeFill
        character.position = characterCenter
        addChild(character)
        for (rect, texture) in art.eyes {
            let node = SKSpriteNode(texture: texture)
            setup(node, rect: rect)
            eyes.append((rect, node))
        }
        apply(time: 0, animate: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup(_ node: SKSpriteNode, rect: Rect4) {
        node.size = CGSize(width: rect.width * characterSize.width, height: rect.height * characterSize.height)
        node.zPosition = 2
        node.position = CGPoint(x: characterCenter.x + (rect.center.x - 0.5) * characterSize.width,
                                y: characterCenter.y + (0.5 - rect.center.y) * characterSize.height)
        addChild(node)
    }

    func resetClock() { lastUpdate = nil }

    override func update(_ currentTime: TimeInterval) {
        let dt = min(1.0 / 15, max(0, currentTime - (lastUpdate ?? currentTime)))
        lastUpdate = currentTime
        guard motionEnabled else { return }
        elapsed += dt
        apply(time: elapsed, animate: true)
    }

    func rest() {
        lastUpdate = nil
        apply(time: 0, animate: false)
    }

    func apply(time: Double, animate: Bool) {
        let t = animate ? time : 0
        let blink = animate ? LobbyMotion.blink(at: t) : 0
        for (_, node) in eyes {
            // Quick expression substitution avoids the double-iris appearance
            // of a long dissolve. The eyelids are briefly held fully closed.
            node.alpha = blink > 0.25 ? 1 : 0
        }
    }
}

private struct LobbyCharacterSurface: NSViewRepresentable {
    let art: LobbyAnimationArt
    var reducedMotion: Bool
    var active: Bool

    func makeNSView(context: Context) -> LobbyCharacterView { LobbyCharacterView(art: art) }
    func updateNSView(_ view: LobbyCharacterView, context: Context) {
        view.configure(reducedMotion: reducedMotion, active: active)
    }
    static func dismantleNSView(_ view: LobbyCharacterView, coordinator: ()) { view.detach() }
}

private final class LobbyCharacterView: SKView {
    private let lobbyScene: LobbyCharacterScene
    private var observers: [NSObjectProtocol] = []
    private var active = true, reduced = false, detached = false

    init(art: LobbyAnimationArt) {
        lobbyScene = LobbyCharacterScene(art: art)
        super.init(frame: .zero)
        allowsTransparency = true
        preferredFramesPerSecond = 30
        ignoresSiblingOrder = false
        presentScene(lobbyScene)
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification,
                     NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if let changed = note.object as? NSWindow, changed !== self.window { return }
                if name == NSWindow.willCloseNotification { self.detach() }
                else { self.refreshVisibility() }
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshVisibility() }
    override func viewDidHide() { super.viewDidHide(); refreshVisibility() }
    override func viewDidUnhide() { super.viewDidUnhide(); refreshVisibility() }

    func configure(reducedMotion: Bool, active: Bool) {
        self.active = active; reduced = reducedMotion
        refreshVisibility()
    }
    private func refreshVisibility() {
        let enabled = !detached && active && !reduced && window != nil && !isHiddenOrHasHiddenAncestor
            && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
            && NSApp.isActive && !NSApp.isHidden
        if !enabled { lobbyScene.rest() }
        if isPaused == enabled { lobbyScene.resetClock() }
        lobbyScene.motionEnabled = enabled
        isPaused = !enabled
    }
    func detach() { detached = true; refreshVisibility(); presentScene(nil) }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
