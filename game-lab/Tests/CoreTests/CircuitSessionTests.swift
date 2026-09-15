import XCTest
@testable import CircuitCore

final class CircuitSessionTests: XCTestCase {
    private func connected(mission: GateKind = .and, gate: GateKind? = nil, seed: UInt64 = 1) throws -> CircuitSession {
        var session = CircuitSession(seed: seed)
        if mission != .and { try session.apply(.selectMission(mission)) }
        try session.apply(.selectGate(gate ?? mission))
        for link in CircuitLink.allCases { try session.apply(.toggleLink(link)) }
        return session
    }

    func testAllTruthTablesMatchIndependentExpectations() {
        let expectations: [GateKind: [Bool]] = [
            .and: [false, false, false, true],
            .or: [false, true, true, true],
            .xor: [false, true, true, false]
        ]
        for gate in GateKind.allCases {
            XCTAssertEqual(InputPair.truthTable.map(gate.evaluate), expectations[gate])
        }
    }

    func testUnconnectedCircuitIsUnknownAndCannotPassEvenZeroRow() throws {
        var session = CircuitSession()
        XCTAssertEqual(session.state.output, .unknown)
        XCTAssertNil(session.state.output.bit)
        try session.apply(.verify)
        XCTAssertEqual(session.state.checks.count, 4)
        XCTAssertTrue(session.state.checks.allSatisfy { $0.actual == .unknown && !$0.passed })
        XCTAssertEqual(session.state.verification, .failed)
        XCTAssertTrue(session.state.completedMissions.isEmpty)
    }

    func testEveryLinkIsRequiredEvenForShortCircuitBooleanCase() throws {
        for missing in CircuitLink.allCases {
            var session = try connected()
            try session.apply(.toggleLink(missing))
            try session.apply(.setInputs(InputPair(a: false, b: false)))
            XCTAssertEqual(session.state.output, .unknown)
            try session.apply(.verify)
            XCTAssertEqual(session.state.verification, .failed)
        }
    }

    func testWiresWithoutGateAreUnknown() throws {
        var session = CircuitSession()
        for link in CircuitLink.allCases { try session.apply(.toggleLink(link)) }
        XCTAssertFalse(session.state.isConnected)
        XCTAssertEqual(session.state.output, .unknown)
    }

    func testConnectedOutputFollowsInputs() throws {
        var session = try connected()
        XCTAssertEqual(session.state.output, .low)
        try session.apply(.toggleInput(.a))
        XCTAssertEqual(session.state.output, .low)
        try session.apply(.toggleInput(.b))
        XCTAssertEqual(session.state.output, .high)
        try session.apply(.toggleInput(.a))
        XCTAssertEqual(session.state.output, .low)
    }

    func testEachCorrectGatePassesAndEachWrongGateFails() throws {
        for mission in GateKind.allCases {
            for gate in GateKind.allCases {
                var session = try connected(mission: mission, gate: gate)
                try session.apply(.verify)
                XCTAssertEqual(session.state.verification, mission == gate ? .passed : .failed)
                XCTAssertEqual(session.state.completedMissions.contains(mission), mission == gate)
            }
        }
    }

    func testStepIsCanonicalAndCannotPassBeforeFourDifferentRows() throws {
        var session = try connected(mission: .xor)
        for row in 0..<4 {
            try session.apply(.step)
            XCTAssertEqual(session.state.inputs, InputPair.truthTable[row])
            XCTAssertEqual(session.state.checks.count, row + 1)
            XCTAssertEqual(session.state.verification, row == 3 ? .passed : .untested)
        }
        XCTAssertEqual(session.state.nextCheckIndex, 0)
        try session.apply(.step)
        XCTAssertEqual(session.state.checks.count, 4)
        XCTAssertEqual(session.state.inputs, InputPair.truthTable[0])
    }

    func testGateEditInvalidatesEvidenceAndOptionalPrediction() throws {
        var session = try connected()
        try session.apply(.verify)
        try session.apply(.predict(session.state.mission.evaluate(session.state.prediction.inputs)))
        XCTAssertEqual(session.state.stage, .complete)
        try session.apply(.selectGate(.xor))
        XCTAssertEqual(session.state.verification, .untested)
        XCTAssertTrue(session.state.checks.isEmpty)
        XCTAssertEqual(session.state.nextCheckIndex, 0)
        XCTAssertNil(session.state.prediction.answer)
        XCTAssertTrue(session.state.completedMissions.isEmpty)
    }

    func testRemovingAndRestoringLinkDoesNotRestoreStalePass() throws {
        var session = try connected()
        try session.apply(.verify)
        try session.apply(.toggleLink(.output))
        XCTAssertEqual(session.state.output, .unknown)
        try session.apply(.toggleLink(.output))
        XCTAssertTrue(session.state.isConnected)
        XCTAssertEqual(session.state.verification, .untested)
        XCTAssertTrue(session.state.checks.isEmpty)
    }

    func testChangingInputsDoesNotInvalidateGateTruthTable() throws {
        var session = try connected()
        try session.apply(.verify)
        let checks = session.state.checks
        try session.apply(.toggleInput(.a))
        XCTAssertEqual(session.state.verification, .passed)
        XCTAssertEqual(session.state.checks, checks)
    }

    func testSelectingSameGateDoesNotInvalidateEvidence() throws {
        var session = try connected()
        try session.apply(.verify)
        try session.apply(.selectGate(.and))
        XCTAssertEqual(session.state.verification, .passed)
    }

    func testPredictionRequiresProvenCircuitAndRejectedActionIsAtomic() throws {
        var session = CircuitSession()
        let snapshot = session.state
        XCTAssertThrowsError(try session.apply(.predict(false))) {
            XCTAssertEqual($0 as? CircuitError, .predictionRequiresVerification)
        }
        XCTAssertEqual(session.state, snapshot)
        XCTAssertTrue(session.actions.isEmpty)
    }

    func testPredictionFeedbackIsDerivedAndAllowsRetry() throws {
        var session = try connected(mission: .xor, seed: 42)
        try session.apply(.verify)
        let expected = session.state.mission.evaluate(session.state.prediction.inputs)
        XCTAssertNil(session.state.predictionExplanation)
        try session.apply(.predict(!expected))
        XCTAssertEqual(session.state.prediction.isCorrect, false)
        XCTAssertNotNil(session.state.predictionExplanation)
        XCTAssertEqual(session.state.verification, .passed)
        try session.apply(.predict(expected))
        XCTAssertEqual(session.state.prediction.isCorrect, true)
    }

    func testNextMissionRequiresVerificationButPredictionIsOptional() throws {
        var session = try connected()
        XCTAssertThrowsError(try session.apply(.nextMission)) {
            XCTAssertEqual($0 as? CircuitError, .nextMissionRequiresVerification)
        }
        try session.apply(.verify)
        try session.apply(.nextMission)
        XCTAssertEqual(session.state.mission, .or)
        XCTAssertEqual(session.state.completedMissions, [.and])
        XCTAssertNil(session.state.selectedGate)
        XCTAssertEqual(session.state.verification, .untested)
    }

    func testWrongPredictionDoesNotBlockProgress() throws {
        var session = try connected()
        try session.apply(.verify)
        try session.apply(.predict(!session.state.mission.evaluate(session.state.prediction.inputs)))
        try session.apply(.nextMission)
        XCTAssertEqual(session.state.mission, .or)
        XCTAssertEqual(session.state.completedMissions, [.and])
    }

    func testAllMissionsCanBeCompletedAndFinalAdvanceIsAtomic() throws {
        var session = CircuitSession()
        for gate in GateKind.allCases {
            XCTAssertEqual(session.state.mission, gate)
            try session.apply(.selectGate(gate))
            for link in CircuitLink.allCases { try session.apply(.toggleLink(link)) }
            try session.apply(.verify)
            if gate != .xor { try session.apply(.nextMission) }
        }
        XCTAssertEqual(session.state.completedMissions, GateKind.allCases)
        let before = session.state
        let count = session.actions.count
        XCTAssertThrowsError(try session.apply(.nextMission)) {
            XCTAssertEqual($0 as? CircuitError, .noNextMission)
        }
        XCTAssertEqual(session.state, before)
        XCTAssertEqual(session.actions.count, count)
    }

    func testResetClearsProgressAndUsesRequestedSeed() throws {
        var session = try connected(mission: .or, seed: 4)
        try session.apply(.verify)
        try session.apply(.reset(seed: 99))
        XCTAssertEqual(session.state, CircuitSession(seed: 99).state)
        XCTAssertFalse(session.actions.isEmpty, "Full replay preserves actions before reset")
        XCTAssertEqual(session.state.tick, 0)
    }

    func testTickCountsAcceptedActionsAndResetsDeterministically() throws {
        var session = CircuitSession()
        try session.apply(.toggleInput(.a))
        XCTAssertEqual(session.state.tick, 1)
        try session.apply(.selectMission(.xor))
        XCTAssertEqual(session.state.tick, 2)
        try session.apply(.reset(seed: 1))
        XCTAssertEqual(session.state.tick, 0)
        try session.apply(.toggleInput(.b))
        XCTAssertEqual(session.state.tick, 1)
    }

    func testReplayRoundTripMatchesWholeSnapshotAndActionLog() throws {
        var session = try connected(mission: .or, gate: .and, seed: 42)
        try session.apply(.verify)
        try session.apply(.selectGate(.or))
        try session.apply(.step)
        try session.apply(.verify)
        try session.apply(.predict(false))
        try session.apply(.nextMission)
        try session.apply(.reset(seed: UInt64.max))
        try session.apply(.toggleInput(.b))
        let data = try JSONEncoder().encode(session.replayDocument())
        let replayed = try CircuitSession.replay(data: data)
        XCTAssertEqual(replayed.state, session.state)
        XCTAssertEqual(replayed.actions, session.actions)
        XCTAssertEqual(replayed.initialSeed, 42)
    }

    func testSnapshotEncodingIsStableAndCodableRoundTrips() throws {
        let session = try connected(mission: .xor)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(session.state)
        XCTAssertEqual(try JSONDecoder().decode(CircuitSnapshot.self, from: data), session.state)
        for _ in 0..<10 { XCTAssertEqual(try encoder.encode(session.state), data) }
        XCTAssertEqual(try encoder.encode(CircuitSession.replay(session.replayDocument()).state), data)
    }

    func testSameSeedHasSamePredictionAndUInt64ExtremesWork() {
        for seed: UInt64 in [0, 1, 42, UInt64.max] {
            XCTAssertEqual(CircuitSession(seed: seed).state, CircuitSession(seed: seed).state)
        }
        let questions = Set((0..<32).map { CircuitSession(seed: UInt64($0)).state.prediction.inputs })
        XCTAssertEqual(questions.count, 4)
    }

    func testDefaultAppSeedContrastsANDWithORAndXOR() throws {
        var session = CircuitSession(seed: 17)
        XCTAssertEqual(session.state.prediction.inputs, InputPair(a: true, b: false))
        XCTAssertFalse(session.state.mission.evaluate(session.state.prediction.inputs))
        try session.apply(.selectMission(.or))
        XCTAssertEqual(session.state.prediction.inputs, InputPair(a: true, b: true))
        XCTAssertTrue(session.state.mission.evaluate(session.state.prediction.inputs))
        try session.apply(.selectMission(.xor))
        XCTAssertEqual(session.state.prediction.inputs, InputPair(a: true, b: true))
        XCTAssertFalse(session.state.mission.evaluate(session.state.prediction.inputs))
        XCTAssertEqual(try CircuitSession.replay(session.replayDocument()).state, session.state)
        try session.apply(.reset(seed: 17))
        XCTAssertEqual(session.state, CircuitSession(seed: 17).state)
    }

    func testMissionPredictionRemainsDeterministicForEverySeedAndSharesORXORCondition() throws {
        for seed: UInt64 in [0, 1, 17, 42, UInt64.max] {
            var session = CircuitSession(seed: seed)
            let andInputs = session.state.prediction.inputs
            try session.apply(.selectMission(.or))
            let orInputs = session.state.prediction.inputs
            XCTAssertNotEqual(andInputs, orInputs)
            try session.apply(.selectMission(.xor))
            XCTAssertEqual(session.state.prediction.inputs, orInputs)
            XCTAssertEqual(try CircuitSession.replay(session.replayDocument()).state, session.state)
        }
    }

    func testReplayRejectsUnsupportedSchemaAndModel() throws {
        let original = try JSONEncoder().encode(CircuitSession().replayDocument())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        object["schemaVersion"] = 999
        XCTAssertThrowsError(try CircuitSession.replay(data: JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? CircuitError, .unsupportedSchema(999))
        }
        object["schemaVersion"] = CircuitReplay.schemaVersion
        object["modelVersion"] = "future"
        XCTAssertThrowsError(try CircuitSession.replay(data: JSONSerialization.data(withJSONObject: object))) {
            XCTAssertEqual($0 as? CircuitError, .unsupportedModel("future"))
        }
    }

    func testReplayRejectsMalformedMissingFieldsUnknownActionAndSnapshotImport() throws {
        let badInputs = [
            "not json", "{}",
            "{\"schemaVersion\":1,\"modelVersion\":\"\(CircuitReplay.modelVersion)\",\"initialSeed\":-1,\"actions\":[]}",
            "{\"schemaVersion\":1,\"modelVersion\":\"\(CircuitReplay.modelVersion)\",\"initialSeed\":1,\"actions\":[{\"skipMission\":{}}]}"
        ]
        for input in badInputs { XCTAssertThrowsError(try CircuitSession.replay(data: Data(input.utf8))) }
        XCTAssertThrowsError(try CircuitSession.replay(data: JSONEncoder().encode(CircuitSession().state)))
    }

    func testReplayRejectsImpossibleSequenceAndOversizedActionList() throws {
        let impossible = CircuitReplay(initialSeed: 1, actions: [.predict(true)])
        XCTAssertThrowsError(try CircuitSession.replay(impossible)) {
            XCTAssertEqual($0 as? CircuitError, .predictionRequiresVerification)
        }
        let oversized = CircuitReplay(initialSeed: 1, actions: Array(repeating: .step, count: 10_001))
        XCTAssertThrowsError(try CircuitSession.replay(oversized)) {
            XCTAssertEqual($0 as? CircuitError, .tooManyActions(10_001))
        }
    }
}
