import XCTest
@testable import CircuitCore

final class ParallelExperienceTests: XCTestCase {
    private func factoryRun(_ m: inout ParallelFactoryModel) { for _ in 0..<40 { if m.runFinished { break }; m.send(.step) } }
    private func pixelRun(_ m: inout ParallelPixelModel) { for _ in 0..<64 { if m.runFinished { break }; m.send(.step) } }
    private func displayRun(_ m: inout ParallelDisplayModel) { for _ in 0..<120 { if m.runFinished { break }; m.send(.step) } }
    private func packetRun(_ m: inout ParallelPacketModel) { for _ in 0..<64 { if m.runFinished || m.stalled { break }; m.send(.step) } }
    private func boardRun(_ m: inout ParallelBoardModel) { for _ in 0..<8 { if m.runFinished { break }; m.send(.step) } }

    func testParallelIndependentAndDependentSchedules() {
        var independent = ParallelFactoryModel(stage:1); factoryRun(&independent)
        XCTAssertEqual(independent.tick,8); XCTAssertFalse(independent.isComplete)
        independent.send(.workers(2)); independent.send(.assign(1,1)); independent.send(.assign(3,1)); factoryRun(&independent)
        XCTAssertEqual(independent.tick,4); XCTAssertTrue(independent.isComplete)
        var m = ParallelFactoryModel(stage:2); factoryRun(&m); XCTAssertEqual(m.tick,12)
        m.send(.workers(2)); m.send(.assign(2,1)); m.send(.assign(4,1)); m.send(.inspect(5))
        for _ in 0..<4 { m.send(.step) }
        XCTAssertEqual(m.completedCount,3); XCTAssertEqual(m.tasks[5].remaining,2)
        factoryRun(&m); XCTAssertEqual(m.tick,8); XCTAssertTrue(m.isComplete)
        m.send(.workers(4)); m.send(.assign(2,1));m.send(.assign(3,2));m.send(.assign(4,3));factoryRun(&m)
        XCTAssertEqual(m.tick,6)
    }
    func testParallelChainOverheadAndChangedPreparation() {
        var chain = ParallelFactoryModel(stage:3); factoryRun(&chain)
        chain.send(.workers(4)); for id in 1..<4 { chain.send(.assign(id,id)) }; factoryRun(&chain)
        XCTAssertEqual(chain.tick,8); XCTAssertTrue(chain.isComplete)
        var overhead = ParallelFactoryModel(stage:4); factoryRun(&overhead)
        overhead.send(.workers(2)); overhead.send(.assign(2,1)); factoryRun(&overhead)
        XCTAssertEqual(overhead.tick,4); XCTAssertTrue(overhead.isComplete)
        var changed = ParallelFactoryModel(stage:5); changed.send(.assign(2,1));changed.send(.assign(4,1));factoryRun(&changed)
        XCTAssertEqual(changed.tick,10); XCTAssertTrue(changed.isComplete)
    }
    func testFactoryEditsResetOnlyCurrentRunAndDependenciesAreNotSameTick() {
        var m = ParallelFactoryModel(stage:2); m.send(.step); m.send(.step)
        XCTAssertEqual(m.tasks[0].remaining,0); XCTAssertEqual(m.tasks[1].remaining,2)
        m.send(.step); XCTAssertEqual(m.tasks[1].remaining,1)
        m.send(.assign(2,0)); XCTAssertEqual(m.tick,0); XCTAssertEqual(m.completedCount,0)
        factoryRun(&m); m.send(.reset); XCTAssertEqual(m.trials.first?.ticks,12)
        let original = m; m.send(.assign(999,0)); XCTAssertEqual(m,original)
    }
    func testPixelAllWorkloadsIncludePreparationAndReadback() {
        for (stage,cpu,gpu) in [(1,4,4),(2,16,7),(3,2,4),(4,16,19)] {
            var m = ParallelPixelModel(stage:stage); pixelRun(&m); let output = m.pixels
            XCTAssertEqual(m.tick,cpu); m.send(.device(true)); pixelRun(&m)
            XCTAssertEqual(m.tick,gpu); XCTAssertEqual(m.pixels,output); XCTAssertTrue(m.isComplete)
        }
        var m = ParallelPixelModel(stage:2); m.send(.device(true))
        for _ in 0..<4 { m.send(.step) }; XCTAssertEqual(m.processed,8); XCTAssertEqual(m.phase,"計算")
        m.send(.step);m.send(.step);XCTAssertEqual(m.processed,16);XCTAssertFalse(m.runFinished)
        m.send(.step);XCTAssertTrue(m.runFinished)
    }
    func testPixelResidentBatchSavesOnlyTransfers() {
        var m = ParallelPixelModel(stage:5); pixelRun(&m); XCTAssertEqual(m.tick,14); let output = m.pixels
        m.send(.resident(true)); pixelRun(&m); XCTAssertEqual(m.tick,11); XCTAssertEqual(m.pixels,output); XCTAssertTrue(m.isComplete)
    }
    func testFrameGenerationAndRefreshAreIndependentAndKeepDuplicatedIDs() {
        var m = ParallelDisplayModel(stage:2); displayRun(&m)
        XCTAssertEqual(m.generated.count,30);XCTAssertEqual(m.displayed.count,60);XCTAssertEqual(m.distinct,30)
        XCTAssertEqual(Array(m.displayed.prefix(6)).map(\.frameID),[0,0,1,1,2,2])
        XCTAssertEqual(Array(m.displayed.prefix(6)).map(\.sourceQuantum),[0,0,4,4,8,8])
        m.send(.hz(30));displayRun(&m);m.send(.hz(120));displayRun(&m);XCTAssertTrue(m.isComplete)
        var drop = ParallelDisplayModel(stage:3); displayRun(&drop)
        XCTAssertEqual(drop.generated.count,60);XCTAssertEqual(drop.distinct,30)
        XCTAssertEqual(Array(drop.displayed.prefix(3)).map(\.frameID),[0,2,4])
        drop.send(.hz(60));displayRun(&drop);XCTAssertTrue(drop.isComplete)
    }
    func testResolutionUsesAreaAndDoesNotChangeDisplayClock() {
        var basic = ParallelDisplayModel(stage:1);displayRun(&basic);basic.send(.fps(30));displayRun(&basic);XCTAssertTrue(basic.isComplete)
        var resolution = ParallelDisplayModel(stage:4);displayRun(&resolution);resolution.send(.resolution(true));displayRun(&resolution)
        XCTAssertEqual(resolution.fps,30);XCTAssertEqual(resolution.hz,120);XCTAssertEqual(resolution.pixelCount,9216);XCTAssertTrue(resolution.isComplete)
        var m = ParallelDisplayModel(stage:5);displayRun(&m);m.send(.resolution(true));displayRun(&m);m.send(.capacity(true));displayRun(&m)
        XCTAssertEqual(m.fps,60);XCTAssertEqual(m.hz,120);XCTAssertTrue(m.isComplete)
    }
    func testBandwidthChangesBulkCompletionButNotFirstPacket() {
        var basic = ParallelPacketModel(stage:1); basic.send(.step);XCTAssertEqual(basic.tick,0);basic.send(.connection(true));packetRun(&basic);XCTAssertEqual(basic.tick,5);XCTAssertTrue(basic.isComplete)
        var m = ParallelPacketModel(stage:2);packetRun(&m);XCTAssertEqual(m.tick,11);XCTAssertEqual(m.firstArrival,4)
        m.send(.bandwidth(4));for _ in 0..<4 { m.send(.step) }
        XCTAssertEqual(m.deliveredCount,4);XCTAssertFalse(m.runFinished);m.send(.step);XCTAssertEqual(m.tick,5);XCTAssertTrue(m.isComplete)
        var latency = ParallelPacketModel(stage:3);packetRun(&latency);latency.send(.latency(1));packetRun(&latency)
        XCTAssertEqual(latency.tick,3);XCTAssertEqual(latency.firstArrival,2);XCTAssertTrue(latency.isComplete)
    }
    func testSequentialRoundTripsAndDeterministicRetry() {
        var m = ParallelPacketModel(stage:4);packetRun(&m);XCTAssertEqual(m.tick,24)
        m.send(.bandwidth(4));packetRun(&m);XCTAssertEqual(m.tick,24)
        m.send(.latency(1));packetRun(&m);XCTAssertEqual(m.tick,12);XCTAssertTrue(m.isComplete)
        var retry = ParallelPacketModel(stage:5);packetRun(&retry);XCTAssertTrue(retry.stalled);XCTAssertEqual(retry.deliveredCount,3)
        retry.send(.retry(true));packetRun(&retry);XCTAssertEqual(retry.tick,7);XCTAssertEqual(retry.packets[1].attempts,2);XCTAssertEqual(retry.deliveredCount,4);XCTAssertTrue(retry.isComplete)
    }
    func testLogicalFunctionAndPackagingDoNotChangeTransferTime() {
        var wire = ParallelBoardModel(stage:1);boardRun(&wire);XCTAssertEqual(wire.tick,3);XCTAssertFalse(wire.isComplete)
        wire.send(.connect(true));boardRun(&wire);XCTAssertEqual(wire.tick,6);XCTAssertTrue(wire.isComplete)
        var package = ParallelBoardModel(stage:2);boardRun(&package);package.send(.soc(true));boardRun(&package);XCTAssertEqual(package.tick,6);XCTAssertTrue(package.isComplete)
        var memory = ParallelBoardModel(stage:3);boardRun(&memory);XCTAssertEqual(memory.tick,3);memory.send(.shared(true));boardRun(&memory);XCTAssertEqual(memory.tick,2);XCTAssertTrue(memory.isComplete)
    }
    func testSharedLaneCountsUnitsAndPhysicalPlacementDoesNotAddSpeed() {
        var m = ParallelBoardModel(stage:4);m.send(.step);m.send(.step)
        XCTAssertEqual(m.deliveredUnits,["CPU1","GPU1"]);XCTAssertEqual(m.waitingUnits,["CPU2","GPU2"])
        boardRun(&m);XCTAssertEqual(m.tick,4);m.send(.capacity(2));boardRun(&m);XCTAssertEqual(m.tick,2);XCTAssertTrue(m.isComplete)
        var positions = ParallelBoardModel(stage:5);boardRun(&positions);positions.send(.position(true));boardRun(&positions);XCTAssertEqual(positions.tick,4);XCTAssertTrue(positions.isComplete)
    }
    func testConnectorUsesFunctionCapacityAndPowerSeparately() {
        var camera = ParallelConnectionModel(stage:1);camera.send(.inspect);XCTAssertFalse(camera.isComplete);camera.send(.connect(0));camera.send(.inspect);XCTAssertTrue(camera.isComplete)
        var video = ParallelConnectionModel(stage:2);video.send(.inspect)
        XCTAssertEqual(video.checks.first(where:{$0.label == "映像"})?.status,0)
        XCTAssertEqual(video.checks.first(where:{$0.label == "給電"})?.status,1)
        video.send(.cable(0,"β"));XCTAssertTrue(video.checks.isEmpty);video.send(.inspect);XCTAssertTrue(video.isComplete)
        var power = ParallelConnectionModel(stage:3);power.send(.inspect)
        XCTAssertEqual(power.checks.first(where:{$0.label == "映像"})?.status,1)
        XCTAssertEqual(power.checks.first(where:{$0.label == "給電"})?.status,0)
        power.send(.cable(0,"β"));power.send(.inspect);XCTAssertTrue(power.isComplete)
    }
    func testHubSharedBudgetAndUnknownAreNotFalseOrZero() {
        var hub = ParallelConnectionModel(stage:4);hub.send(.inspect);XCTAssertFalse(hub.isComplete)
        XCTAssertEqual(hub.checks.first(where:{$0.label == "B1共有容量"})?.detail,"14 / 8")
        hub.send(.port(2,"B2"));hub.send(.inspect);XCTAssertTrue(hub.isComplete)
        hub.send(.port(0,"B1"));hub.send(.inspect);XCTAssertFalse(hub.isComplete)
        XCTAssertTrue(hub.checks.contains { $0.label == "B1物理接続" && $0.status == 0 })
        var unknown = ParallelConnectionModel(stage:5);unknown.send(.inspect);XCTAssertTrue(unknown.checks.contains { $0.status == -1 });XCTAssertFalse(unknown.isComplete)
        unknown.send(.reveal);unknown.send(.inspect);XCTAssertTrue(unknown.isComplete)
    }
    private func roundTrip<M: ExperienceModel>(_ model: M, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(model.isValid,file:file,line:line)
        let decoded = try JSONDecoder().decode(M.self,from:JSONEncoder().encode(model))
        XCTAssertEqual(decoded,model,file:file,line:line);XCTAssertTrue(decoded.isValid,file:file,line:line)
    }
    func testAllThirtyStageInitialAndMidrunSnapshotsRoundTrip() throws {
        for stage in 1...5 {
            var a = ParallelFactoryModel(stage:stage);a.send(.step);try roundTrip(a)
            var b = ParallelPixelModel(stage:stage);b.send(.step);try roundTrip(b)
            var c = ParallelDisplayModel(stage:stage);c.send(.step);try roundTrip(c)
            var d = ParallelPacketModel(stage:stage);d.send(.step);try roundTrip(d)
            var e = ParallelBoardModel(stage:stage);e.send(.step);try roundTrip(e)
            var f = ParallelConnectionModel(stage:stage);f.send(.inspect);try roundTrip(f)
        }
    }
    func testMalformedSavedStateRejectedBeforeUIUsesArrays() throws {
        let original = ParallelPixelModel(stage:2)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any]);json["pixels"] = [0]
        let broken = try JSONDecoder().decode(ParallelPixelModel.self,from:JSONSerialization.data(withJSONObject:json));XCTAssertFalse(broken.isValid)
        json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(ParallelDisplayModel(stage:2))) as? [String:Any]);json["hz"] = 0
        let invalidClock = try JSONDecoder().decode(ParallelDisplayModel.self,from:JSONSerialization.data(withJSONObject:json));XCTAssertFalse(invalidClock.isValid)
    }
}
