import XCTest
@testable import CircuitCore

final class MemoryExperienceTests:XCTestCase {
    private func roundTrip<M:ExperienceModel>(_ model:M,file:StaticString=#filePath,line:UInt=#line) throws {
        let decoded=try JSONDecoder().decode(M.self,from:JSONEncoder().encode(model))
        XCTAssertEqual(decoded,model,file:file,line:line);XCTAssertTrue(decoded.isValid,file:file,line:line)
    }
    func testMemoryDockEditSaveDoesNotFreeRAM() throws {
        var m=MemoryDockModel(stage:1);m.send(.open);m.send(.edit)
        XCTAssertEqual(m.selected?.workVersion,2);XCTAssertEqual(m.selected?.savedVersion,1);XCTAssertEqual(m.usedRAM,3)
        m.send(.observe);m.send(.save);XCTAssertTrue(m.isComplete);XCTAssertEqual(m.usedRAM,3)
        try roundTrip(m)
    }
    func testMemoryDockCloseFreesSpaceAndPreservesSavedPhoto() {
        var m=MemoryDockModel(stage:2);m.send(.save);XCTAssertEqual(m.usedRAM,8)
        m.send(.select("drawing"));m.send(.open);XCTAssertEqual(m.usedRAM,8)
        m.send(.select("photo"));m.send(.close(confirm:false));XCTAssertEqual(m.usedRAM,5);XCTAssertEqual(m.selected?.savedVersion,2)
        m.send(.select("drawing"));m.send(.open);XCTAssertEqual(m.usedRAM,7);XCTAssertTrue(m.isComplete)
    }
    func testMemoryDockPowerCycleKeepsSavedVersion() throws {
        var m=MemoryDockModel(stage:3);m.send(.save);m.send(.power(confirm:false));XCTAssertTrue(m.powered);XCTAssertNotNil(m.pendingConfirmation)
        m.send(.power(confirm:true));XCTAssertFalse(m.powered);XCTAssertEqual(m.usedRAM,0)
        try roundTrip(m);m.send(.power(confirm:false));m.send(.open);XCTAssertEqual(m.selected?.workVersion,3);XCTAssertTrue(m.isComplete)
        var unsaved=MemoryDockModel(stage:3);unsaved.send(.power(confirm:true));unsaved.send(.power(confirm:false));unsaved.send(.open)
        XCTAssertEqual(unsaved.selected?.workVersion,2);XCTAssertFalse(unsaved.isComplete)
    }
    func testMemoryDockCapacityComparisons() {
        var m=MemoryDockModel(stage:4);m.send(.expandStorage);m.send(.open);XCTAssertEqual(m.usedRAM,3)
        m.send(.expandRAM);m.send(.open);XCTAssertEqual(m.usedRAM,6);XCTAssertTrue(m.isComplete)
        var s=MemoryDockModel(stage:5);s.send(.expandRAM);s.send(.save);XCTAssertNil(s.selected?.savedVersion)
        s.send(.expandStorage);s.send(.save);s.send(.power(confirm:true));s.send(.power(confirm:false));s.send(.open)
        XCTAssertTrue(s.isComplete);XCTAssertEqual(s.usedStorage,9)
    }
    private func deliver(_ model:inout MemoryCacheModel) {
        for _ in 0..<100 {
            if model.finished { break }
            if let pending=model.pending {
                // Keep A for the next A request; replace the other item if possible.
                let old=pending == "C" ? (model.cache.first { $0 != "A" } ?? model.cache.first) : model.cache.first
                model.send(.replace(old))
            } else { model.send(.step) }
        }
    }
    func testCacheFirstAccessAndRepeat() throws {
        var m=MemoryCacheModel(stage:1);m.send(.step);XCTAssertEqual(m.remaining,3);XCTAssertEqual(m.index,0)
        try roundTrip(m);deliver(&m);XCTAssertEqual(m.ticks,5);XCTAssertEqual(m.hits,1);XCTAssertTrue(m.isComplete)
    }
    func testCacheTwoSlotsComparedWithOne() {
        var m=MemoryCacheModel(stage:2);deliver(&m);XCTAssertEqual(m.ticks,16);XCTAssertFalse(m.isComplete)
        m.send(.configure(2));deliver(&m);XCTAssertEqual(m.ticks,10);XCTAssertTrue(m.isComplete)
    }
    func testCacheReplacementChoiceAndOrderComparison() {
        var m=MemoryCacheModel(stage:3);deliver(&m);XCTAssertEqual(m.ticks,18);XCTAssertTrue(m.isComplete)
        var c=MemoryCacheModel(stage:4);deliver(&c);c.send(.order(1));deliver(&c)
        XCTAssertEqual(c.ticks,15);XCTAssertTrue(c.isComplete)
    }
    func testCacheDoesNotHelpUniqueRequests() {
        var m=MemoryCacheModel(stage:5);deliver(&m);XCTAssertEqual(m.ticks,24)
        m.send(.configure(3));deliver(&m);XCTAssertEqual(m.ticks,24);XCTAssertEqual(m.hits,0);XCTAssertTrue(m.isComplete)
    }
    func testCacheRejectsUnknownReplacementAndPausesAtChoice() {
        var m=MemoryCacheModel(stage:2)
        for _ in 0..<8 { m.send(.step) };XCTAssertEqual(m.pending,"B")
        let ticks=m.ticks;m.send(.step);m.send(.replace("X"));XCTAssertEqual(m.ticks,ticks);XCTAssertEqual(m.pending,"B");XCTAssertEqual(m.cache,["A"])
    }
    func testRescueFullRAMStillReadsWithoutWaiting() {
        var m=MemoryRescueModel(stage:1);for _ in 0..<4 { m.send(.step) }
        XCTAssertEqual(m.usedRAM,6);XCTAssertEqual(m.ticks,4);XCTAssertTrue(m.isComplete)
    }
    func testRescueCompressionAndSwapCosts() throws {
        var m=MemoryRescueModel(stage:2);m.send(.compress);XCTAssertEqual(m.usedRAM,4);XCTAssertEqual(m.cpuTicks,2)
        m.send(.admit);XCTAssertEqual(m.usedRAM,6);try roundTrip(m)
        for _ in 0..<4 { m.send(.step) };XCTAssertEqual(m.ticks,6)
        m.send(.restart);m.send(.evict);m.send(.admit);for _ in 0..<4 { m.send(.step) }
        XCTAssertEqual(m.ticks,7);XCTAssertTrue(m.isComplete)
    }
    func testRescueExpansionNeedsSpaceAndRetainsIdentity() {
        var m=MemoryRescueModel(stage:3);m.send(.step);m.send(.step)
        XCTAssertEqual(m.index,1);XCTAssertEqual(m.ticks,1);XCTAssertTrue(m.data.first { $0.id=="B" }!.compressed)
        m.send(.close);m.send(.step);XCTAssertEqual(m.ticks,4);XCTAssertFalse(m.data.first { $0.id=="B" }!.compressed);XCTAssertTrue(m.isComplete)
    }
    func testRescueRepeatedSwapComparedWithEnoughRAM() {
        var m=MemoryRescueModel(stage:4)
        m.send(.step)
        for id in ["A","B","A"] { m.send(.select(id));m.send(.evict);m.send(.step) }
        XCTAssertEqual(m.ticks,22)
        m.send(.capacity(6));for _ in 0..<4 { m.send(.step) }
        XCTAssertEqual(m.ticks,7);XCTAssertTrue(m.isComplete)
    }
    func testRescueSwapIsNotPersistentSave() {
        var m=MemoryRescueModel(stage:5);m.send(.power)
        XCTAssertEqual(m.usedRAM,0);XCTAssertEqual(m.usedScratch,0);m.send(.power);m.send(.restore);XCTAssertTrue(m.isComplete)
    }
    private func transfer(_ model:inout MemoryStorageModel) { for _ in 0..<40 { if model.finished { break };model.send(.step) } }
    func testStorageCapacityAndReadOnlyOriginals() throws {
        var m=MemoryStorageModel(stage:1);m.send(.rate(8));m.send(.step);XCTAssertEqual(m.elapsed,0);XCTAssertEqual(m.usedMB,8)
        m.send(.capacity(16));transfer(&m);XCTAssertEqual(m.usedMB,16);XCTAssertTrue(m.isComplete)
        var read=MemoryStorageModel(stage:2);read.send(.step)
        XCTAssertEqual(read.phase,"transfer");XCTAssertTrue(read.guide.contains("いまは転送"))
        read.send(.step)
        XCTAssertEqual(read.phase,"ready");XCTAssertTrue(read.guide.contains("次の荷物は待機中"));XCTAssertFalse(read.guide.contains("いまは転送"))
        XCTAssertEqual(read.elapsed,16);XCTAssertEqual(read.delivered,4);XCTAssertEqual(read.usedMB,16);try roundTrip(read)
        transfer(&read);XCTAssertEqual(read.elapsed,64);read.send(.capacity(32));transfer(&read);XCTAssertEqual(read.elapsed,64);XCTAssertTrue(read.isComplete)
    }
    func testStorageRateAndRequestBatching() {
        var m=MemoryStorageModel(stage:3);transfer(&m);m.send(.rate(8));transfer(&m);XCTAssertEqual(m.elapsed,48);XCTAssertTrue(m.isComplete)
        var b=MemoryStorageModel(stage:4);transfer(&b);b.send(.bundle(true));transfer(&b);XCTAssertEqual(b.elapsed,40);XCTAssertTrue(b.isComplete)
    }
    func testStorageDifferentWorkloadsFavorDifferentChanges() {
        var m=MemoryStorageModel(stage:5)
        m.send(.rate(8));transfer(&m);XCTAssertEqual(m.elapsed,24)
        m.send(.latency(4));transfer(&m);XCTAssertEqual(m.elapsed,36)
        m.send(.scenario(1));m.send(.rate(8));transfer(&m);XCTAssertEqual(m.elapsed,72)
        m.send(.latency(4));transfer(&m);XCTAssertEqual(m.elapsed,48);XCTAssertTrue(m.isComplete)
    }
    private func execute(_ model:inout MemoryPCDayModel) { for _ in 0..<20 { if model.current==nil { break };model.send(.step) } }
    func testPCOpenEditDisplayAndObserve() throws {
        var first=MemoryPCDayModel(stage:1);first.send(.append(.open));first.send(.append(.display));execute(&first)
        XCTAssertEqual(first.ticks,3);XCTAssertTrue(first.isComplete)
        var m=MemoryPCDayModel(stage:2);for c in [MemoryPCCommand.open,.edit,.display] { m.send(.append(c)) };execute(&m)
        XCTAssertEqual(m.ticks,5);XCTAssertEqual(m.ram,2);XCTAssertEqual(m.display,2);XCTAssertEqual(m.storage["original"],1);XCTAssertFalse(m.isComplete)
        m.send(.observe);XCTAssertTrue(m.isComplete);try roundTrip(m)
    }
    func testPCSavingSurvivesRestart() {
        var m=MemoryPCDayModel(stage:3);execute(&m);XCTAssertEqual(m.storage["original"],2)
        m.send(.power);XCTAssertNil(m.ram);XCTAssertNil(m.display);m.send(.power)
        m.send(.append(.open));m.send(.append(.display));execute(&m);XCTAssertTrue(m.isComplete)
    }
    func testSavingOnlyAfterRestartDoesNotProveSavedDataSurvived() {
        var pc=MemoryPCDayModel(stage:3);pc.send(.power);pc.send(.power)
        for c in [MemoryPCCommand.open,.edit,.save,.display] { pc.send(.append(c)) };execute(&pc)
        XCTAssertEqual(pc.display,2);XCTAssertEqual(pc.storage["original"],2);XCTAssertFalse(pc.isComplete)
        pc.send(.power);pc.send(.power);pc.send(.append(.open));pc.send(.append(.display));execute(&pc);XCTAssertTrue(pc.isComplete)
        var dock=MemoryDockModel(stage:5);dock.send(.expandRAM);dock.send(.save)
        dock.send(.power(confirm:true));dock.send(.power(confirm:false));dock.send(.open);dock.send(.expandStorage);dock.send(.save)
        XCTAssertFalse(dock.isComplete)
        dock.send(.power(confirm:true));dock.send(.power(confirm:false));dock.send(.open);XCTAssertTrue(dock.isComplete)
    }
    func testPCOrderFailureAndSeparateSave() {
        var m=MemoryPCDayModel(stage:4);m.send(.step);XCTAssertEqual(m.ticks,0);XCTAssertTrue(m.sawInvalidOrder)
        m.send(.move(1,-1));execute(&m);XCTAssertTrue(m.isComplete)
        var s=MemoryPCDayModel(stage:5);for c in [MemoryPCCommand.open,.edit,.display,.saveAs] { s.send(.append(c)) };execute(&s)
        XCTAssertEqual(s.storage,["original":1,"edited":2]);XCTAssertTrue(s.isComplete)
    }
    private func voyage(_ model:inout MemoryBatteryModel) { for _ in 0..<6 { model.send(.step) } }
    func testBatteryUnitsAndSameStartingEnergy() throws {
        var m=MemoryBatteryModel(stage:1);voyage(&m);XCTAssertEqual(m.energy,18*6);XCTAssertTrue(m.isComplete)
        var c=MemoryBatteryModel(stage:2);voyage(&c);c.send(.all(.fast));voyage(&c);XCTAssertEqual(c.energy,0);XCTAssertEqual(c.work,12);XCTAssertTrue(c.isComplete);try roundTrip(c)
    }
    func testBatteryCanDischargeWhilePluggedIn() {
        var m=MemoryBatteryModel(stage:3);m.send(.step)
        XCTAssertEqual(m.energy,28*6);XCTAssertEqual(m.lastDelta,-2*6);XCTAssertEqual(m.work,2)
        for _ in 0..<5 { m.send(.step) };XCTAssertEqual(m.energy,18*6);XCTAssertTrue(m.isComplete)
    }
    func testBatteryScheduleWithNoClippingHasSameFinalEnergy() {
        var a=MemoryBatteryModel(stage:4);for i in 0..<3 { a.send(.mode(i,.fast)) };voyage(&a)
        XCTAssertEqual(a.energy,17*6);XCTAssertTrue(a.isComplete)
        var b=MemoryBatteryModel(stage:4);for i in 3..<6 { b.send(.mode(i,.fast)) };voyage(&b)
        XCTAssertEqual(b.energy,a.energy);XCTAssertNotEqual(b.levels,a.levels)
    }
    func testBatteryFullChargeMakesOrderMatter() {
        var m=MemoryBatteryModel(stage:5);for i in 0..<3 { m.send(.mode(i,.fast)) };voyage(&m)
        XCTAssertEqual(m.energy,54*6);XCTAssertGreaterThan(m.spilled,0)
        m.send(.restart);for i in 0..<6 { m.send(.mode(i,i<3 ? .standard:.fast)) };voyage(&m)
        XCTAssertEqual(m.energy,45*6);XCTAssertTrue(m.isComplete)
    }
    func testEveryInitialStageIsValidAndCodable() throws {
        for n in 1...5 { try roundTrip(MemoryDockModel(stage:n));try roundTrip(MemoryCacheModel(stage:n));try roundTrip(MemoryRescueModel(stage:n));try roundTrip(MemoryStorageModel(stage:n));try roundTrip(MemoryPCDayModel(stage:n));try roundTrip(MemoryBatteryModel(stage:n)) }
    }
    func testCorruptSavedQuantitiesAndExecutionPositionsAreRejected() throws {
        func changed<M: ExperienceModel>(_ model: M, key: String, value: Int) throws -> M {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(model)) as? [String: Any])
            object[key] = value
            return try JSONDecoder().decode(M.self, from: JSONSerialization.data(withJSONObject: object))
        }
        XCTAssertFalse(try changed(MemoryDockModel(stage:1), key:"ramCapacity", value:0).isValid)
        XCTAssertFalse(try changed(MemoryCacheModel(stage:1), key:"capacity", value:9).isValid)
        XCTAssertFalse(try changed(MemoryRescueModel(stage:1), key:"ramCapacity", value:0).isValid)
        XCTAssertFalse(try changed(MemoryStorageModel(stage:1), key:"rate", value:0).isValid)
        XCTAssertFalse(try changed(MemoryPCDayModel(stage:1), key:"pc", value:99).isValid)
        XCTAssertFalse(try changed(MemoryBatteryModel(stage:1), key:"energy", value:-1).isValid)
    }
}
