import Foundation

enum ThermalRepresentative {
    static func cooling() -> CoolingModel {
        var model = CoolingModel(stage: 2)
        for _ in 0..<8 { model.send(.step) }
        precondition(model.heat == 16 && model.work == 16 && !model.restricted)
        return model
    }
    static func bottleneck() -> BottleneckModel {
        var model = BottleneckModel(stage: 2)
        while model.canStep { model.send(.step) }
        precondition(model.tick == 8)
        model.send(.upgrade("cpu"))
        for _ in 0..<3 { model.send(.step) }
        precondition(model.unread == 0 && model.q1 == 2 && model.q2 == 2 && model.done == 2)
        return model
    }
}
