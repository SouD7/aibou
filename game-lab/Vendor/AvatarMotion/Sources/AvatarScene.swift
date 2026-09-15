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
    private let room: SKSpriteNode
    var roomFrameIndex: Int { (room as? AnimatedRoomNode)?.frameIndex ?? 0 }
    private var visuals: [AvatarPoseID: PoseVisual] = [:]
    private(set) var currentPose: AvatarPoseID = .standing
    var motionStrength = 1.0
    var reducedMotion = false
    var speechAmplitude = 0.0
    var forceBlink: Double?
    var focused = false { didSet { applyFocus() } }
    private var lastFrameTime: TimeInterval?
    private var motionTime = 0.0
    private var animationPaused = false
    private var deterministicTime: Double?

    init(manifest: RigManifest, resourceDirectory: URL) throws {
        self.manifest = manifest
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

    func selectPose(_ pose: AvatarPoseID) {
        guard visuals[pose] != nil else { return }
        currentPose = pose
        for (id, visual) in visuals { visual.isHidden = id != pose }
        applyFocus()
    }

    func setDeterministicTime(_ time: Double?) { deterministicTime = time; applyFrame(time ?? 0) }

    func setAnimationPaused(_ paused: Bool) {
        animationPaused = paused
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
        (room as? AnimatedRoomNode)?.apply(time: time, reducedMotion: reducedMotion)
        let input = MotionInput(time: time, strength: motionStrength, reducedMotion: reducedMotion,
                                speechAmplitude: speechAmplitude, forceBlink: forceBlink)
        visuals[currentPose]?.apply(input: input)
    }

    private func applyFocus() {
        room.isHidden = focused
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
