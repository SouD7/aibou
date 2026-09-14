import Foundation

enum BookshelfVisualState: String, Codable, CaseIterable {
    case sparse, normal, overflow
}

enum DeskVisualState: String, Codable, CaseIterable {
    case normal, stacked, overflow
}

enum DisplayVisualState: String, Codable, CaseIterable {
    case normal, staticNoise
}

enum FanVisualState: String, Codable, CaseIterable {
    case stopped, slow, fast
}

enum StatusLightVisualState: String, Codable, CaseIterable {
    case cyan, yellow, red
}

struct RoomStateOption: Identifiable, Equatable {
    let id: String
    let title: String
    let isDefault: Bool
}

enum RoomVisualStateError: LocalizedError, Equatable {
    case invalidBedLights(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBedLights(let value): return "ベッドの点灯数は0〜4で指定してください（受信値: \(value)）。"
        }
    }
}

struct RoomVisualState: Codable, Equatable {
    private(set) var bedLights: Int
    private(set) var bookshelf: BookshelfVisualState
    private(set) var desk: DeskVisualState
    private(set) var display: DisplayVisualState
    private(set) var fans: FanVisualState
    private(set) var network: StatusLightVisualState
    private(set) var compute: StatusLightVisualState

    init() {
        bedLights = 4
        bookshelf = .normal
        desk = .normal
        display = .normal
        fans = .slow
        network = .cyan
        compute = .cyan
    }

    init(bedLights: Int, bookshelf: BookshelfVisualState, desk: DeskVisualState,
         display: DisplayVisualState, fans: FanVisualState,
         network: StatusLightVisualState, compute: StatusLightVisualState) throws {
        guard (0...4).contains(bedLights) else { throw RoomVisualStateError.invalidBedLights(bedLights) }
        self.bedLights = bedLights; self.bookshelf = bookshelf; self.desk = desk
        self.display = display; self.fans = fans; self.network = network; self.compute = compute
    }

    enum CodingKeys: String, CodingKey {
        case bedLights, bookshelf, desk, display, fans, network, compute
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let bedLights = try values.decodeIfPresent(Int.self, forKey: .bedLights) ?? 4
        guard (0...4).contains(bedLights) else { throw RoomVisualStateError.invalidBedLights(bedLights) }
        self.bedLights = bedLights
        bookshelf = try values.decodeIfPresent(BookshelfVisualState.self, forKey: .bookshelf) ?? .normal
        desk = try values.decodeIfPresent(DeskVisualState.self, forKey: .desk) ?? .normal
        display = try values.decodeIfPresent(DisplayVisualState.self, forKey: .display) ?? .normal
        fans = try values.decodeIfPresent(FanVisualState.self, forKey: .fans) ?? .slow
        network = try values.decodeIfPresent(StatusLightVisualState.self, forKey: .network) ?? .cyan
        compute = try values.decodeIfPresent(StatusLightVisualState.self, forKey: .compute) ?? .cyan
    }

    static func options(for componentID: String) -> [RoomStateOption] {
        switch canonicalComponentID(componentID) {
        case "bed":
            return (0...4).map { RoomStateOption(id: String($0), title: "\($0)灯", isDefault: $0 == 4) }
        case "bookshelf":
            return [RoomStateOption(id: "sparse", title: "スカスカ", isDefault: false),
                    RoomStateOption(id: "normal", title: "中くらい", isDefault: true),
                    RoomStateOption(id: "overflow", title: "あふれる", isDefault: false)]
        case "desk":
            return [RoomStateOption(id: "normal", title: "通常", isDefault: true),
                    RoomStateOption(id: "stacked", title: "書類の山", isDefault: false),
                    RoomStateOption(id: "overflow", title: "書類があふれる", isDefault: false)]
        case "display":
            return [RoomStateOption(id: "normal", title: "通常", isDefault: true),
                    RoomStateOption(id: "staticNoise", title: "砂嵐", isDefault: false)]
        case "fans":
            return [RoomStateOption(id: "stopped", title: "停止", isDefault: false),
                    RoomStateOption(id: "slow", title: "ゆっくり", isDefault: true),
                    RoomStateOption(id: "fast", title: "高速", isDefault: false)]
        case "network", "compute":
            return [RoomStateOption(id: "cyan", title: "水色", isDefault: true),
                    RoomStateOption(id: "yellow", title: "黄", isDefault: false),
                    RoomStateOption(id: "red", title: "赤", isDefault: false)]
        default:
            return []
        }
    }

    func currentOptionID(for componentID: String) -> String? {
        switch Self.canonicalComponentID(componentID) {
        case "bed": return String(bedLights)
        case "bookshelf": return bookshelf.rawValue
        case "desk": return desk.rawValue
        case "display": return display.rawValue
        case "fans": return fans.rawValue
        case "network": return network.rawValue
        case "compute": return compute.rawValue
        default: return nil
        }
    }

    func applying(optionID: String, for componentID: String) -> RoomVisualState? {
        var next = self
        switch Self.canonicalComponentID(componentID) {
        case "bed":
            guard let value = Int(optionID), (0...4).contains(value), String(value) == optionID else { return nil }
            next.bedLights = value
        case "bookshelf":
            guard let value = BookshelfVisualState(rawValue: optionID) else { return nil }
            next.bookshelf = value
        case "desk":
            guard let value = DeskVisualState(rawValue: optionID) else { return nil }
            next.desk = value
        case "display":
            guard let value = DisplayVisualState(rawValue: optionID) else { return nil }
            next.display = value
        case "fans":
            guard let value = FanVisualState(rawValue: optionID) else { return nil }
            next.fans = value
        case "network":
            guard let value = StatusLightVisualState(rawValue: optionID) else { return nil }
            next.network = value
        case "compute":
            guard let value = StatusLightVisualState(rawValue: optionID) else { return nil }
            next.compute = value
        default:
            return nil
        }
        return next
    }

    private static func canonicalComponentID(_ id: String) -> String {
        ["fan-1", "fan-2", "fans"].contains(id) ? "fans" : id
    }
}
