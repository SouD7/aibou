import Foundation

/// Reproduce the six approved imageState descriptions through public actions.
/// Histories and intermediate states are earned by simulation, never injected.
enum ParallelRepresentative {
    static func factory() -> ParallelFactoryModel {
        var m = ParallelFactoryModel(stage:2)
        for _ in 0..<12 { m.send(.step) }
        m.send(.workers(2));m.send(.assign(2,1));m.send(.assign(4,1))
        for _ in 0..<4 { m.send(.step) }
        precondition(m.isValid && m.tick == 4 && m.completedCount == 3 && m.workers == 2)
        precondition(m.tasks[0].isDone && m.tasks[1].isDone && m.tasks[2].isDone && m.tasks[3].remaining == 2 && m.tasks[4].remaining == 2)
        precondition(m.trials.contains { $0.key == "w1" && $0.ticks == 12 })
        return m
    }
    static func pixel() -> ParallelPixelModel {
        var m = ParallelPixelModel(stage:2)
        for _ in 0..<16 { m.send(.step) }
        m.send(.device(true));for _ in 0..<4 { m.send(.step) }
        precondition(m.isValid && m.tick == 4 && m.processed == 8 && m.phase == "計算")
        precondition(m.trials.contains { $0.key == "cpu" && $0.ticks == 16 })
        return m
    }
    static func display() -> ParallelDisplayModel {
        var m = ParallelDisplayModel(stage:2)
        for _ in 0..<60 { m.send(.step) }
        m.send(.window(0))
        precondition(m.isValid && m.fps == 30 && m.hz == 60 && m.generated.count == 30 && m.displayed.count == 60 && m.distinct == 30)
        precondition(Array(m.displayed.prefix(6)).map(\.frameID) == [0,0,1,1,2,2])
        return m
    }
    static func packet() -> ParallelPacketModel {
        var m = ParallelPacketModel(stage:2)
        for _ in 0..<11 { m.send(.step) }
        m.send(.bandwidth(4));for _ in 0..<4 { m.send(.step) }
        precondition(m.isValid && m.tick == 4 && m.deliveredCount == 4 && m.firstArrival == 4 && !m.runFinished)
        precondition(m.packets.prefix(4).allSatisfy(\.delivered) && m.packets.suffix(4).allSatisfy { !$0.delivered && $0.arrival == 5 })
        precondition(m.trials.contains { $0.ticks == 11 && $0.values[0] == 1 && $0.values[3] == 4 })
        return m
    }
    static func board() -> ParallelBoardModel {
        var m = ParallelBoardModel(stage:4)
        m.send(.step);m.send(.step)
        precondition(m.isValid && m.soc && m.capacity == 1 && m.tick == 2 && m.cpuReceived == 1 && m.gpuReceived == 1)
        precondition(m.waitingUnits == ["CPU2","GPU2"])
        return m
    }
    static func connection() -> ParallelConnectionModel {
        var m = ParallelConnectionModel(stage:2)
        m.send(.inspect)
        precondition(m.isValid && m.connectedIDs == [0] && m.connections[0].port == "B" && m.connections[0].cable == "α")
        precondition(m.checks.first { $0.label == "形" }?.status == 1 && m.checks.first { $0.label == "映像" }?.status == 0 && m.checks.first { $0.label == "給電" }?.status == 1)
        return m
    }
}
