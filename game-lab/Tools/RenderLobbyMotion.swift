import AppKit
import SpriteKit
import SwiftUI

/// Offline visual verification of the same SpriteKit scene used by the lobby.
/// Creates no window, generates no input events, and reads no user's save data.
@main
struct RenderLobbyMotion {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("Usage: render-lobby <art-directory> <output-directory>") }
        let out = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        guard let art = LobbyAnimationArt.load(directory: URL(fileURLWithPath: args[1])) else { fatalError("Missing art") }
        let size = CGSize(width: 1600, height: 900)
        let scene = LobbyCharacterScene(art: art)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.allowsTransparency = true
        view.presentScene(scene)
        view.isPaused = true
        let deskPath = LobbyReceptionForeground().path(in: CGRect(origin: .zero, size: size)).cgPath
        let frameCount = 204
        for index in 0..<frameCount {
            autoreleasepool {
                let time = Double(index) / 30
                scene.apply(time: time, animate: true)
                guard let character = view.texture(from: scene, crop: CGRect(origin: .zero, size: size))?.cgImage(),
                      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 900,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 6400, bitsPerPixel: 32),
                      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Renderer failed") }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                let cg = context.cgContext
                art.background.draw(in: CGRect(origin: .zero, size: size))
                cg.draw(character, in: CGRect(origin: .zero, size: size))
                cg.saveGState()
                cg.translateBy(x: 0, y: 900); cg.scaleBy(x: 1, y: -1)
                cg.addPath(deskPath); cg.clip()
                cg.translateBy(x: 0, y: 900); cg.scaleBy(x: 1, y: -1)
                art.background.draw(in: CGRect(origin: .zero, size: size))
                cg.restoreGState()
                NSGraphicsContext.restoreGraphicsState()
                guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG failed") }
                try! data.write(to: out.appendingPathComponent(String(format: "frame-%03d.png", index)))
            }
        }
        print("Rendered \(frameCount) frames at 30 fps using production scene; blink only.")
    }
}
