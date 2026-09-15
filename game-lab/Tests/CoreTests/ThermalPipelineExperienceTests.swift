import XCTest
@testable import CircuitCore

final class ThermalPipelineExperienceTests: XCTestCase {
    private func run(_ model: inout CoolingModel) { while model.canStep { model.send(.step) } }
    private func run(_ model: inout BottleneckModel) { while model.canStep { model.send(.step) } }
    func testHeatAccumulationAndDelayedProtection() {
        var first = CoolingModel(stage: 1); run(&first)
        XCTAssertEqual(first.work, 4); XCTAssertEqual(first.heat, 0); XCTAssertFalse(first.isComplete)
        first.send(.fast(true)); run(&first)
        XCTAssertEqual(first.work, 8); XCTAssertEqual(first.heat, 8); XCTAssertTrue(first.isComplete)
        var longer = CoolingModel(stage: 2)
        for _ in 0..<8 { longer.send(.step) }
        XCTAssertEqual(longer.heat, 16); XCTAssertFalse(longer.restricted)
        longer.send(.step); XCTAssertTrue(longer.restricted); XCTAssertEqual(longer.work, 17)
        run(&longer); XCTAssertEqual(longer.work, 20); XCTAssertEqual(longer.heat, 12); XCTAssertFalse(longer.isComplete)
        longer.send(.cooler(5)); run(&longer)
        XCTAssertEqual(longer.work, 24); XCTAssertEqual(longer.heat, 0); XCTAssertTrue(longer.isComplete)
    }
    func testCoolingQuietAndWarmConditions() {
        var quiet = CoolingModel(stage: 3); run(&quiet)
        XCTAssertEqual(quiet.work, 32); XCTAssertEqual(quiet.noise, 48); XCTAssertFalse(quiet.isComplete)
        quiet.send(.cooler(3)); run(&quiet)
        XCTAssertEqual(quiet.work, 26); XCTAssertEqual(quiet.noise, 16); XCTAssertTrue(quiet.isComplete)
        var warm = CoolingModel(stage: 4); run(&warm)
        XCTAssertEqual(warm.work, 26); XCTAssertFalse(warm.isComplete)
        warm.send(.warm(false)); run(&warm)
        XCTAssertEqual(warm.work, 32); XCTAssertTrue(warm.isComplete)
    }
    func testShortBurstDoesNotGuaranteeSustainedPerformance() {
        var m = CoolingModel(stage: 5); run(&m)
        XCTAssertEqual(m.work, 8); XCTAssertFalse(m.isComplete)
        m.send(.length(12)); run(&m)
        XCTAssertEqual(m.work, 20); XCTAssertFalse(m.isComplete)
        m.send(.cooler(5)); run(&m)
        XCTAssertEqual(m.work, 24); XCTAssertTrue(m.isComplete)
        XCTAssertEqual(m.runs.count, 3)
    }
    func testPipelineSimultaneousStagesConserveJobs() {
        var m = BottleneckModel(stage: 1)
        for _ in 0..<3 { m.send(.step); XCTAssertEqual(m.unread+m.q1+m.q2+m.done, 6); XCTAssertTrue(m.isValid) }
        XCTAssertEqual(m.q1, 4); XCTAssertEqual(m.q2, 1); XCTAssertEqual(m.done, 1)
        run(&m); XCTAssertEqual(m.tick, 8); XCTAssertFalse(m.isComplete)
        m.send(.inspect(2)); XCTAssertTrue(m.isComplete)
    }
    func testChangingOnlyBottleneckHelps() {
        for (upgrade, expected) in [("read",8),("cpu",5),("write",8)] {
            var m = BottleneckModel(stage: 2); m.send(.upgrade(upgrade)); run(&m)
            XCTAssertEqual(m.tick, expected); XCTAssertEqual(m.isComplete, expected == 5)
        }
    }
    func testRAMCapacityAndReadRateAreDistinctBottlenecks() {
        var ram = BottleneckModel(stage: 3); run(&ram); XCTAssertEqual(ram.tick,7)
        ram.send(.upgrade("cpu")); run(&ram); XCTAssertEqual(ram.tick,7); XCTAssertFalse(ram.isComplete)
        ram.send(.upgrade("ram")); run(&ram); XCTAssertEqual(ram.tick,5); XCTAssertTrue(ram.isComplete)
        var read = BottleneckModel(stage: 4); read.send(.upgrade("cpu")); run(&read)
        XCTAssertEqual(read.tick,8); XCTAssertFalse(read.isComplete)
        read.send(.upgrade("read")); run(&read); XCTAssertEqual(read.tick,5); XCTAssertTrue(read.isComplete)
    }
    func testTiedBottlenecksRequireThreeControlledComparisons() {
        for order in [["cpu","write"],["write","cpu"]] {
            var m = BottleneckModel(stage:5)
            m.send(.upgrade(order[0])); XCTAssertEqual(m.config, BottleneckModel.baseline(5))
            run(&m); XCTAssertEqual(m.tick,8)
            m.send(.upgrade(order[0])); run(&m); XCTAssertEqual(m.tick,8); XCTAssertFalse(m.isComplete)
            m.send(.upgrade(order[1])); run(&m); XCTAssertEqual(m.tick,5); XCTAssertTrue(m.isComplete)
            XCTAssertEqual(m.runs.count,3)
        }
    }
    func testModelAndArtifactRoundTripKeepsSnapshotsIndependent() throws {
        var model = BottleneckModel(stage:2); model.send(.upgrade("cpu")); run(&model)
        var record = ExperienceRecord(model:model)
        record.artifacts = [ExperienceArtifact(model:model)]; record.completedStages = [2]
        record.model.send(.retry)
        XCTAssertTrue(record.artifacts[0].model.isComplete); XCTAssertFalse(record.model.isComplete)
        let read = try JSONDecoder().decode(ExperienceRecord<BottleneckModel>.self, from: JSONEncoder().encode(record))
        XCTAssertTrue(read.isValid); XCTAssertEqual(read.model,record.model); XCTAssertEqual(read.artifacts,record.artifacts)
        var cool = CoolingModel(stage:3); cool.send(.cooler(3)); run(&cool)
        XCTAssertEqual(try JSONDecoder().decode(CoolingModel.self,from:JSONEncoder().encode(cool)),cool)
    }
    func testInvalidControlsDoNotAdvanceOrChangeConditions() {
        var m = CoolingModel(stage:1); let initial = m
        m.send(.cooler(999)); m.send(.length(16)); m.send(.warm(true)); m.send(.inspect(-1)); XCTAssertEqual(m,initial)
        var pipeline = BottleneckModel(stage:2); let config = pipeline.config
        pipeline.send(.upgrade("not-a-device")); pipeline.send(.inspect(999)); XCTAssertEqual(pipeline.config,config); XCTAssertEqual(pipeline.tick,0)
        run(&pipeline); let ended = pipeline; pipeline.send(.step); XCTAssertEqual(pipeline,ended)
    }
}
