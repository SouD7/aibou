import AppKit
import SpriteKit
import simd
import CoreImage

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: UInt64
        switch cleaned.count {
        case 8: (r, g, b, a) = (value >> 24, value >> 16 & 255, value >> 8 & 255, value & 255)
        default: (r, g, b, a) = (value >> 16, value >> 8 & 255, value & 255, 255)
        }
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                  blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

final class PoseVisual: SKNode {
    private let manifest: PoseManifest
    private let canvas: Point2
    private let sprite: SKSpriteNode
    private let shadow: SKShapeNode
    private let shadowEffect: SKEffectNode
    private var eyeOverlays: [(rect: Rect4, cover: SKShapeNode, lash: SKShapeNode, patch: SKSpriteNode?)] = []
    private var mouthOverlay: (rect: Rect4, cover: SKShapeNode, mouth: SKShapeNode)?
    private var pageOverlay: (rect: Rect4, page: SKShapeNode)?
    private let glitchLayer = SKNode()
    private var glitchStrips: [SKSpriteNode] = []
    private let columns = 16
    private let rows = 24

    init(manifest: PoseManifest, canvas: Point2, texture: SKTexture,
         blinkTextures: [SKTexture?] = []) {
        self.manifest = manifest; self.canvas = canvas
        sprite = SKSpriteNode(texture: texture, size: CGSize(width: manifest.size.x, height: manifest.size.y))
        let shadowSize = manifest.shadowSize ?? Point2(manifest.size.x * 0.45, manifest.size.y * 0.045)
        shadow = SKShapeNode(ellipseOf: CGSize(width: shadowSize.x, height: shadowSize.y))
        shadowEffect = SKEffectNode()
        super.init()

        name = manifest.id.rawValue
        position = CGPoint(x: manifest.center.x, y: canvas.y - manifest.center.y)
        shadow.fillColor = NSColor.black.withAlphaComponent(manifest.shadowOpacity ?? 0.20)
        shadow.strokeColor = .clear
        shadowEffect.filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: max(5, shadowSize.y * 0.34)])
        shadowEffect.shouldRasterize = true; shadowEffect.zPosition = -2
        if let center = manifest.shadowCenter {
            shadow.position = CGPoint(x: center.x - manifest.center.x, y: manifest.center.y - center.y)
        } else {
            shadow.position = CGPoint(x: 0, y: -manifest.size.y * 0.475)
        }
        addChild(shadowEffect); shadowEffect.addChild(shadow)
        sprite.zPosition = 0; addChild(sprite)
        glitchLayer.name = "arrival-noise"
        glitchLayer.zPosition = 1; glitchLayer.isHidden = true; addChild(glitchLayer)
        createFaceOverlays(blinkTextures: blinkTextures)
        createPageOverlay()
        apply(input: MotionInput(time: 0))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func localPoint(_ normalized: Point2) -> CGPoint {
        CGPoint(x: (normalized.x - 0.5) * manifest.size.x,
                y: (0.5 - normalized.y) * manifest.size.y)
    }

    private func createFaceOverlays(blinkTextures: [SKTexture?]) {
        let skin = NSColor(hex: manifest.skin)
        for (index, rect) in manifest.eyes.enumerated() {
            let size = CGSize(width: rect.width * manifest.size.x, height: rect.height * manifest.size.y)
            let cover = SKShapeNode(rectOf: size, cornerRadius: size.height * 0.45)
            cover.fillColor = skin; cover.strokeColor = .clear; cover.zPosition = 3; cover.isHidden = true
            let lashPath = CGMutablePath()
            lashPath.move(to: CGPoint(x: -size.width * 0.38, y: 0))
            lashPath.addQuadCurve(to: CGPoint(x: size.width * 0.38, y: 0), control: CGPoint(x: 0, y: -size.height * 0.18))
            let lash = SKShapeNode(path: lashPath)
            lash.strokeColor = NSColor(calibratedWhite: 0.12, alpha: 0.9)
            lash.lineWidth = max(1, size.height * 0.11); lash.lineCap = .round
            lash.zPosition = 4; lash.isHidden = true
            addChild(cover); addChild(lash)
            let patch: SKSpriteNode?
            if index < blinkTextures.count, let texture = blinkTextures[index] {
                let node = SKSpriteNode(texture: texture, size: size)
                node.zPosition = 5; node.alpha = 0; node.isHidden = true
                addChild(node); patch = node
            } else { patch = nil }
            eyeOverlays.append((rect, cover, lash, patch))
        }
        if let rect = manifest.mouth {
            let size = CGSize(width: rect.width * manifest.size.x, height: rect.height * manifest.size.y)
            let cover = SKShapeNode(rectOf: CGSize(width: size.width * 1.14, height: size.height * 1.25), cornerRadius: size.height * 0.45)
            cover.fillColor = skin; cover.strokeColor = .clear; cover.zPosition = 3
            let mouth = SKShapeNode(ellipseOf: CGSize(width: size.width * 0.62, height: max(1.4, size.height * 0.10)))
            mouth.fillColor = NSColor(red: 0.28, green: 0.12, blue: 0.14, alpha: 0.92)
            mouth.strokeColor = .clear; mouth.zPosition = 4
            addChild(cover); addChild(mouth)
            mouthOverlay = (rect, cover, mouth)
        }
    }

    private func createPageOverlay() {
        guard let rect = manifest.book else { return }
        let width = rect.width * manifest.size.x
        let height = rect.height * manifest.size.y
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -height * 0.42))
        path.addQuadCurve(to: CGPoint(x: 0, y: height * 0.42), control: CGPoint(x: width * 0.56, y: height * 0.55))
        path.addQuadCurve(to: CGPoint(x: 0, y: -height * 0.42), control: CGPoint(x: width * 0.46, y: -height * 0.55))
        let page = SKShapeNode(path: path)
        page.fillColor = NSColor(calibratedWhite: 0.97, alpha: 0.68)
        page.strokeColor = NSColor(calibratedWhite: 0.45, alpha: 0.35)
        page.lineWidth = 0.8; page.zPosition = 2; page.isHidden = true
        addChild(page); pageOverlay = (rect, page)
    }

    func apply(input: MotionInput) {
        let destinations = MotionMath.destinationGrid(columns: columns, rows: rows, pose: manifest, input: input)
        sprite.warpGeometry = SKWarpGeometryGrid(columns: columns, rows: rows,
            sourcePositions: MotionMath.sourceGrid(columns: columns, rows: rows),
            destinationPositions: destinations)
        let output = MotionMath.output(for: manifest.id, input: input)

        for item in eyeOverlays {
            let point = item.rect.center
            let delta = MotionMath.displacement(at: point, pose: manifest, input: input)
            let position = localPoint(Point2(point.x + delta.x, point.y + delta.y))
            item.cover.position = position; item.lash.position = position; item.patch?.position = position
            if let patch = item.patch {
                item.cover.isHidden = true; item.lash.isHidden = true
                patch.isHidden = output.blink < 0.01
                patch.alpha = CGFloat(output.blink)
            } else {
                item.cover.isHidden = output.blink < 0.06; item.lash.isHidden = output.blink < 0.06
                item.cover.yScale = max(0.12, output.blink)
                item.lash.alpha = output.blink
            }
        }
        if let item = mouthOverlay {
            let point = item.rect.center
            let delta = MotionMath.displacement(at: point, pose: manifest, input: input)
            let position = localPoint(Point2(point.x + delta.x, point.y + delta.y))
            item.cover.position = position; item.mouth.position = position
            item.cover.isHidden = output.mouthOpen < 0.015
            item.mouth.isHidden = output.mouthOpen < 0.015
            let baseHeight = max(1.4, item.rect.height * manifest.size.y * 0.10)
            let openHeight = item.rect.height * manifest.size.y * (0.18 + output.mouthOpen * 0.82)
            let width = item.rect.width * manifest.size.x * (0.62 - output.mouthOpen * 0.16)
            item.mouth.path = CGPath(ellipseIn: CGRect(x: -width / 2, y: -max(baseHeight, openHeight) / 2,
                                                       width: width, height: max(baseHeight, openHeight)), transform: nil)
        }
        if let item = pageOverlay {
            let point = item.rect.center
            let delta = MotionMath.displacement(at: point, pose: manifest, input: input)
            item.page.position = localPoint(Point2(point.x + delta.x, point.y + delta.y))
            item.page.isHidden = output.pageTurn < 0.02
            item.page.xScale = CGFloat(0.18 + output.pageTurn * 0.82)
            item.page.zRotation = CGFloat(-0.22 + output.pageTurn * 0.44)
            item.page.alpha = CGFloat(output.pageTurn)
        }
    }

    /// Texture slices create brief horizontal signal interference on the avatar only.
    /// The shadow and room remain stable. Cached subtextures share the original atlas.
    func setArrivalNoise(progress: Double?) {
        guard let progress else {
            glitchLayer.isHidden = true; sprite.isHidden = false; return
        }
        if glitchStrips.isEmpty, let texture = sprite.texture {
            let count = 32
            for index in 0..<count {
                let strip = SKSpriteNode(texture: SKTexture(rect: CGRect(x: 0, y: Double(index) / Double(count),
                    width: 1, height: 1 / Double(count)), in: texture),
                    size: CGSize(width: manifest.size.x, height: manifest.size.y / Double(count)))
                strip.color = NSColor(hex: "#B8EAFF")
                glitchLayer.addChild(strip); glitchStrips.append(strip)
            }
        }
        sprite.isHidden = true; glitchLayer.isHidden = false
        let tick = floor(progress * 12)
        let strength = 1 - progress * 0.75
        for (index, strip) in glitchStrips.enumerated() {
            let seed = sin(Double(index) * 17.17 + tick * 9.31)
            let affected = abs(seed) > 0.56
            strip.position = CGPoint(x: affected ? seed * 19 * strength : 0,
                y: -manifest.size.y / 2 + (Double(index) + 0.5) * manifest.size.y / Double(glitchStrips.count))
            strip.colorBlendFactor = affected ? 0.45 * strength : 0
            strip.alpha = affected ? 0.78 : 1
        }
    }

    var electricAnchor: CGPoint {
        convert(localPoint(manifest.chest), to: parent!)
    }

    func setFocus(_ focused: Bool) {
        if focused {
            let desired = manifest.focusSize ?? Point2(canvas.x * 0.50, canvas.y * 0.88)
            let factor = min(desired.x / manifest.size.x, desired.y / manifest.size.y)
            position = CGPoint(x: canvas.x / 2, y: canvas.y / 2)
            setScale(factor)
            shadow.position = CGPoint(x: 0, y: -manifest.size.y * 0.475)
        } else {
            position = CGPoint(x: manifest.center.x, y: canvas.y - manifest.center.y)
            setScale(1)
            if let center = manifest.shadowCenter {
                shadow.position = CGPoint(x: center.x - manifest.center.x, y: manifest.center.y - center.y)
            } else { shadow.position = CGPoint(x: 0, y: -manifest.size.y * 0.475) }
        }
    }
}

final class AvatarScene: SKScene {
    let manifest: RigManifest
    let componentCatalog: RoomComponentCatalog
    private let componentHighlights: RoomComponentHighlights
    private let warningBadges: RoomWarningBadges
    private(set) var componentWarnings: [String: ComponentWarning] = [:]
    var onWarningsChange: (([String: ComponentWarning]) -> Void)?
    private(set) var hoveredComponent: RoomComponent?
    private(set) var selectedComponent: RoomComponent?
    var onComponentSelection: ((RoomComponent?) -> Void)?
    private let room: SKSpriteNode
    var roomFrameIndex: Int { (room as? AnimatedRoomNode)?.frameIndex ?? 0 }
    private var visuals: [AvatarPoseID: PoseVisual] = [:]
    private(set) var currentPose: AvatarPoseID = .standing
    private let electricEffect = ElectricTransitionEffect()
    private(set) var poseTransition: ElectricTransition?
    private var frameTime = 0.0
    var motionStrength = 1.0
    var reducedMotion = false {
        didSet {
            warningBadges.update(componentWarnings, reducedMotion: reducedMotion || animationPaused)
            if reducedMotion { finishPoseTransition() }
        }
    }
    var speechAmplitude = 0.0
    var forceBlink: Double?
    var focused = false { didSet { applyFocus() } }
    private var lastFrameTime: TimeInterval?
    private var motionTime = 0.0
    private var animationPaused = false
    private var deterministicTime: Double?

    init(manifest: RigManifest, resourceDirectory: URL) throws {
        self.manifest = manifest
        componentCatalog = try RoomComponentCatalog.load(
            from: resourceDirectory.appendingPathComponent("room-components.json"), canvas: manifest.canvas)
        componentHighlights = RoomComponentHighlights(canvas: manifest.canvas)
        warningBadges = RoomWarningBadges(catalog: componentCatalog)
        let sceneSize = CGSize(width: manifest.canvas.x, height: manifest.canvas.y)
        let roomDirectory = resourceDirectory.appendingPathComponent("RoomAnimation")
        if FileManager.default.fileExists(atPath: roomDirectory.appendingPathComponent("manifest.json").path) {
            room = try AnimatedRoomNode(directory: roomDirectory, canvas: manifest.canvas)
        } else if let image = NSImage(contentsOf: resourceDirectory.appendingPathComponent("room.png")) {
            room = SKSpriteNode(texture: SKTexture(image: image), size: sceneSize)
        } else {
            room = SKSpriteNode(color: NSColor(red: 0.12, green: 0.105, blue: 0.13, alpha: 1), size: sceneSize)
        }
        super.init(size: sceneSize)
        scaleMode = .aspectFit; anchorPoint = .zero
        backgroundColor = NSColor(red: 0.075, green: 0.068, blue: 0.085, alpha: 1)
        room.position = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        room.zPosition = -10; addChild(room)
        addChild(componentHighlights)
        addChild(warningBadges)
        addChild(electricEffect)
        for pose in manifest.poses {
            let url = resourceDirectory.appendingPathComponent(pose.image)
            guard var image = NSImage(contentsOf: url) else { throw ManifestError.resourceMissing(pose.image) }
            if pose.chromaKey, let processed = ImageProcessing.removeGreenScreen(from: image) { image = processed }
            var blinkTextures: [SKTexture?] = []
            if let blinkImage = pose.blinkImage,
               var aligned = NSImage(contentsOf: resourceDirectory.appendingPathComponent(blinkImage)) {
                if pose.chromaKey, let processed = ImageProcessing.removeGreenScreen(from: aligned) { aligned = processed }
                blinkTextures = pose.eyes.map {
                    ImageProcessing.featheredCrop(from: aligned, normalized: $0).map(SKTexture.init(image:))
                }
            }
            let visual = PoseVisual(manifest: pose, canvas: manifest.canvas, texture: SKTexture(image: image),
                                    blinkTextures: blinkTextures)
            visual.isHidden = pose.id != currentPose
            visuals[pose.id] = visual; addChild(visual)
        }
        guard visuals[currentPose] != nil else { throw ManifestError.poseMissing(currentPose) }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func hoverRoom(at point: CGPoint?) {
        let component = point.flatMap { point in
            roomComponent(at: point)
        }
        hoveredComponent = component
        componentHighlights.showHover(component, at: point)
    }

    func selectRoom(at point: CGPoint) {
        guard !focused else { return }
        let component = roomComponent(at: point)
        selectRoomComponent(component?.id)
    }

    private func roomComponent(at point: CGPoint) -> RoomComponent? {
        guard !focused else { return nil }
        if let id = warningBadges.componentID(at: point) {
            return componentCatalog.components.first { $0.id == id }
        }
        return componentCatalog.component(at: Point2(point.x, size.height - point.y))
    }

    /// Invoke on the main thread when a backend status changes. nil clears only this component.
    @discardableResult
    func setComponentWarning(_ warning: ComponentWarning?, for id: String) -> Bool {
        guard componentCatalog.components.contains(where: { $0.id == id }) else { return false }
        var next = componentWarnings
        next[id] = warning
        replaceComponentWarnings(next)
        return true
    }

    /// Complete backend snapshot: missing component IDs are cleared; unknown IDs are ignored.
    func replaceComponentWarnings(_ warnings: [String: ComponentWarning]) {
        let known = Set(componentCatalog.components.map(\.id))
        let next = warnings.filter { known.contains($0.key) }
        guard next != componentWarnings else { return }
        componentWarnings = next
        warningBadges.update(next, reducedMotion: reducedMotion || animationPaused)
        onWarningsChange?(next)
    }

    func selectRoomComponent(_ id: String?) {
        hoverRoom(at: nil)
        let component = focused ? nil : componentCatalog.components.first { $0.id == id }
        selectedComponent = component
        componentHighlights.showSelection(component)
        onComponentSelection?(component)
    }

    func selectPose(_ pose: AvatarPoseID, animated: Bool = true) {
        guard visuals[pose] != nil else { return }
        let previous = currentPose
        currentPose = pose
        guard animated, !animationPaused, !isPaused, !reducedMotion, !focused else {
            finishPoseTransition(); return
        }
        // During a jump, remember only the latest requested destination. Complete the
        // current transition first so rapid clicks never leave detached effects or two bodies.
        guard poseTransition == nil else { return }
        guard previous != pose else { return }
        beginPoseTransition(from: previous, to: pose, at: frameTime)
    }

    private func beginPoseTransition(from: AvatarPoseID, to: AvatarPoseID, at time: Double) {
        guard !(from.isStanding && to.isStanding),
              let source = visuals[from], let target = visuals[to] else {
            finishPoseTransition(); return
        }
        poseTransition = ElectricTransition(from: from, to: to, startedAt: time,
                                            origin: source.electricAnchor, destination: target.electricAnchor)
        applyFrame(time)
    }

    private func finishPoseTransition() {
        poseTransition = nil; electricEffect.isHidden = true
        for (id, visual) in visuals {
            visual.isHidden = id != currentPose; visual.alpha = 1
            visual.setArrivalNoise(progress: nil)
        }
    }

    func setDeterministicTime(_ time: Double?) { deterministicTime = time; applyFrame(time ?? 0) }

    func setAnimationPaused(_ paused: Bool) {
        animationPaused = paused
        if paused {
            finishPoseTransition()
            warningBadges.update(componentWarnings, reducedMotion: true)
        }
        isPaused = paused
        lastFrameTime = nil
    }

    override func update(_ currentTime: TimeInterval) {
        guard !animationPaused, !isPaused else { lastFrameTime = nil; return }
        guard deterministicTime == nil else { applyFrame(deterministicTime ?? 0); return }
        guard let previous = lastFrameTime else {
            lastFrameTime = currentTime; applyFrame(motionTime); return
        }
        // Clamp long display gaps so wake/resume never jumps the body to another phase.
        motionTime += min(max(currentTime - previous, 0), 1.0 / 15.0)
        lastFrameTime = currentTime
        applyFrame(motionTime)
    }

    func applyFrame(_ time: Double) {
        frameTime = time
        (room as? AnimatedRoomNode)?.apply(time: time, reducedMotion: reducedMotion)
        let input = MotionInput(time: time, strength: motionStrength, reducedMotion: reducedMotion,
                                speechAmplitude: speechAmplitude, forceBlink: forceBlink)
        guard let transition = poseTransition else {
            visuals[currentPose]?.apply(input: input); return
        }
        let sample = transition.sample(at: time)
        if sample.finished {
            let arrived = transition.to
            finishPoseTransition()
            if arrived != currentPose {
                beginPoseTransition(from: arrived, to: currentPose, at: time)
            } else { visuals[currentPose]?.apply(input: input) }
            return
        }
        for (id, visual) in visuals {
            let opacity = id == transition.from ? sample.outgoingAlpha :
                (id == transition.to ? sample.incomingAlpha : 0)
            visual.alpha = opacity; visual.isHidden = opacity == 0
            if opacity > 0 { visual.apply(input: input) }
            visual.setArrivalNoise(progress: id == transition.to ? sample.noiseProgress : nil)
        }
        electricEffect.render(transition, at: time)
    }

    private func applyFocus() {
        finishPoseTransition()
        room.isHidden = focused
        componentHighlights.isHidden = focused
        warningBadges.isHidden = focused
        hoverRoom(at: nil)
        if focused { selectRoomComponent(nil) }
        visuals.values.forEach { $0.setFocus(focused) }
    }
}

enum SceneLoader {
    static func load(bundle: Bundle = .main) throws -> (AvatarScene, URL) {
        guard let assets = bundle.resourceURL?.appendingPathComponent("Assets") else {
            throw ManifestError.resourceMissing("Assets")
        }
        let manifest = try RigManifest.load(from: assets.appendingPathComponent("rig.json"))
        return (try AvatarScene(manifest: manifest, resourceDirectory: assets), assets)
    }
}
