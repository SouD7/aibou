import XCTest
@testable import CircuitCore

final class CircuitExperienceTests: XCTestCase {
    private func assemble(_ model: inout CircuitExperienceModel, gate: GateKind = .and) {
        if !model.started { model.send(.begin) }
        model.send(.selectGate(gate))
        for link in CircuitLink.allCases where !model.circuit.links.contains(link) { model.send(.toggleLink(link)) }
    }
    private func observeAll(_ model: inout CircuitExperienceModel) {
        for row in InputPair.truthTable.reversed() { model.send(.setInputs(row)); model.send(.observe) }
    }
    func testIntroductionDistinguishesUnknownAndDoesNotPretendToFinishCircuit() {
        var model = CircuitExperienceModel(stage: 1)
        XCTAssertEqual(model.circuit.output, .unknown); XCTAssertFalse(model.isComplete)
        model.send(.observe)
        XCTAssertTrue(model.observations.isEmpty); XCTAssertFalse(model.isComplete)
        model.send(.begin); XCTAssertTrue(model.isComplete)
        model.send(.toggleInput(.a))
        XCTAssertEqual(model.circuit.output, .unknown)
        XCTAssertEqual(model.circuit.verification, .untested)
    }
    func testAssemblyRequiresPartAndThreeDistinctConnections() {
        var model = CircuitExperienceModel(stage: 2)
        model.send(.connect(.aOut, .bOut)); XCTAssertTrue(model.circuit.links.isEmpty)
        model.send(.connect(.aOut, .gateB)); XCTAssertTrue(model.circuit.links.isEmpty)
        model.send(.connect(.aOut, .gateA)); model.send(.connect(.gateB, .bOut)); model.send(.connect(.gateOut, .lampIn))
        XCTAssertEqual(model.circuit.links.count, 3); XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.circuit.output, .unknown)
        model.send(.selectGate(.and)); XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.circuit.output, .low); XCTAssertEqual(model.circuit.verification, .untested)
        model.send(.connect(.aOut, .gateA)); XCTAssertEqual(model.circuit.links.count, 3)
        model.send(.toggleLink(.output)); XCTAssertFalse(model.isComplete)
    }
    func testAllTwelveGateResultsUseExistingEvaluator() {
        let expected: [GateKind: [LogicSignal]] = [.and: [.low,.low,.low,.high], .or: [.low,.high,.high,.high], .xor: [.low,.high,.high,.low]]
        for gate in GateKind.allCases {
            var model = CircuitExperienceModel(stage: 3); model.send(.selectGate(gate))
            for (index, row) in InputPair.truthTable.enumerated() {
                model.send(.setInputs(row)); XCTAssertEqual(model.circuit.output, expected[gate]![index])
            }
        }
    }
    func testFourObservationsAcceptAnyOrderAndPreserveMismatchAsDiscovery() {
        var model = CircuitExperienceModel(stage: 3); model.send(.selectGate(.or))
        observeAll(&model)
        XCTAssertTrue(model.isComplete); XCTAssertEqual(model.observations.count, 4)
        XCTAssertEqual(model.circuit.verification, .failed)
        XCTAssertEqual(model.observations.filter { !$0.passed }.map(\.inputs), [InputPair(a: false,b: true),InputPair(a: true,b: false)])
    }
    func testInputAndCompanionKeepObservationsButEditsInvalidateThem() {
        var model = CircuitExperienceModel(stage: 3)
        observeAll(&model); let observed = model.observations
        let a = model.circuit.inputs.a, b = model.circuit.inputs.b
        model.send(.askCompanion)
        XCTAssertEqual(model.circuit.inputs.a, a); XCTAssertEqual(model.circuit.inputs.b, !b)
        XCTAssertEqual(model.observations, observed)
        model.send(.selectGate(.xor)); XCTAssertTrue(model.observations.isEmpty); XCTAssertFalse(model.isComplete)
        for _ in 0..<4 { model.send(.step) }
        XCTAssertEqual(model.observations.count, 4)
        model.send(.toggleLink(.inputA))
        XCTAssertTrue(model.observations.isEmpty); XCTAssertEqual(model.circuit.output, .unknown)
        model.send(.step); XCTAssertTrue(model.observations.isEmpty)
    }
    func testCounterexampleCheckpointMustBeRepairedAndReverified() {
        var model = CircuitExperienceModel(stage: 4)
        XCTAssertEqual(model.circuit.selectedGate, .or); XCTAssertFalse(model.isComplete)
        XCTAssertEqual(model.circuit.inputs, InputPair(a: false,b: true)); XCTAssertEqual(model.circuit.output, .high)
        model.send(.replayRow(InputPair(a: true,b: false)))
        XCTAssertEqual(model.circuit.inputs, InputPair(a: true,b: false))
        model.send(.selectGate(.and)); XCTAssertEqual(model.circuit.output, .low)
        XCTAssertFalse(model.isComplete); XCTAssertTrue(model.observations.isEmpty)
        for _ in 0..<3 { model.send(.step); XCTAssertFalse(model.isComplete) }
        model.send(.step); XCTAssertTrue(model.isComplete)
        XCTAssertEqual(model.circuit.verification, .passed)
    }
    func testInterruptedTestResumesAtNextConditionAndEditResetsCursor() {
        var model = CircuitExperienceModel(stage: 3)
        model.send(.step); model.send(.step)
        XCTAssertEqual(model.circuit.nextCheckIndex, 2)
        let paused = model
        model.send(.step); XCTAssertEqual(model.circuit.inputs, InputPair(a: true,b: false))
        model = paused; model.send(.step)
        XCTAssertEqual(model.circuit.inputs, InputPair(a: true,b: false))
        model.send(.selectGate(.or)); XCTAssertEqual(model.circuit.nextCheckIndex, 0)
        XCTAssertTrue(model.observations.isEmpty)
    }
    func testWrongOptionalPredictionAndSkippingBothPermitCompletion() {
        var answer = CircuitExperienceModel(stage: 5)
        XCTAssertFalse(answer.isComplete)
        answer.send(.predict(!GateKind.and.evaluate(answer.circuit.prediction.inputs)))
        XCTAssertEqual(answer.circuit.prediction.isCorrect, false); XCTAssertTrue(answer.isComplete)
        var skipped = CircuitExperienceModel(stage: 5)
        skipped.send(.skipPrediction); XCTAssertTrue(skipped.isComplete)
        skipped.send(.selectGate(.or)); XCTAssertFalse(skipped.isComplete); XCTAssertFalse(skipped.skippedPrediction)
        skipped.send(.skipPrediction); XCTAssertFalse(skipped.isComplete)
    }
    func testAllCheckpointsRoundTripThroughValidatedLegacyJournal() throws {
        for stage in 1...5 {
            var model = CircuitExperienceModel(stage: stage)
            if stage == 1 { model.send(.begin) }
            else if stage == 2 { assemble(&model) }
            else if stage == 3 { observeAll(&model) }
            else if stage == 4 { model.send(.selectGate(.and)); observeAll(&model) }
            else { model.send(.skipPrediction) }
            XCTAssertTrue(model.isComplete); XCTAssertTrue(model.isValid)
            let data = try JSONEncoder().encode(model)
            let decoded = try JSONDecoder().decode(CircuitExperienceModel.self, from: data)
            XCTAssertEqual(decoded, model); XCTAssertEqual(decoded.circuit, model.circuit)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNotNil(json["journal"]); XCTAssertNil(json["circuit"])
        }
    }
    func testMalformedJournalCannotInjectCompletedSnapshot() throws {
        let model = CircuitExperienceModel(stage: 1)
        let original = try JSONEncoder().encode(model)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var journal = try XCTUnwrap(json["journal"] as? [String: Any])
        journal["modelVersion"] = "invented"; json["journal"] = journal
        XCTAssertThrowsError(try JSONDecoder().decode(CircuitExperienceModel.self, from: JSONSerialization.data(withJSONObject: json)))
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json["skippedPrediction"] = true
        XCTAssertThrowsError(try JSONDecoder().decode(CircuitExperienceModel.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testArtifactPreviewIsIndependentAndDoesNotClaimDiskSave() throws {
        var model = CircuitExperienceModel(stage: 5); model.send(.skipPrediction)
        let saved = ExperienceArtifact(model: model)
        var record = ExperienceRecord(model: model); record.artifacts.append(saved)
        model.send(.selectGate(.xor)); record.model = model
        XCTAssertEqual(record.artifacts[0].model.circuit.selectedGate, .and)
        XCTAssertTrue(record.artifacts[0].model.isComplete); XCTAssertFalse(record.model.isComplete)
        XCTAssertTrue(record.isValid)
        XCTAssertFalse(saved.model.guide.contains("残したよ"))
        XCTAssertEqual(try JSONDecoder().decode(ExperienceRecord<CircuitExperienceModel>.self, from: JSONEncoder().encode(record)).artifacts[0].model, saved.model)
    }
}
