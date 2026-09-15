import XCTest
@testable import CircuitCore

final class WorkshopSessionTests: XCTestCase {
    private func connected(_ gate: GateKind = .and, seed: UInt64 = 17) throws -> WorkshopSession {
        var session = WorkshopSession(seed: seed)
        try session.apply(.begin)
        try session.apply(.circuit(.selectGate(gate)))
        for link in CircuitLink.allCases { try session.apply(.circuit(.toggleLink(link))) }
        return session
    }

    private func encoded(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func editedDocument(_ session: WorkshopSession, key: String, value: Any) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded(session.replayDocument())) as? [String: Any])
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    private func assertSameWork(_ actual: WorkshopArtifact?, _ expected: WorkshopArtifact?,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try XCTUnwrap(actual, file: file, line: line)
        let expected = try XCTUnwrap(expected, file: file, line: line)
        // Journal compaction changes bookkeeping counters, never the saved experiment.
        XCTAssertEqual(actual.circuit.seed, expected.circuit.seed, file: file, line: line)
        XCTAssertEqual(actual.circuit.mission, expected.circuit.mission, file: file, line: line)
        XCTAssertEqual(actual.circuit.selectedGate, expected.circuit.selectedGate, file: file, line: line)
        XCTAssertEqual(actual.circuit.links, expected.circuit.links, file: file, line: line)
        XCTAssertEqual(actual.circuit.inputs, expected.circuit.inputs, file: file, line: line)
        XCTAssertEqual(actual.circuit.output, expected.circuit.output, file: file, line: line)
        XCTAssertEqual(actual.circuit.checks, expected.circuit.checks, file: file, line: line)
        XCTAssertEqual(actual.circuit.nextCheckIndex, expected.circuit.nextCheckIndex, file: file, line: line)
        XCTAssertEqual(actual.circuit.verification, expected.circuit.verification, file: file, line: line)
        XCTAssertEqual(actual.circuit.prediction, expected.circuit.prediction, file: file, line: line)
        XCTAssertEqual(actual.circuit.completedMissions, expected.circuit.completedMissions, file: file, line: line)
        XCTAssertEqual(actual.observations, expected.observations, file: file, line: line)
    }

    func testWelcomeRequiresExplicitStartAndRejectedActionsAreAtomic() throws {
        var session = WorkshopSession()
        let before = session.state
        XCTAssertEqual(before.phase, .welcome)
        XCTAssertFalse(before.hasStarted)
        XCTAssertFalse(before.canObserve)
        for action in [WorkshopAction.askCompanion, .observe, .hint, .finish, .circuit(.selectGate(.and))] {
            XCTAssertThrowsError(try session.apply(action)) { XCTAssertEqual($0 as? WorkshopError, .notStarted) }
            XCTAssertEqual(session.state, before)
            XCTAssertTrue(session.actions.isEmpty)
        }
        try session.apply(.begin)
        XCTAssertEqual(session.state.phase, .building)
        XCTAssertTrue(session.state.hasStarted)
        let started = session.state
        XCTAssertThrowsError(try session.apply(.begin)) { XCTAssertEqual($0 as? WorkshopError, .alreadyStarted) }
        XCTAssertEqual(session.state, started)
    }

    func testOnlyANDMissionAvailableInGuidedWorkshop() throws {
        var session = try connected()
        let before = session.state
        let actionsBefore = session.actions
        for action in [CircuitAction.selectMission(.or), .nextMission, .reset(seed: 9)] {
            XCTAssertThrowsError(try session.apply(.circuit(action))) {
                XCTAssertEqual($0 as? WorkshopError, .unsupportedCircuitAction)
            }
            XCTAssertEqual(session.state, before)
            XCTAssertEqual(session.actions, actionsBefore)
        }
    }

    func testMissingGateOrAnyWireCannotObserveOrVerify() throws {
        var empty = WorkshopSession()
        try empty.apply(.begin)
        var sessions = [empty]
        for link in CircuitLink.allCases {
            var session = try connected()
            try session.apply(.circuit(.toggleLink(link)))
            sessions.append(session)
        }
        for var session in sessions {
            let before = session.state
            XCTAssertEqual(before.phase, .building)
            for action in [WorkshopAction.observe, .circuit(.step), .circuit(.verify)] {
                XCTAssertThrowsError(try session.apply(action)) { XCTAssertEqual($0 as? WorkshopError, .connectionRequired) }
                XCTAssertEqual(session.state, before)
            }
        }
    }

    func testConnectionEntersObservingWithoutClaimingAnObservation() throws {
        let session = try connected()
        XCTAssertEqual(session.state.phase, .observing)
        XCTAssertTrue(session.state.canObserve)
        XCTAssertTrue(session.state.observations.isEmpty)
        XCTAssertEqual(session.state.circuit.verification, .untested)
    }

    func testInputChangesAndCompanionDoNotAutomaticallyClaimObservations() throws {
        var session = try connected()
        try session.apply(.circuit(.toggleInput(.a)))
        XCTAssertTrue(session.state.observations.isEmpty)
        XCTAssertEqual(session.state.circuit.output, .low)
        try session.apply(.askCompanion)
        XCTAssertEqual(session.state.circuit.inputs, InputPair(a: true, b: true))
        XCTAssertEqual(session.state.circuit.output, .high)
        XCTAssertEqual(session.state.feedback, .companionChangedInput)
        XCTAssertTrue(session.state.observations.isEmpty)
        try session.apply(.observe)
        XCTAssertEqual(session.state.observedInputs, [InputPair(a: true, b: true)])
        XCTAssertEqual(session.state.observations.first?.actual, .high)
        XCTAssertEqual(session.state.circuit.verification, .untested)
    }

    func testObservationNotebookDeduplicatesAndSortsActualTestedRows() throws {
        var session = try connected(.or)
        for pair in InputPair.truthTable.reversed() {
            try session.apply(.circuit(.setInputs(pair)))
            try session.apply(.observe)
            try session.apply(.observe)
        }
        XCTAssertEqual(session.state.observedInputs, InputPair.truthTable)
        XCTAssertEqual(session.state.observations.map(\.actual), [.low, .high, .high, .high])
        XCTAssertEqual(session.state.observations.map(\.expected), [false, false, false, true])
        XCTAssertEqual(session.state.circuit.verification, .untested, "Observation does not silently complete the evaluation.")
    }

    func testEveryGateAndWireChangeInvalidatesNotebookAndVerification() throws {
        var proven = try connected()
        try proven.apply(.circuit(.verify))
        try proven.apply(.circuit(.predict(false)))
        for action in [CircuitAction.selectGate(.xor), .toggleLink(.inputA), .toggleLink(.inputB), .toggleLink(.output)] {
            var changed = proven
            try changed.apply(.circuit(action))
            XCTAssertTrue(changed.state.observations.isEmpty)
            XCTAssertTrue(changed.state.circuit.checks.isEmpty)
            XCTAssertNil(changed.state.circuit.prediction.answer)
            XCTAssertNotEqual(changed.state.phase, .verified)
        }
    }

    func testReselectingSameGateAndInputChangesKeepValidNotebook() throws {
        var session = try connected()
        try session.apply(.circuit(.verify))
        let evidence = session.state.observations
        try session.apply(.circuit(.selectGate(.and)))
        try session.apply(.circuit(.toggleInput(.a)))
        try session.apply(.askCompanion)
        XCTAssertEqual(session.state.observations, evidence)
        XCTAssertEqual(session.state.circuit.verification, .passed)
        XCTAssertEqual(session.state.phase, .verified)
    }

    func testSequentialVerificationRequiresFourConditionsAndRecordsEach() throws {
        var session = try connected()
        for row in 0..<4 {
            try session.apply(.circuit(.step))
            XCTAssertEqual(session.state.circuit.inputs, InputPair.truthTable[row])
            XCTAssertEqual(session.state.observations.count, row + 1)
            XCTAssertEqual(session.state.phase, row == 3 ? .verified : .observing)
            XCTAssertEqual(session.state.canFinish, row == 3)
        }
        XCTAssertEqual(session.state.feedback, .verificationPassed)
        XCTAssertTrue(session.state.feedbackText.contains("AND"))
        try session.apply(.circuit(.setInputs(InputPair(a: false, b: false))))
        XCTAssertEqual(session.state.phase, .verified, "Returning the animation to the initial input preserves evidence.")
        XCTAssertEqual(session.state.observations.count, 4)
    }

    func testWrongGatesFailWithConcreteValidatedCounterexamples() throws {
        for gate in [GateKind.or, .xor] {
            var session = try connected(gate)
            try session.apply(.circuit(.verify))
            XCTAssertEqual(session.state.phase, .observing)
            XCTAssertEqual(session.state.feedback, .verificationFailed)
            XCTAssertFalse(session.state.canFinish)
            let wrong = try XCTUnwrap(session.state.circuit.checks.first(where: { !$0.passed }))
            try session.apply(.selectCounterexample(wrong.inputs))
            XCTAssertEqual(session.state.selectedCounterexample, wrong.inputs)
            XCTAssertEqual(session.state.circuit.output, wrong.actual)
            let before = session.state
            XCTAssertThrowsError(try session.apply(.selectCounterexample(InputPair(a: false, b: false)))) {
                XCTAssertEqual($0 as? WorkshopError, .invalidCounterexample)
            }
            XCTAssertEqual(session.state, before)
            try session.apply(.circuit(.selectGate(.and)))
            XCTAssertNil(session.state.selectedCounterexample)
            XCTAssertThrowsError(try session.apply(.selectCounterexample(wrong.inputs)))
        }
    }

    func testUnverifiedOrWrongCircuitsCannotCreateCompletedWork() throws {
        for gate in GateKind.allCases {
            var session = try connected(gate)
            if gate != .and { try session.apply(.circuit(.verify)) }
            let before = session.state
            XCTAssertThrowsError(try session.apply(.finish)) { XCTAssertEqual($0 as? WorkshopError, .verificationRequired) }
            XCTAssertEqual(session.state, before)
            XCTAssertNil(session.state.completedArtifact)
        }
    }

    func testPredictionIsOptionalAndWrongPredictionDoesNotBlockFinish() throws {
        for answer in [Optional<Bool>.none, false, true] {
            var session = try connected()
            try session.apply(.circuit(.verify))
            if let answer { try session.apply(.circuit(.predict(answer))) }
            try session.apply(.finish)
            XCTAssertEqual(session.state.phase, .finished)
            XCTAssertFalse(session.state.canFinish)
            let work = try XCTUnwrap(session.state.completedArtifact)
            XCTAssertEqual(work.circuit.verification, .passed)
            XCTAssertEqual(work.circuit.prediction.answer, answer)
            XCTAssertEqual(work.observations.count, 4)
            XCTAssertEqual(work.completedActionIndex, session.actions.count)
        }
    }

    func testResetKeepsFinishedArtifactButStartsNewCleanAttempt() throws {
        var session = try connected()
        try session.apply(.circuit(.verify))
        try session.apply(.finish)
        let work = session.state.completedArtifact
        try session.apply(.reset)
        XCTAssertEqual(session.state.phase, .building)
        try assertSameWork(session.state.completedArtifact, work)
        XCTAssertNil(session.state.circuit.selectedGate)
        XCTAssertTrue(session.state.observations.isEmpty)
        XCTAssertEqual(session.state.circuit.verification, .untested)
        try session.apply(.circuit(.selectGate(.or)))
        try assertSameWork(session.state.completedArtifact, work)
    }

    func testUndoRestoresGateEvidenceHintsAndPredictionAsOneConsistentState() throws {
        var session = try connected()
        try session.apply(.circuit(.verify))
        try session.apply(.hint)
        try session.apply(.circuit(.predict(false)))
        let before = session.state
        try session.apply(.circuit(.selectGate(.xor)))
        XCTAssertEqual(session.state.observations.count, 0)
        XCTAssertEqual(session.state.hintLevel, 0)
        try session.apply(.undo)
        XCTAssertEqual(session.state, before)
        XCTAssertEqual(session.actions.last, .undo)
    }

    func testFinishIsCheckpointAndLaterEditUndoCannotDeleteWork() throws {
        var session = try connected()
        try session.apply(.circuit(.verify))
        try session.apply(.finish)
        let finished = session.state
        XCTAssertFalse(session.state.canUndo)
        XCTAssertThrowsError(try session.apply(.undo)) { XCTAssertEqual($0 as? WorkshopError, .nothingToUndo) }
        XCTAssertEqual(session.state, finished)
        try session.apply(.circuit(.selectGate(.xor)))
        try session.apply(.undo)
        XCTAssertEqual(session.state, finished)
        XCTAssertNotNil(session.state.completedArtifact)
        XCTAssertThrowsError(try session.apply(.undo))
        let restored = try WorkshopSession.replay(data: encoded(session.replayDocument()))
        XCTAssertEqual(restored.state, finished)
    }

    func testResetCompactsSavedWorkAndBeginsNewUndoHistory() throws {
        for answer in [Optional<Bool>.none, false, true] {
            var session = try connected()
            // Noise before the checkpoint should disappear without changing the work.
            for _ in 0..<37 { try session.apply(.askCompanion) }
            try session.apply(.circuit(.verify))
            for _ in 0..<3 { try session.apply(.circuit(.step)) }
            try session.apply(.circuit(.setInputs(InputPair(a: true, b: true))))
            if let answer { try session.apply(.circuit(.predict(answer))) }
            try session.apply(.finish)
            let work = session.state.completedArtifact
            try session.apply(.circuit(.selectGate(.or)))
            try session.apply(.reset)
            XCTAssertLessThan(session.actions.count, 16)
            XCTAssertEqual(session.state.phase, .building)
            XCTAssertFalse(session.state.canUndo)
            XCTAssertThrowsError(try session.apply(.undo))
            try assertSameWork(session.state.completedArtifact, work)
            let compactJournal = try encoded(session.replayDocument())
            let restored = try WorkshopSession.replay(data: compactJournal)
            XCTAssertEqual(restored.state, session.state)
            XCTAssertEqual(try encoded(restored.replayDocument()), compactJournal)
            // A second reset is an idempotent boundary, not an ever-growing journal.
            try session.apply(.reset)
            XCTAssertEqual(try encoded(session.replayDocument()), compactJournal)
            let resetState = session.state
            try session.apply(.circuit(.selectGate(.xor)))
            try session.apply(.undo)
            XCTAssertEqual(session.state, resetState)
        }
    }

    func testResetRecoversAtJournalLimitWithAndWithoutSavedWork() throws {
        for keepWork in [false, true] {
            var session = try connected()
            if keepWork {
                try session.apply(.circuit(.verify))
                try session.apply(.finish)
            }
            let work = session.state.completedArtifact
            while session.actions.count < WorkshopSession.maximumReplayActions {
                try session.apply(.hint)
            }
            let boundedState = session.state
            XCTAssertThrowsError(try session.apply(.askCompanion))
            XCTAssertEqual(session.state, boundedState)
            // The long save remains valid. Reset can recover even after an app restart.
            session = try WorkshopSession.replay(data: encoded(session.replayDocument()))
            try session.apply(.reset)
            XCTAssertLessThan(session.actions.count, 16)
            XCTAssertFalse(session.state.canUndo)
            if keepWork { try assertSameWork(session.state.completedArtifact, work) }
            else { XCTAssertNil(session.state.completedArtifact) }
            try session.apply(.circuit(.selectGate(.and)))
            XCTAssertEqual(session.state.circuit.selectedGate, .and)
            let reloaded = try WorkshopSession.replay(data: encoded(session.replayDocument()))
            XCTAssertEqual(reloaded.state, session.state)
        }
    }

    func testResetBeforeStartRemainsWelcomeAndReplayStable() throws {
        var session = WorkshopSession()
        try session.apply(.reset)
        XCTAssertEqual(session.state.phase, .welcome)
        XCTAssertFalse(session.state.hasStarted)
        XCTAssertFalse(session.state.canUndo)
        XCTAssertEqual(session.actions, [.reset])
        try session.apply(.reset)
        XCTAssertEqual(session.actions, [.reset])
        let restored = try WorkshopSession.replay(data: encoded(session.replayDocument()))
        XCTAssertEqual(restored.state, session.state)
        try session.apply(.begin)
        XCTAssertEqual(session.state.phase, .building)
    }

    func testUndoDepthIsBoundedAndEmptyUndoIsAtomic() throws {
        var session = WorkshopSession()
        XCTAssertThrowsError(try session.apply(.undo)) { XCTAssertEqual($0 as? WorkshopError, .nothingToUndo) }
        XCTAssertTrue(session.actions.isEmpty)
        try session.apply(.begin)
        for _ in 0..<80 { try session.apply(.askCompanion) }
        for _ in 0..<WorkshopSession.maximumUndoDepth { try session.apply(.undo) }
        XCTAssertFalse(session.state.canUndo)
        let before = session.state
        let journal = session.actions
        XCTAssertThrowsError(try session.apply(.undo))
        XCTAssertEqual(session.state, before)
        XCTAssertEqual(session.actions, journal)
        XCTAssertTrue(session.state.hasStarted, "Old undo history is intentionally discarded.")
    }

    func testHintsEscalateOnlyOnRequestWithoutChangingBoardOrMastery() throws {
        var session = try connected()
        let circuit = session.state.circuit
        for expected in [1, 2, 3, 3] {
            try session.apply(.hint)
            XCTAssertEqual(session.state.hintLevel, expected)
            XCTAssertEqual(session.state.circuit, circuit)
            XCTAssertTrue(session.state.observations.isEmpty)
        }
        XCTAssertTrue(session.state.feedbackText.contains("&"))
    }

    func testReplayRoundTripReconstructsUndoCompletedWorkAndCurrentAttempt() throws {
        var session = try connected(.or)
        try session.apply(.circuit(.verify))
        try session.apply(.selectCounterexample(InputPair(a: false, b: true)))
        try session.apply(.hint)
        try session.apply(.circuit(.selectGate(.and)))
        for _ in 0..<4 { try session.apply(.circuit(.step)) }
        try session.apply(.finish)
        try session.apply(.reset)
        try session.apply(.circuit(.selectGate(.xor)))
        let data = try encoded(session.replayDocument())
        let restored = try WorkshopSession.replay(data: data)
        XCTAssertEqual(restored.state, session.state)
        XCTAssertEqual(restored.actions, session.actions)
        XCTAssertEqual(try encoded(restored.state), try encoded(session.state))
        XCTAssertEqual(try encoded(restored.replayDocument()), data)
        var canContinueUndo = restored
        try canContinueUndo.apply(.undo)
        XCTAssertNil(canContinueUndo.state.circuit.selectedGate)
        XCTAssertNotNil(canContinueUndo.state.completedArtifact)
    }

    func testReplayRejectsUnsupportedVersionsAndMalformedData() throws {
        let session = WorkshopSession()
        for pair in [("schemaVersion", 999 as Any), ("modelVersion", "future" as Any), ("circuitModelVersion", "future" as Any)] {
            XCTAssertThrowsError(try WorkshopSession.replay(data: editedDocument(session, key: pair.0, value: pair.1)))
        }
        for data in [Data(), Data("{".utf8), Data("{}".utf8), try encoded(session.state)] {
            XCTAssertThrowsError(try WorkshopSession.replay(data: data))
        }
        XCTAssertThrowsError(try WorkshopSession.replay(data: editedDocument(session, key: "actions", value: [["unknownAction": [:]]])))
    }

    func testReplayValidatesJournalRatherThanTrustingClaimedSuccess() throws {
        XCTAssertThrowsError(try WorkshopSession.replay(WorkshopReplay(initialSeed: 17, actions: [.begin, .finish])))
        XCTAssertThrowsError(try WorkshopSession.replay(WorkshopReplay(initialSeed: 17, actions: [.undo])))
        let session = WorkshopSession()
        let restored = try WorkshopSession.replay(data: editedDocument(session, key: "state", value: ["phase": "finished"]))
        XCTAssertEqual(restored.state.phase, .welcome, "Untrusted snapshot claims never supply the loaded state.")
        XCTAssertNil(restored.state.completedArtifact)
    }

    func testReplayBoundsBytesAndActionCountBeforeExecuting() throws {
        let oversizedData = Data(repeating: 32, count: WorkshopSession.maximumReplayBytes + 1)
        XCTAssertThrowsError(try WorkshopSession.replay(data: oversizedData)) {
            XCTAssertEqual($0 as? WorkshopError, .documentTooLarge(oversizedData.count))
        }
        let oversized = WorkshopReplay(initialSeed: 17,
            actions: Array(repeating: .begin, count: WorkshopSession.maximumReplayActions + 1))
        XCTAssertThrowsError(try WorkshopSession.replay(oversized)) {
            XCTAssertEqual($0 as? WorkshopError, .tooManyActions(WorkshopSession.maximumReplayActions + 1))
        }
    }

    func testSeedsAtUInt64ExtremesAndSnapshotEncodingStayDeterministic() throws {
        for seed in [UInt64(0), 17, UInt64.max] {
            let first = try connected(seed: seed)
            let second = try connected(seed: seed)
            XCTAssertEqual(first.state, second.state)
            XCTAssertEqual(try encoded(first.state), try encoded(second.state))
            let decoded = try JSONDecoder().decode(WorkshopSnapshot.self, from: encoded(first.state))
            XCTAssertEqual(decoded, first.state)
        }
    }
}
