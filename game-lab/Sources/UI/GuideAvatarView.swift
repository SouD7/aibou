import AppKit
import SpriteKit
import SwiftUI

enum GuideMood: String {
    case greeting, observing, thinking, pointing, celebrate

    fileprivate var pose: AvatarPoseID {
        switch self {
        case .greeting, .celebrate, .pointing: return .standingFrontHands
        case .observing: return .standing
        case .thinking: return .standingBackHands
        }
    }

    fileprivate var description: String {
        switch self {
        case .greeting: return "一緒に作る準備をしています"
        case .observing: return "あなたの実験を見守っています"
        case .thinking: return "回路を一緒に考えています"
        case .pointing: return "次に試す場所を案内しています"
        case .celebrate: return "完成を一緒に喜んでいます"
        }
    }
}

/// The actual adopted AIBOU character, using the same rig and face processing as
/// avatar-motion. It only loads the three standing poses and their blink patch.
struct GuideAvatarView: View {
    var mood: GuideMood
    var speaking: Bool
    var reducedMotion: Bool
    var fullBody = false

    var body: some View {
        GuideAvatarSurface(mood: mood, speaking: speaking, reducedMotion: reducedMotion, fullBody: fullBody)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("AIBOU。\(speaking ? "お話ししています" : mood.description)")
            .accessibilityIdentifier("guide.avatar")
            .allowsHitTesting(false)
    }
}

private struct GuideAvatarSurface: NSViewRepresentable {
    let mood: GuideMood
    let speaking: Bool
    let reducedMotion: Bool
    let fullBody: Bool

    func makeNSView(context: Context) -> GuideSpriteView {
        let view = GuideSpriteView(fullBody: fullBody)
        view.configure(mood: mood, speaking: speaking, reducedMotion: reducedMotion)
        return view
    }

    func updateNSView(_ view: GuideSpriteView, context: Context) {
        view.configure(mood: mood, speaking: speaking, reducedMotion: reducedMotion)
    }

    static func dismantleNSView(_ view: GuideSpriteView, coordinator: ()) {
        view.detach()
    }
}

private final class GuideRenderingView: SKView {
    override var isOpaque: Bool { false }
}

private final class GuideSpriteView: NSView {
    private let spriteView = GuideRenderingView(frame: .zero)
    private let posterView = NSImageView(frame: .zero)
    private var guideScene: GuidePortraitScene?
    private var observations: [NSObjectProtocol] = []
    private var refreshGeneration = 0
    private var reducedMotion = false
    private var detached = false
    private let canvasSize: CGSize

    init(bundle: Bundle = .main, fullBody: Bool = false) {
        canvasSize = CGSize(width: 500, height: fullBody ? 750 : 680)
        super.init(frame: .zero)
        spriteView.allowsTransparency = true
        spriteView.ignoresSiblingOrder = true
        spriteView.shouldCullNonVisibleNodes = true
        spriteView.preferredFramesPerSecond = 30
        spriteView.isHidden = true
        spriteView.isPaused = true
        posterView.imageScaling = .scaleProportionallyUpOrDown
        posterView.imageAlignment = .alignCenter
        for child in [spriteView, posterView] {
            child.frame = bounds
            child.autoresizingMask = [.width, .height]
            addSubview(child)
        }
        do {
            guideScene = try GuidePortraitScene(bundle: bundle, fullBody: fullBody)
            posterView.image = guideScene?.poster(for: .greeting)
        } catch {
            // Keep the lesson usable if a distribution accidentally lacks art.
            let label = NSTextField(wrappingLabelWithString: "AIBOU\n字幕で一緒に進めよう")
            label.alignment = .center
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -20)
            ])
        }
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in
                guard let self, let changedWindow = note.object as? NSWindow,
                      changedWindow === self.window else { return }
                if name == NSWindow.willCloseNotification { self.detach() }
                else { self.updateVisibility() }
            })
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.updateVisibility()
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        // SpriteKit's aspectFit letterbox can become opaque on macOS. Fit its
        // actual native view to the portrait, leaving transparent parent space.
        let scale = min(bounds.width / canvasSize.width, bounds.height / canvasSize.height)
        let size = NSSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        spriteView.frame = NSRect(x: bounds.midX - size.width / 2,
                                  y: bounds.midY - size.height / 2,
                                  width: size.width, height: size.height)
        posterView.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateVisibility()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateVisibility()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateVisibility()
    }

    func configure(mood: GuideMood, speaking: Bool, reducedMotion: Bool) {
        self.reducedMotion = reducedMotion
        guideScene?.configure(mood: mood, speaking: speaking, reducedMotion: reducedMotion)
        posterView.image = guideScene?.poster(for: mood)
        updateVisibility()
    }

    private var canRender: Bool {
        guard !detached, let window else { return false }
        return !isHiddenOrHasHiddenAncestor && !window.isMiniaturized && !NSApp.isHidden
            && window.occlusionState.contains(.visible)
    }

    private func updateVisibility() {
        refreshGeneration += 1
        guard canRender, !reducedMotion, let guideScene else {
            guideScene?.onNextFrame = nil
            guideScene?.pauseMotion()
            posterView.isHidden = false
            spriteView.isHidden = true
            spriteView.isPaused = true
            // Keep a native static portrait visible while removing the offscreen
            // SpriteKit scene. Screenshots never depend on a live GPU surface.
            spriteView.presentScene(nil)
            return
        }
        if spriteView.scene === guideScene, !spriteView.isPaused, posterView.isHidden { return }
        posterView.isHidden = false
        spriteView.isHidden = false
        let generation = refreshGeneration
        // Reveal animation only after SpriteKit has actually updated a frame.
        // If a covered/background window never starts rendering, its native
        // portrait remains visible indefinitely, without a repeating timer.
        guideScene.onNextFrame = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, self.refreshGeneration == generation,
                      self.canRender, !self.reducedMotion else { return }
                self.posterView.isHidden = true
            }
        }
        if spriteView.scene !== guideScene { spriteView.presentScene(guideScene) }
        guideScene.pauseMotion()
        spriteView.isPaused = false
    }

    func detach() {
        detached = true
        updateVisibility()
    }

    deinit { observations.forEach(NotificationCenter.default.removeObserver) }
}

private final class GuidePortraitScene: SKScene {
    private var visuals: [AvatarPoseID: PoseVisual] = [:]
    private var mouths: [AvatarPoseID: GuideSpeakingMouth] = [:]
    private var posters: [AvatarPoseID: NSImage] = [:]
    var onNextFrame: (() -> Void)?
    private var mood: GuideMood = .greeting
    private var speaking = false
    private var reducedMotion = false
    private var elapsed = 0.0
    private var lastFrame: TimeInterval?

    init(bundle: Bundle = .main, fullBody: Bool = false) throws {
        let canvas = Point2(500, fullBody ? 750 : 680)
        guard let directory = bundle.resourceURL?.appendingPathComponent("GuideAssets") else {
            throw ManifestError.resourceMissing("GuideAssets")
        }
        let rig = try RigManifest.load(from: directory.appendingPathComponent("rig.json"))
        super.init(size: CGSize(width: canvas.x, height: canvas.y))
        scaleMode = .aspectFit
        backgroundColor = .clear
        anchorPoint = .zero

        for id in AvatarPoseID.standingVariants {
            guard var pose = rig.pose(id) else { throw ManifestError.poseMissing(id) }
            guard var image = NSImage(contentsOf: directory.appendingPathComponent(pose.image)) else {
                throw ManifestError.resourceMissing(pose.image)
            }
            if pose.chromaKey, let processed = ImageProcessing.removeGreenScreen(from: image) { image = processed }
            var blinkTextures: [SKTexture?] = []
            if let name = pose.blinkImage, var aligned = NSImage(contentsOf: directory.appendingPathComponent(name)) {
                if pose.chromaKey, let processed = ImageProcessing.removeGreenScreen(from: aligned) { aligned = processed }
                blinkTextures = pose.eyes.map {
                    ImageProcessing.featheredCrop(from: aligned, normalized: $0).map(SKTexture.init(image:))
                }
            }
            // A portrait crop makes the existing face and hand poses legible at
            // 250 x 340. All normalized face/warp anchors retain their geometry.
            pose.size = fullBody ? Point2(500, 750) : Point2(680, 1020)
            pose.center = fullBody ? Point2(250, 375) : Point2(250, 526)
            pose.shadowOpacity = 0
            pose.shadowCenter = Point2(250, 1200)
            posters[id] = Self.makePoster(image: image, pose: pose, canvas: canvas)
            let mouth = GuideSpeakingMouth(pose: pose)
            // Preserve the original painted skin and smile corners instead of
            // using a solid skin cover at this larger face size.
            pose.mouth = nil
            let texture = SKTexture(image: image)
            texture.filteringMode = .linear
            let visual = PoseVisual(manifest: pose, canvas: canvas, texture: texture, blinkTextures: blinkTextures)
            if let mouth { mouths[id] = mouth; visual.addChild(mouth) }
            visual.isHidden = id != mood.pose
            visuals[id] = visual
            addChild(visual)
        }
        applyFrame()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(mood: GuideMood, speaking: Bool, reducedMotion: Bool) {
        self.mood = mood
        self.speaking = speaking
        self.reducedMotion = reducedMotion
        for (id, visual) in visuals { visual.isHidden = id != mood.pose }
        applyFrame()
    }

    func poster(for mood: GuideMood) -> NSImage? { posters[mood.pose] }

    private static func makePoster(image: NSImage, pose: PoseManifest, canvas: Point2) -> NSImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(canvas.x), pixelsHigh: Int(canvas.y), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: CGRect(x: pose.center.x - pose.size.x / 2,
                              y: canvas.y - pose.center.y - pose.size.y / 2,
                              width: pose.size.x, height: pose.size.y),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let poster = NSImage(size: NSSize(width: canvas.x, height: canvas.y))
        poster.addRepresentation(bitmap)
        return poster
    }

    func pauseMotion() { lastFrame = nil }

    override func didFinishUpdate() {
        let callback = onNextFrame
        onNextFrame = nil
        callback?()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !reducedMotion else { return }
        if let lastFrame { elapsed += min(max(currentTime - lastFrame, 0), 1.0 / 15.0) }
        lastFrame = currentTime
        applyFrame()
    }

    private func applyFrame() {
        let time = reducedMotion ? 0 : elapsed
        // Speech-aware motion, not phoneme lip-sync; the synthesizer is the
        // source of speaking state. No mouth movement in reduced-motion mode.
        let amplitude = speaking && !reducedMotion
            ? 0.18 + 0.30 * abs(sin(time * 14.3) * cos(time * 6.1)) : 0
        let visual = visuals[mood.pose]
        visual?.apply(input: MotionInput(time: time, strength: reducedMotion ? 0 : 0.6,
                                        reducedMotion: reducedMotion, speechAmplitude: amplitude,
                                        forceBlink: reducedMotion ? 0 : nil))
        mouths[mood.pose]?.apply(input: MotionInput(time: time, strength: reducedMotion ? 0 : 0.6,
                                                  reducedMotion: reducedMotion, speechAmplitude: amplitude))
        // Intent cues use the adopted standing poses plus a slight inclination;
        // they do not pretend the flat art has independently rigged arms/eyes.
        let inclination: Double
        switch mood {
        case .pointing: inclination = -0.014
        case .thinking: inclination = 0.014
        case .celebrate: inclination = reducedMotion ? 0 : sin(time * 3.8) * 0.009
        case .greeting, .observing: inclination = 0
        }
        visual?.zRotation = inclination
    }
}

private final class GuideSpeakingMouth: SKNode {
    private let pose: PoseManifest
    private let rect: Rect4
    private let mouth: SKShapeNode

    init?(pose: PoseManifest) {
        guard let rect = pose.mouth else { return nil }
        self.pose = pose
        self.rect = rect
        mouth = SKShapeNode()
        super.init()
        zPosition = 6
        mouth.fillColor = NSColor(srgbRed: 0.39, green: 0.16, blue: 0.20, alpha: 1)
        mouth.strokeColor = NSColor(srgbRed: 0.62, green: 0.31, blue: 0.33, alpha: 0.75)
        mouth.lineWidth = 0.6
        mouth.zPosition = 1
        addChild(mouth)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(input: MotionInput) {
        let opening = input.reducedMotion ? 0 : MotionMath.clamp(input.speechAmplitude)
        isHidden = opening < 0.01
        guard !isHidden else { return }
        let center = rect.center
        let offset = MotionMath.displacement(at: center, pose: pose, input: input)
        position = CGPoint(x: (center.x + offset.x - 0.5) * pose.size.x,
                           y: (0.5 - center.y - offset.y) * pose.size.y)
        let width = rect.width * pose.size.x * (0.67 - opening * 0.12)
        let height = rect.height * pose.size.y * (0.12 + opening * 0.85)
        mouth.path = CGPath(ellipseIn: CGRect(x: -width / 2, y: -height / 2,
                                              width: width, height: height), transform: nil)
    }
}
