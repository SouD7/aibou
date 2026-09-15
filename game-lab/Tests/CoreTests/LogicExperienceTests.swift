import XCTest
@testable import CircuitCore

final class LogicExperienceTests: XCTestCase {
    func instruction(_ stage: Int, _ program: [LogicInstructionModel.Instruction]) -> LogicInstructionModel {
        var model = LogicInstructionModel(stage: stage)
        program.forEach { model.send(.append($0)) }
        return model
    }
    func testInstructionFirstStageConsumesBeforeOutput() {
        var model = instruction(1,[.read,.output]); model.send(.step)
        XCTAssertEqual(model.accumulator,2); XCTAssertEqual(model.inputIndex,1); XCTAssertTrue(model.output.isEmpty); XCTAssertFalse(model.isComplete)
        model.send(.step); XCTAssertEqual(model.output,[2]); XCTAssertNil(model.accumulator); XCTAssertTrue(model.isComplete)
    }
    func testInstructionAllFiveSolutions() {
        let programs: [[LogicInstructionModel.Instruction]] = [[.read,.output],[.read,.addOne,.output],[.read,.store0,.read,.add0,.output],[.read,.ifZero4,.output,.stop],[.read,.addOne,.output,.jump1]]
        for (index,program) in programs.enumerated() {
            var model = instruction(index+1,program); model.send(.verify)
            XCTAssertTrue(model.isComplete,"stage \(index+1): \(model.results)"); XCTAssertTrue(model.isValid)
        }
    }
    func testInstructionRepresentativeReadStoreReadState() {
        var model = instruction(3,[.read,.store0,.read,.add0,.output])
        for _ in 0..<3 { model.send(.step) }
        XCTAssertEqual(model.accumulator,3); XCTAssertEqual(model.memory[0],2); XCTAssertEqual(model.pc,3); XCTAssertTrue(model.output.isEmpty)
        model.send(.step); XCTAssertEqual(model.accumulator,5); model.send(.step); XCTAssertEqual(model.output,[5])
    }
    func testInstructionMissingValueAndEditedSuccess() {
        var model = instruction(1,[.output]); model.send(.step)
        XCTAssertNotNil(model.fault); XCTAssertEqual(model.steps,0); XCTAssertEqual(model.inputIndex,0)
        model.send(.remove(0)); model.send(.append(.read)); model.send(.append(.output)); model.send(.verify)
        XCTAssertTrue(model.isComplete); model.send(.move(0,1)); XCTAssertFalse(model.isComplete); XCTAssertNil(model.fault)
    }
    func testInstructionMemoryZeroIsNotUnknownAndLoopBound() {
        var model = instruction(3,[.read,.add0]); model.send(.step); model.send(.step); XCTAssertNotNil(model.fault)
        var loop = instruction(5,[.jump1]); for _ in 0..<101 { loop.send(.step) }; XCTAssertNotNil(loop.fault); XCTAssertEqual(loop.steps,100); XCTAssertFalse(loop.isComplete)
    }
    func testInstructionBatchCheckDoesNotReplaceUserMachine() {
        var model = instruction(4,[.read,.ifZero4,.output,.stop]); model.send(.step)
        let accumulator = model.accumulator,pc=model.pc; model.send(.verify)
        XCTAssertEqual(model.accumulator,accumulator); XCTAssertEqual(model.pc,pc); XCTAssertEqual(model.results.count,3)
    }
    func testBitsOneAndEightStates() {
        var one=LogicBitArtModel(stage:1); one.send(.record); one.send(.toggle(0)); one.send(.record); XCTAssertTrue(one.isComplete)
        var eight=LogicBitArtModel(stage:2)
        for value in 0..<8 { eight.send(.chooseValue(value)); eight.send(.record) }
        XCTAssertTrue(eight.isComplete); eight.send(.record); XCTAssertEqual(eight.observedValues.count,8)
    }
    func testBitPaletteChangesMeaningWithoutBits() {
        var model=LogicBitArtModel(stage:3); let original=model.pixels
        XCTAssertEqual(model.binary,"101"); XCTAssertEqual(model.colors[6],5)
        model.send(.record); model.send(.switchMapping); XCTAssertEqual(model.pixels,original); XCTAssertEqual(model.value,5); XCTAssertEqual(model.colors[6],6)
        model.send(.record); XCTAssertTrue(model.isComplete); XCTAssertEqual(model.totalBits,48)
    }
    func testBitNineColorSolutionRequiresFourthBit() {
        var model=LogicBitArtModel(stage:4); model.send(.chooseValue(8)); XCTAssertEqual(model.value,0)
        model.send(.addBit); XCTAssertEqual(model.bits,4)
        for i in LogicBitArtModel.target.indices {
            model.send(.select(i)); model.send(.chooseValue(LogicBitArtModel.target[i])); model.send(.assignColor(LogicBitArtModel.target[i]))
        }
        XCTAssertTrue(model.isComplete); XCTAssertEqual(Set(model.colors).count,9)
        model.send(.removeBit); XCTAssertEqual(model.bits,4); XCTAssertTrue(model.isValid)
    }
    func testBitComparisonRetainsOriginal() {
        var model=LogicBitArtModel(stage:5); model.send(.chooseValue(6)); let original=model.pixels
        model.send(.beginComparison); model.send(.toggle(0)); model.send(.record); XCTAssertEqual(model.totalBits,16)
        model.send(.expandComparison); XCTAssertEqual(model.totalBits,48); model.send(.record)
        XCTAssertTrue(model.isComplete); XCTAssertEqual(model.originalPixels,original)
    }
    func testMemoryDirectAndHoldGoals() {
        var direct=LogicMemorySwitchModel(stage:1); direct.send(.record); direct.send(.toggle(0))
        XCTAssertTrue(direct.guide.contains("入力は1")); XCTAssertTrue(direct.guide.contains("出力も1")); XCTAssertFalse(direct.guide.contains("記憶Q"))
        direct.send(.record); XCTAssertTrue(direct.isComplete)
        var hold=LogicMemorySwitchModel(stage:2); hold.send(.toggle(0)); XCTAssertEqual(hold.stored,[0])
        hold.send(.write); let writtenGuide=hold.guide; hold.send(.toggle(0))
        XCTAssertNotEqual(hold.guide,writtenGuide); XCTAssertTrue(hold.guide.contains("入力は0")); XCTAssertTrue(hold.guide.contains("記憶Qは1のまま"))
        hold.send(.record); XCTAssertEqual(hold.input,[0]); XCTAssertEqual(hold.output,[1]); XCTAssertTrue(hold.isComplete)
    }
    func testMemoryRepresentativeAndOverwrite() {
        var model=LogicMemorySwitchModel(stage:3); XCTAssertEqual(model.input,[0]); XCTAssertEqual(model.stored,[1])
        model.send(.record); model.send(.write); XCTAssertEqual(model.stored,[0]); model.send(.record); XCTAssertTrue(model.isComplete)
    }
    func testMemoryFourBitAtomicWrite() {
        var model=LogicMemorySwitchModel(stage:4); model.send(.toggle(0)); model.send(.toggle(2)); model.send(.write)
        XCTAssertEqual(model.stored,[1,0,1,0]); for i in 0..<4 { model.send(.toggle(i)) }
        XCTAssertEqual(model.stored,[1,0,1,0]); XCTAssertTrue(model.guide.contains("入力は0101")); XCTAssertTrue(model.guide.contains("記憶Qは1010のまま"))
        model.send(.record); model.send(.write); XCTAssertEqual(model.stored,[0,1,0,1]); model.send(.record); XCTAssertTrue(model.isComplete)
    }
    func testMemoryCopyNeedsPowerCycleToDemonstrateSavedRestoration() {
        var model = LogicMemorySwitchModel(stage: 5)
        model.send(.power); model.send(.record); model.send(.power)
        model.send(.toggle(0)); model.send(.toggle(2)); model.send(.write); model.send(.saveCopy)
        model.send(.restoreCopy)
        XCTAssertFalse(model.isComplete)
        model.send(.power); model.send(.power); model.send(.restoreCopy)
        XCTAssertTrue(model.isComplete)
    }
    func testMemoryPowerLossIsUnknownAndExplicitCopyRestores() {
        var model=LogicMemorySwitchModel(stage:5); model.send(.power); model.send(.record)
        XCTAssertEqual(model.stored,[nil,nil,nil,nil]); model.send(.power); XCTAssertEqual(model.stored,[nil,nil,nil,nil])
        model.send(.toggle(0)); model.send(.toggle(2)); model.send(.write); model.send(.saveCopy)
        XCTAssertEqual(model.stored,[1,0,1,0]); model.send(.power); model.send(.power); XCTAssertEqual(model.output,[nil,nil,nil,nil])
        model.send(.restoreCopy); XCTAssertEqual(model.stored,[1,0,1,0]); XCTAssertTrue(model.isComplete)
    }
    func testTinyUnknownAndFullLogicSolutions() {
        for stage in 1...5 {
            var model=LogicTinySwitchModel(stage:stage); XCTAssertNil(model.output); model.send(.test); XCTAssertFalse(model.isComplete)
            for i in 0..<model.switchCount { model.send(.place(i)); model.send(.connect(i)) }
            if [3,5].contains(stage) { model.send(.changeLayout(.parallel)) }
            if stage == 4 { model.send(.invert(0)) }
            model.send(.test); XCTAssertTrue(model.isComplete,"stage \(stage)"); XCTAssertTrue(model.isValid)
        }
    }
    func testTinyParallelSinglePathAndRevision() {
        var model=LogicTinySwitchModel(stage:3)
        for i in 0..<2 { model.send(.place(i)); model.send(.connect(i)) }
        model.send(.changeLayout(.parallel)); model.send(.toggle(0)); XCTAssertEqual(model.output,1); XCTAssertFalse(model.isClosed(1))
        model.send(.test); XCTAssertTrue(model.isComplete)
        model.send(.changeLayout(.series)); XCTAssertTrue(model.observations.isEmpty); model.send(.test); XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.observations.filter { !$0.matches }.count,2)
    }
    func testDispatchPlacementDoesNotComputeAndFirstStage() {
        var model=LogicWorkDispatchModel(stage:1); model.send(.admit(0)); XCTAssertEqual(model.jobs[0].done,0); XCTAssertEqual(model.used,3)
        for _ in 0..<3 { model.send(.step) }; XCTAssertTrue(model.isComplete); XCTAssertEqual(model.used,0)
    }
    func testDispatchCapacityAndSecondStage() {
        var model=LogicWorkDispatchModel(stage:2); model.send(.admit(1)); model.send(.admit(0))
        XCTAssertEqual(model.used,2); XCTAssertEqual(model.jobs[0].status,.pending)
        model.send(.step); model.send(.step); model.send(.admit(0)); for _ in 0..<4 { model.send(.step) }
        XCTAssertTrue(model.isComplete); XCTAssertEqual(model.tick,6)
    }
    func dispatchRun(_ model: inout LogicWorkDispatchModel,_ sequence: [Int]) {
        model.send(.admit(0)); model.send(.admit(1))
        for i in sequence { model.send(.select(i)); model.send(.step) }
    }
    func testDispatchFairnessAndExactRepresentative() {
        var model=LogicWorkDispatchModel(stage:3); model.send(.admit(0)); model.send(.admit(1)); model.send(.select(0)); model.send(.step)
        XCTAssertEqual(model.used,5); XCTAssertEqual(model.jobs[0].done,1); XCTAssertEqual(model.jobs[1].done,0)
        for i in [1,0,1,0,0] { model.send(.select(i)); model.send(.step) }
        XCTAssertTrue(model.isComplete); XCTAssertEqual(model.jobs.map(\.firstService),[1,2]); XCTAssertEqual(model.jobs.map(\.completedAt),[6,4])
        var unfair=LogicWorkDispatchModel(stage:3); dispatchRun(&unfair,[0,0,0,0,1,1]); XCTAssertFalse(unfair.isComplete); XCTAssertTrue(unfair.allDone)
    }
    func testDispatchIOWaitStartsAfterTriggerAndOnlyOnce() {
        var model=LogicWorkDispatchModel(stage:4); model.send(.admit(0)); model.send(.admit(1)); model.send(.select(0)); model.send(.step)
        XCTAssertEqual(model.jobs[0].ioRemaining,2); model.send(.select(1)); model.send(.step); XCTAssertEqual(model.jobs[0].ioRemaining,1)
        model.send(.step); XCTAssertEqual(model.jobs[0].ioRemaining,0); XCTAssertEqual(model.jobs[0].status,.ready)
        model.send(.select(0)); model.send(.step); XCTAssertEqual(model.jobs[0].status,.completed); XCTAssertEqual(model.jobs[0].done,2)
        model.send(.select(1)); model.send(.step); XCTAssertTrue(model.isComplete); XCTAssertEqual(model.tick,5)
    }
    func testDispatchComparisonVariesOneFactor() {
        var model=LogicWorkDispatchModel(stage:5); dispatchRun(&model,[0,1,0,1,0,0]); model.send(.recordComparison)
        model.send(.capacity(8)); dispatchRun(&model,[0,1,0,1,0,0]); model.send(.recordComparison); XCTAssertFalse(model.isComplete)
        model.send(.capacity(6)); dispatchRun(&model,[0,0,0,0,1,1]); model.send(.recordComparison); XCTAssertTrue(model.isComplete)
    }
    func testDispatchPauseRetainsMemoryAndCloseResets() {
        var model=LogicWorkDispatchModel(stage:3); model.send(.admit(0)); model.send(.step); model.send(.pause(0)); XCTAssertEqual(model.used,3)
        model.send(.close(0)); XCTAssertEqual(model.used,0); XCTAssertEqual(model.jobs[0].done,0)
    }
    func testAllLogicModelsRoundTripAndArtifactIndependence() throws {
        func check<M: ExperienceModel>(_ original: M) throws {
            let data=try JSONEncoder().encode(original),decoded=try JSONDecoder().decode(M.self,from:data)
            XCTAssertEqual(decoded,original); XCTAssertTrue(decoded.isValid)
        }
        for stage in 1...5 { try check(LogicInstructionModel(stage:stage)); try check(LogicBitArtModel(stage:stage)); try check(LogicMemorySwitchModel(stage:stage)); try check(LogicTinySwitchModel(stage:stage)); try check(LogicWorkDispatchModel(stage:stage)) }
        var model=instruction(1,[.read,.output]); model.send(.verify); let artifact=ExperienceArtifact(model:model)
        model.send(.remove(0)); XCTAssertTrue(artifact.model.isComplete); XCTAssertFalse(model.isComplete)
    }
}
