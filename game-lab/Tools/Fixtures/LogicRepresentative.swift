import Foundation
#if canImport(CircuitCore)
import CircuitCore
#endif

/// Offline screenshot fixtures for the six original concept images. Only public
/// gameplay actions construct these states; no real player save is loaded.
enum LogicRepresentative {
    static func bitArt() -> LogicBitArtModel {
        var model = LogicBitArtModel(stage: 3)
        model.send(.select(6))
        model.send(.switchMapping)
        precondition(model.binary == "101" && model.value == 5 && model.colors[6] == 6 && model.totalBits == 48)
        return model
    }

    static func circuit() -> CircuitExperienceModel {
        var model = CircuitExperienceModel(stage: 3)
        model.send(.setInputs(InputPair(a: true, b: false)))
        model.send(.observe)
        precondition(model.circuit.selectedGate == .and && model.circuit.links.count == 3)
        precondition(model.circuit.output == .low && model.observations.count == 1)
        precondition(model.observations[0].inputs == InputPair(a: true, b: false))
        // The concept is a revisit with the name AND already discovered. The new
        // checkpoint model names parts after verification; its first visit still
        // shows “パーツ01”. Do not fake verified state just for a screenshot.
        return model
    }

    static func memorySwitch() -> LogicMemorySwitchModel {
        var model = LogicMemorySwitchModel(stage: 3)
        // Stage 3 intentionally starts at D0/Q1. Writing 0 first constructs the
        // concept's four visible D/Q pairs via real operations. The oldest shown
        // event therefore says “書く” rather than the concept's “初期”.
        model.send(.write)
        model.send(.toggle(0))
        model.send(.write)
        model.send(.toggle(0))
        precondition(model.input == [0] && model.stored == [1] && model.output == [1])
        let visible = Array(model.events.suffix(4))
        precondition(visible.map(\.input) == [[0], [1], [1], [0]])
        precondition(visible.map(\.stored) == [[0], [0], [1], [1]])
        return model
    }

    static func tinySwitch() -> LogicTinySwitchModel {
        var model = LogicTinySwitchModel(stage: 3)
        for i in 0..<2 { model.send(.place(i)); model.send(.connect(i)) }
        model.send(.changeLayout(.parallel))
        model.send(.toggle(0))
        precondition(model.layout == .parallel && model.inputs == [1, 0] && model.output == 1)
        precondition(model.isClosed(0) && !model.isClosed(1))
        return model
    }

    static func instruction() -> LogicInstructionModel {
        var model = LogicInstructionModel(stage: 3)
        for command: LogicInstructionModel.Instruction in [.read, .store0, .read, .add0, .output] { model.send(.append(command)) }
        for _ in 0..<3 { model.send(.step) }
        precondition(model.accumulator == 3 && model.memory[0] == 2 && model.pc == 3)
        precondition(model.output.isEmpty && model.expected == [5] && model.inputIndex == 2)
        return model
    }

    static func dispatch() -> LogicWorkDispatchModel {
        var model = LogicWorkDispatchModel(stage: 3)
        model.send(.admit(0)); model.send(.admit(1))
        model.send(.select(0)); model.send(.step); model.send(.select(1))
        precondition(model.capacity == 6 && model.used == 5 && model.tick == 1)
        precondition(model.jobs[0].done == 1 && model.jobs[1].done == 0 && model.selected == 1)
        return model
    }
}
