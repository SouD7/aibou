import Foundation

/// Catalog representative states, reached through public actions without saved-state injection.
/// Initial stage scaffolds are the same ones presented to a player entering that lesson.
enum MemoryRepresentative {
    // M2: the photo has been saved, but all eight RAM slots remain occupied.
    static func dock() -> MemoryDockModel {
        var model = MemoryDockModel(stage: 2)
        model.send(.select("photo"))
        model.send(.save)
        precondition(model.isValid && model.usedRAM == 8 && model.ramCapacity == 8)
        precondition(model.selected?.workVersion == 2 && model.selected?.savedVersion == 2)
        precondition(model.documents.first { $0.id == "drawing" }?.workVersion == nil)
        return model
    }

    // C3: A (4 beats), B (4 beats), then cached A (1 beat). C is the next request.
    static func cache() -> MemoryCacheModel {
        var model = MemoryCacheModel(stage: 3)
        for _ in 0..<9 { model.send(.step) }
        precondition(model.isValid && model.ticks == 9 && model.index == 3)
        precondition(model.cache == ["A", "B"] && model.capacity == 2 && model.next == "C")
        precondition(model.requests == ["A", "B", "A", "C", "A", "B"] && model.remaining == 0)
        return model
    }

    // R2: compress B from three slots to one, then admit C; no requests read yet.
    static func rescue() -> MemoryRescueModel {
        var model = MemoryRescueModel(stage: 2)
        model.send(.select("B"))
        model.send(.compress)
        model.send(.admit)
        precondition(model.isValid && model.usedRAM == 6 && model.ramCapacity == 6)
        precondition(model.data.map(\.footprint) == [3, 1, 2] && model.data.allSatisfy { $0.location == "ram" })
        precondition(model.cpuTicks == 2 && model.ticks == 2 && model.ioTicks == 0 && model.index == 0)
        precondition(model.requests == ["A", "C", "A", "C"])
        return model
    }

    // S2: expanded capacity, unchanged bandwidth; first four-MB read completes at two seconds.
    static func storage() -> MemoryStorageModel {
        var model = MemoryStorageModel(stage: 2)
        model.send(.capacity(32))
        model.send(.step)
        model.send(.step)
        precondition(model.isValid && model.capacityMB == 32 && model.usedMB == 16)
        precondition(model.rate == 4 && model.latency == 8 && model.sizes == [4, 4, 4, 4])
        precondition(model.index == 1 && model.delivered == 4 && model.totalMB == 16 && model.elapsed == 16)
        return model
    }

    // P3 begins immediately after the demonstrated open/edit/display sequence (2+2+1 beats).
    // Recording that comparison keeps the seeded state and leaves Save as the next command.
    static func pcDay() -> MemoryPCDayModel {
        var model = MemoryPCDayModel(stage: 3)
        model.send(.observe)
        precondition(model.isValid && model.ram == 2 && model.display == 2)
        precondition(model.storage["original"] == 1 && model.ticks == 5 && model.current == .save)
        return model
    }

    // B3: ten minutes at 30 W, supplied with 18 W, consumes the missing 2 Wh from the battery.
    static func battery() -> MemoryBatteryModel {
        var model = MemoryBatteryModel(stage: 3)
        model.send(.step)
        precondition(model.isValid && model.index == 1 && model.energy == 168 && model.work == 2)
        precondition(model.current.mode == .fast && model.current.supply == 18 && model.lastDelta == -12)
        return model
    }
}
