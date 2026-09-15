import Foundation

extension ParallelFactoryModel {
    public var isValid: Bool {
        guard (1...5).contains(stage), [1,2,4].contains(workers), (0...40).contains(tick), tasks.count >= 2, tasks.count <= 6,
              Set(tasks.map(\.id)).count == tasks.count, Set(queueOrder) == Set(tasks.map(\.id)), queueOrder.count == tasks.count else { return false }
        return tasks.allSatisfy { task in
            (0..<tasks.count).contains(task.id) && (1...4).contains(task.duration) && (0...task.duration).contains(task.remaining)
            && (0..<workers).contains(task.lane) && task.prerequisites.allSatisfy { $0 != task.id && (0..<tasks.count).contains($0) }
        } && trials.count <= 10 && trials.allSatisfy { (1...40).contains($0.ticks) } && activeTasks.allSatisfy { (0..<tasks.count).contains($0) }
    }
}
extension ParallelPixelModel {
    public var isValid: Bool {
        (1...5).contains(stage) && (0...64).contains(tick) && (0...count).contains(processed) && pixels.count == count
        && pixels.allSatisfy { (0...3).contains($0) } && (0...2).contains(remainingSetup) && (0...(stage == 5 ? 1 : 0)).contains(pass)
        && ["準備","計算","読み戻し","完成"].contains(phase) && trials.count <= 10
        && trials.allSatisfy { (1...64).contains($0.ticks) && $0.values.count == count && $0.values.allSatisfy { (0...3).contains($0) } }
    }
}
extension ParallelDisplayModel {
    public var isValid: Bool {
        guard (1...5).contains(stage), [15,30,60,120].contains(requestedFPS), [30,60,120].contains(hz), (0...120).contains(quantum),
              generated.count <= 120, displayed.count <= 120, windowStart >= 0, windowStart <= max(0,displayed.count-6) else { return false }
        return generated.allSatisfy { (0..<120).contains($0.quantum) && (0..<120).contains($0.frameID) && $0.quantum == $0.sourceQuantum }
            && displayed.allSatisfy { (0..<120).contains($0.quantum) && (0..<generated.count).contains($0.frameID) && (0...$0.quantum).contains($0.sourceQuantum) }
            && trials.count <= 10 && trials.allSatisfy { $0.values.count == 4 && $0.ticks == 120 }
    }
}
extension ParallelPacketModel {
    public var isValid: Bool {
        guard (1...5).contains(stage), [1,2,4].contains(bandwidth), [1,3].contains(latency), (0...64).contains(tick), packets.count == count,
              packets.map(\.id) == Array(1...count), trials.count <= 10 else { return false }
        return packets.allSatisfy { p in
            (0...2).contains(p.attempts) && (p.sentAt.map { (0...tick).contains($0) } ?? true)
            && (p.arrival.map { (1...128).contains($0) } ?? true) && (p.retryAt.map { (1...128).contains($0) } ?? true)
            && (!p.delivered || (p.arrival.map { $0 <= tick } ?? false))
        } && trials.allSatisfy { $0.values.count == 5 && (1...64).contains($0.ticks) }
    }
}
extension ParallelBoardModel {
    public var isValid: Bool {
        guard (1...5).contains(stage), [1,2].contains(capacity), (0...totalSteps).contains(tick), deliveredUnits.count <= 4,
              deliveredUnits == Array(unitOrder.prefix(deliveredUnits.count)), trials.count <= 10 else { return false }
        return (stage < 4 ? deliveredUnits.isEmpty : deliveredUnits.count == min(4,tick*capacity))
            && trials.allSatisfy { (1...6).contains($0.ticks) }
    }
}
extension ParallelConnectionModel {
    public var isValid: Bool {
        guard (1...5).contains(stage), connections.count == (stage == 4 ? 3 : 1), connections.map(\.id) == Array(0..<connections.count),
              connectedIDs.isSubset(of:Set(connections.map(\.id))), checks.count <= 20 else { return false }
        let expected = stage == 4 ? ["カメラ","ストレージ","画面"] : [stage == 1 ? "カメラ" : "画面"]
        return connections.map(\.device) == expected && connections.allSatisfy { availableCables.contains($0.cable) && availablePorts.contains($0.port) }
            && checks.allSatisfy { (-1...1).contains($0.status) } && Set(checks.map(\.label)).count == checks.count
            && observations.isSubset(of:["alpha-failed","gamma-failed","hub-overloaded","unknown"])
    }
}
