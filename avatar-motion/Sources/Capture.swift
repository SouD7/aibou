import AppKit
import SpriteKit

struct CaptureRequest {
    let directory: URL
    let poses: [AvatarPoseID]
    let times: [Double]
    let qa: Bool
    let focus: Bool
    let transitionFrom: AvatarPoseID?

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
        let sequenceDuration: Double? = arguments.firstIndex(of: "--sequence").flatMap {
            $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil
        }
        let fps = arguments.firstIndex(of: "--fps").flatMap {
            $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil
        } ?? 10
        let sequenceTimes: [Double]? = sequenceDuration.flatMap { duration in
            guard duration.isFinite, duration > 0, duration <= 30, fps.isFinite, fps >= 1, fps <= 60 else { return nil }
            return (0..<Int((duration * fps).rounded(.up))).map { Double($0) / fps }
        }
        return CaptureRequest(directory: directory,
                              poses: pose.map { [$0] } ?? (qa ? AvatarPoseID.allCases : [.standing]),
                              times: sequenceTimes ?? time.map { [$0] } ?? (qa ? [0, 1] : [0]), qa: qa,
                              focus: arguments.contains("--focus"),
                              transitionFrom: arguments.firstIndex(of: "--transition-from").flatMap {
                                  $0 + 1 < arguments.count ? AvatarPoseID(rawValue: arguments[$0 + 1]) : nil
                              })
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
            scene.selectPose(request.transitionFrom ?? pose, animated: false)
            scene.setDeterministicTime(0)
            if request.transitionFrom != nil { scene.selectPose(pose) }
            for time in request.times {
                scene.forceBlink = nil; scene.speechAmplitude = 0; scene.setDeterministicTime(time)
                let name = "\(pose.rawValue)-t\(String(format: "%.2f", time))"
                try save(scene: scene, view: view, url: request.directory.appendingPathComponent(name + ".png"))
                records.append(["file": name + ".png", "pose": pose.rawValue, "time": time,
                                "blink": MotionMath.output(for: pose, input: MotionInput(time: time)).blink,
                                "speech": 0, "focus": request.focus, "roomFrame": scene.roomFrameIndex])
            }
        }
        if request.qa {
            scene.focused = true
            for pose in request.poses {
                scene.selectPose(pose, animated: false); scene.forceBlink = nil; scene.speechAmplitude = 0
                scene.setDeterministicTime(1)
                let name = "\(pose.rawValue)-focus"
                try save(scene: scene, view: view, url: request.directory.appendingPathComponent(name + ".png"))
                records.append(["file": name + ".png", "pose": pose.rawValue, "time": 1,
                                "blink": 0, "speech": 0, "focus": true])
            }
            for pose in request.poses.filter(\.isStanding) {
                scene.selectPose(pose, animated: false)
                for variant in [("blink", 1.0, 0.0), ("speech", 0.0, 0.72)] {
                    let name = "\(pose.rawValue)-\(variant.0)"
                    scene.forceBlink = variant.1; scene.speechAmplitude = variant.2; scene.setDeterministicTime(2)
                    try save(scene: scene, view: view, url: request.directory.appendingPathComponent(name + ".png"))
                    records.append(["file": name + ".png", "pose": pose.rawValue, "time": 2,
                                    "blink": variant.1, "speech": variant.2, "focus": true])
                }
            }
        }
        let metadata: [String: Any] = ["canvas": [scene.size.width, scene.size.height],
                                       "renderSize": [view.frame.width, view.frame.height], "frames": records]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: request.directory.appendingPathComponent("metadata.json"), options: .atomic)
    }

    private static func save(scene: SKScene, view: SKView, url: URL) throws {
        guard let texture = view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size)) else {
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
