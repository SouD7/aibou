import AppKit
import QuartzCore
import SwiftUI

/// The illustrated guide used on the physical workbench. Facial features stay
/// as painted: no generic face patches are applied to the tilted portrait.
struct IllustratedGuideView: View {
    var speaking: Bool
    var reducedMotion: Bool
    var compact: Bool
    var notebook = false

    var body: some View {
        Group {
            if let art = notebook ? IllustratedGuideArt.notebook : IllustratedGuideArt.shared {
                IllustratedGuideSurface(image: compact ? art.portrait : art.presenting,
                                        speaking: speaking, reducedMotion: reducedMotion)
            } else {
                GuideAvatarView(mood: .greeting, speaking: speaking, reducedMotion: reducedMotion)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(speaking ? "AIBOUが案内しています" : "AIBOUが回路を一緒に見ています")
        .accessibilityIdentifier("guide.avatar")
        .allowsHitTesting(false)
    }
}

private struct IllustratedGuideArt {
    let presenting: NSImage
    let portrait: NSImage

    static let shared = load()
    static let notebook = loadNotebook()

    static func loadNotebook(bundle: Bundle = .main) -> IllustratedGuideArt? {
        guard let url = bundle.resourceURL?.appendingPathComponent("ExhibitionArt/guide-notebook.png"),
              let original = NSImage(contentsOf: url),
              let transparent = ImageProcessing.removeGreenScreen(from: original),
              let image = transparent.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return shared }
        let bounds = CGRect(x: Double(image.width) * 0.16, y: 0,
                            width: Double(image.width) * 0.60, height: Double(image.height) * 0.44).integral
        guard let crop = image.cropping(to: bounds) else { return shared }
        return IllustratedGuideArt(presenting: transparent,
            portrait: NSImage(cgImage: crop, size: NSSize(width: crop.width, height: crop.height)))
    }

    static func load(bundle: Bundle = .main) -> IllustratedGuideArt? {
        guard let url = bundle.resourceURL?.appendingPathComponent("WorkshopArt/guide-presenting-v1.png"),
              let original = NSImage(contentsOf: url),
              let transparent = ImageProcessing.removeGreenScreen(from: original),
              let image = transparent.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // Generated source is 1024 x 1536. The large view keeps the presenting
        // hand and upper body; the compact view intentionally focuses on the face.
        func crop(_ normalized: CGRect) -> NSImage? {
            let rect = CGRect(x: normalized.minX * Double(image.width),
                              y: normalized.minY * Double(image.height),
                              width: normalized.width * Double(image.width),
                              height: normalized.height * Double(image.height)).integral
            guard let part = image.cropping(to: rect) else { return nil }
            return NSImage(cgImage: part, size: NSSize(width: part.width, height: part.height))
        }
        guard let presenting = crop(CGRect(x: 0, y: 0, width: 1, height: 0.73)),
              let portrait = crop(CGRect(x: 0.34, y: 0, width: 0.55, height: 0.37)) else { return nil }
        return IllustratedGuideArt(presenting: presenting, portrait: portrait)
    }
}

private struct IllustratedGuideSurface: NSViewRepresentable {
    let image: NSImage
    let speaking: Bool
    let reducedMotion: Bool

    func makeNSView(context: Context) -> IllustratedGuideNativeView {
        let view = IllustratedGuideNativeView()
        view.configure(image: image, speaking: speaking, reducedMotion: reducedMotion)
        return view
    }

    func updateNSView(_ view: IllustratedGuideNativeView, context: Context) {
        view.configure(image: image, speaking: speaking, reducedMotion: reducedMotion)
    }

    static func dismantleNSView(_ view: IllustratedGuideNativeView, coordinator: ()) { view.detach() }
}

private final class IllustratedGuideNativeView: NSView {
    private let portrait = NSImageView(frame: .zero)
    private var observations: [NSObjectProtocol] = []
    private var speaking = false
    private var reducedMotion = false
    private var detached = false
    private var animatedSpeaking: Bool?

    override var isOpaque: Bool { false }

    init() {
        super.init(frame: .zero)
        portrait.imageScaling = .scaleProportionallyUpOrDown
        portrait.imageAlignment = .alignBottom
        portrait.wantsLayer = true
        addSubview(portrait)
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in
                guard let self, let changedWindow = note.object as? NSWindow, changedWindow === self.window else { return }
                if name == NSWindow.willCloseNotification { self.detach() }
                else { self.updateMotion() }
            })
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.updateMotion()
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        // A small inset leaves breathing room for the subtle animation while
        // preserving every edge of the presenting hand and the hair.
        portrait.frame = bounds.insetBy(dx: 2, dy: 2)
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateMotion() }
    override func viewDidHide() { super.viewDidHide(); updateMotion() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateMotion() }

    func configure(image: NSImage, speaking: Bool, reducedMotion: Bool) {
        portrait.image = image
        self.speaking = speaking
        self.reducedMotion = reducedMotion
        updateMotion()
    }

    private func updateMotion() {
        let visible = !detached && !isHiddenOrHasHiddenAncestor && window != nil
            && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
            && NSApp.isActive && !NSApp.isHidden
        guard visible, !reducedMotion else {
            portrait.layer?.removeAnimation(forKey: "guide.breathing")
            animatedSpeaking = nil
            return
        }
        guard animatedSpeaking != speaking else { return }
        animatedSpeaking = speaking
        // Core Animation handles a small breathing motion without a display
        // timer or per-frame SwiftUI updates. Speech uses a slightly quicker cue;
        // it is intentionally not presented as phoneme lip sync.
        let breath = CABasicAnimation(keyPath: "transform.scale.y")
        breath.fromValue = 1
        breath.toValue = speaking ? 1.004 : 1.0025
        breath.duration = speaking ? 1.25 : 2.3
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        portrait.layer?.add(breath, forKey: "guide.breathing")
    }

    func detach() { detached = true; updateMotion() }
    deinit { observations.forEach(NotificationCenter.default.removeObserver) }
}
