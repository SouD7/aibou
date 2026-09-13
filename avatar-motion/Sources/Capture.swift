import AppKit
import SpriteKit

struct CaptureRequest {
    let directory: URL
    let poses: [AvatarPoseID]
    let times: [Double]
    let qa: Bool
    let focus: Bool

    static func parse(_ arguments: [String]) -> CaptureRequest? {
        guard let index = arguments.firstIndex(of: "--capture-dir"), index + 1 < arguments.count else { return nil }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        let pose: AvatarPoseID? = arguments.firstIndex(of: "--pose").flatMap {
            $0 + 1 < arguments.count ? AvatarPoseID(rawValue: arguments[$0 + 1]) : nil
        }
        let time: Double? = arguments.firstIndex(of: "--time").flatMap {
            $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil
        }
        let qa = arguments.contains("--qa")
        return CaptureRequest(directory: directory,
                              poses: pose.map { [$0] } ?? (qa ? AvatarPoseID.allCases : [.standing]),
                              times: time.map { [$0] } ?? (qa ? [0, 1] : [0]), qa: qa,
                              focus: arguments.contains("--focus"))
    }
}

enum SceneCapture {
    static func run(_ request: CaptureRequest, bundle: Bundle = .main) throws {
        try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)
        let loaded = try SceneLoader.load(bundle: bundle)
        let scene = loaded.0
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1003, height: 565))
        view.presentScene(scene)
        scene.focused = request.focus
        var records: [[String: Any]] = []
        for pose in request.poses {
            scene.selectPose(pose)
            for time in request.times {
                scene.forceBlink = nil; scene.speechAmplitude = 0; scene.setDeterministicTime(time)
                let name = "\(pose.rawValue)-t\(String(format: "%.2f", time))"
                try save(scene: scene, view: view, url: request.directory.appendingPathComponent(name + ".png"))
                records.append(["file": name + ".png", "pose": pose.rawValue, "time": time,
                                "blink": MotionMath.output(for: pose, input: MotionInput(time: time)).blink,
                                "speech": 0, "focus": request.focus])
            }
        }
        if request.qa {
            scene.focused = true
            for pose in request.poses {
                scene.selectPose(pose); scene.forceBlink = nil; scene.speechAmplitude = 0
                scene.setDeterministicTime(1)
                let name = "\(pose.rawValue)-focus"
                try save(scene: scene, view: view, url: request.directory.appendingPathComponent(name + ".png"))
                records.append(["file": name + ".png", "pose": pose.rawValue, "time": 1,
                                "blink": 0, "speech": 0, "focus": true])
            }
            scene.selectPose(.standing)
            for variant in [("standing-blink", 1.0, 0.0), ("standing-speech", 0.0, 0.72)] {
                scene.forceBlink = variant.1; scene.speechAmplitude = variant.2; scene.setDeterministicTime(2)
                try save(scene: scene, view: view, url: request.directory.appendingPathComponent(variant.0 + ".png"))
                records.append(["file": variant.0 + ".png", "pose": "standing", "time": 2,
                                "blink": variant.1, "speech": variant.2, "focus": true])
            }
        }
        let metadata: [String: Any] = ["canvas": [scene.size.width, scene.size.height],
                                       "renderSize": [view.frame.width, view.frame.height], "frames": records]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: request.directory.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private static func save(scene: SKScene, view: SKView, url: URL) throws {
        guard let texture = view.texture(from: scene) else {
            throw NSError(domain: "AIBOUCapture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "SpriteKit のフレーム取得に失敗しました。"])
        }
        let image = texture.cgImage()
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "AIBOUCapture", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "PNGの生成に失敗しました。"])
        }
        try data.write(to: url, options: .atomic)
    }
}
