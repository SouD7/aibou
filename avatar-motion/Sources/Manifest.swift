import Foundation

struct Point2: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        x = try values.decode(Double.self)
        y = try values.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(x); try values.encode(y)
    }
}

struct Rect4: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        x = try values.decode(Double.self); y = try values.decode(Double.self)
        width = try values.decode(Double.self); height = try values.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(x); try values.encode(y); try values.encode(width); try values.encode(height)
    }

    var center: Point2 { Point2(x + width / 2, y + height / 2) }
}

enum AvatarPoseID: String, CaseIterable, Codable, Identifiable {
    case standing
    case standingBackHands = "standing-back-hands"
    case standingFrontHands = "standing-front-hands"
    case sleeping, reading

    static let primaryModes: [AvatarPoseID] = [.standing, .sleeping, .reading]
    static let standingVariants: [AvatarPoseID] = [.standing, .standingBackHands, .standingFrontHands]

    var id: String { rawValue }
    var isStanding: Bool { Self.standingVariants.contains(self) }
    var japaneseTitle: String {
        switch self {
        case .standing, .standingBackHands, .standingFrontHands: return "立つ"
        case .sleeping: return "眠る"
        case .reading: return "読む"
        }
    }
    var standingVariantTitle: String {
        switch self {
        case .standing: return "通常"
        case .standingBackHands: return "後ろで組む"
        case .standingFrontHands: return "前で組む"
        case .sleeping, .reading: return japaneseTitle
        }
    }
    var symbol: String {
        switch self {
        case .standing, .standingBackHands, .standingFrontHands: return "figure.stand"
        case .sleeping: return "bed.double.fill"
        case .reading: return "book.fill"
        }
    }
}

struct PoseManifest: Codable, Equatable, Identifiable {
    var id: AvatarPoseID
    var image: String
    var center: Point2
    var size: Point2
    var head: Point2
    var chest: Point2
    var hip: Point2
    var eyes: [Rect4]
    var mouth: Rect4?
    var book: Rect4?
    var skin: String
    var shadowCenter: Point2?
    var shadowSize: Point2?
    var shadowOpacity: Double?
    var focusSize: Point2?
    var chromaKey: Bool
    var blinkImage: String?

    enum CodingKeys: String, CodingKey {
        case id, image, center, size, head, chest, hip, eyes, mouth, book, skin
        case shadowCenter, shadowSize, shadowOpacity, focusSize, chromaKey, blinkImage
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(AvatarPoseID.self, forKey: .id)
        image = try values.decode(String.self, forKey: .image)
        center = try values.decode(Point2.self, forKey: .center)
        size = try values.decode(Point2.self, forKey: .size)
        head = try values.decode(Point2.self, forKey: .head)
        chest = try values.decode(Point2.self, forKey: .chest)
        hip = try values.decode(Point2.self, forKey: .hip)
        eyes = try values.decodeIfPresent([Rect4].self, forKey: .eyes) ?? []
        mouth = try values.decodeIfPresent(Rect4.self, forKey: .mouth)
        book = try values.decodeIfPresent(Rect4.self, forKey: .book)
        skin = try values.decodeIfPresent(String.self, forKey: .skin) ?? "#F4DCCF"
        shadowCenter = try values.decodeIfPresent(Point2.self, forKey: .shadowCenter)
        shadowSize = try values.decodeIfPresent(Point2.self, forKey: .shadowSize)
        shadowOpacity = try values.decodeIfPresent(Double.self, forKey: .shadowOpacity)
        focusSize = try values.decodeIfPresent(Point2.self, forKey: .focusSize)
        chromaKey = try values.decodeIfPresent(Bool.self, forKey: .chromaKey) ?? false
        blinkImage = try values.decodeIfPresent(String.self, forKey: .blinkImage)
    }
}

struct RigManifest: Codable, Equatable {
    var canvas: Point2
    var poses: [PoseManifest]

    func pose(_ id: AvatarPoseID) -> PoseManifest? { poses.first { $0.id == id } }

    static func load(from url: URL) throws -> RigManifest {
        try JSONDecoder().decode(RigManifest.self, from: Data(contentsOf: url))
    }
}

enum ManifestError: LocalizedError {
    case resourceMissing(String)
    case poseMissing(AvatarPoseID)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name): return "リソースが見つかりません: \(name)"
        case .poseMissing(let pose): return "rig.json に \(pose.rawValue) の設定がありません。"
        }
    }
}
