# R6 Independent Code Review

## Verdict

**COMMENT** — the three R5 repair items are correctly implemented and the fixed snapshot passes its verification suite, but this fresh full review found two additional MEDIUM correctness gaps in saved-index validation and `nettop` attribution.

**Files reviewed:** 31/31 manifest files (12 source files, 9 test files, and 10 scripts, plists, and documents)

| Severity | Count |
| --- | ---: |
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 2 |
| LOW | 0 |

The reviewed snapshot is `/var/folders/53/pz7xqxg90pb8jlkvjt0tnv800000gn/T/aibou-r6-review-scqrycml`. Its 31 SHA-256 entries match `QA/r6-snapshot.json`, whose `changed_since_r5_fix` list is empty. Live source links below have the same content and line numbers as the fixed snapshot.

## Stage 1 — specification compliance

The requested R5 fixes are complete:

- Inventory results retain their acquisition wall-clock timestamp while cache expiry is driven by `ContinuousClock` at [Sources/DeviceSampler.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:45) and [Sources/DeviceSampler.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:274). The clock-forward, clock-backward, exact-boundary, and cached-failure cases are covered at [Tests/DeviceTests.swift](/Users/sodaiyamamoto/aibou/monitor/Tests/DeviceTests.swift:17).
- Saved storage results validate schema, completed state, root identity/kind, completion time, counts, root totals, and error counts before restoration at [Sources/StorageScanner.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:246). The intended metadata cases are covered in `StorageTests`.
- Sustained diagnostics are documented and implemented through the existing `MonitorStore`; the one-shot API remains a `.snapshot` and resets continuity at [README.md](/Users/sodaiyamamoto/aibou/monitor/README.md:15), [Sources/MonitorStore.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:14), and [Sources/Diagnostics.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/Diagnostics.swift:66).

No new fallback suppresses an underlying failure or converts a failed contract into a silent success. The two remaining specification deviations are the confirmed findings below.

## New confirmed findings

### [MEDIUM] A saved storage tree can use a file node as a parent

**File:** [Sources/StorageScanner.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:272)

**Issue:** `validTree` proves that every `parentID` exists and that every node reaches the unique root, but the parent-resolution loop at lines 279–283 never requires the referenced parent to have `kind == .directory`. This is weaker than the documented parent-child consistency check at [README.md](/Users/sodaiyamamoto/aibou/monitor/README.md:71).

**Concrete trigger and evidence:** A local saved archive was constructed with a directory root, a child whose kind is `.file`, and a second file whose `parentID` names that first file. The archive also had a completed status, non-nil `completedAt`, matching `scannedCount`, matching root totals, and consistent error counts. A bounded probe compiled from `Common.swift`, `StorageScanner.swift`, and `AdditionalCollectors.swift` loaded it successfully and printed:

```text
archive_parent_kind=ACCEPTED status=saved nodes=3
```

This accepts and presents an impossible hierarchy as a trusted saved result. The trigger is a malformed or corrupted local saved input; it does not cross a privilege boundary.

**Minimal fix:** When resolving each parent ID, require `nodes[offset].kind == .directory` before storing the parent offset. Reject the archive with `invalidSavedIndex` otherwise.

**Coverage gap:** Graph tests at [Tests/StorageTests.swift](/Users/sodaiyamamoto/aibou/monitor/Tests/StorageTests.swift:152) cover cycles, self-cycles, a second root, a missing parent, path/ID mismatch, and a deep unordered chain, but their synthetic parents retain the root's directory kind. Add a file-parent rejection fixture.

### [MEDIUM] A malformed process row inherits the preceding `nettop` owner

**File:** [Sources/AdditionalCollectors.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:205)

**Issue:** `owner` and `processLabel` live across all selected rows. Lines 215–219 update them only when a non-connection label ends in `.PID`; line 220 still attaches the previous values when PID parsing fails, and line 241 describes every `pid == nil` row as a connection even when the label does not contain `<->`.

**Concrete trigger and evidence:** The parser was given a valid CSV table whose first row was a normal `good.42` process aggregate and whose next row was `malformed-process` with valid cumulative counters but no terminal PID:

```text
,state,bytes_in,bytes_out,
good.42,,100,200,
malformed-process,,300,400,
```

With PID 42 owned by `OWNER-42`, the bounded probe printed:

```text
nettop_malformed_owner=OWNER-42 note=good.42 の接続。計測区間の観測結果
```

The second row is therefore falsely attributed to the previous process. This can occur when `nettop` emits a malformed row or its OS-dependent format changes, a compatibility boundary already documented in the product.

**Minimal fix:** Treat process and connection rows separately. For every non-connection row, replace `processLabel` with the current label; if terminal PID parsing fails, reset the owner to `未特定` and report the row as unattributed or unsupported-format data. Only rows that contain `<->` should inherit the preceding process attribution.

**Coverage gap:** [Tests/AdditionalTests.swift](/Users/sodaiyamamoto/aibou/monitor/Tests/AdditionalTests.swift:28) covers a valid `.PID` process followed by a connection, and [Tests/AdditionalTests.swift](/Users/sodaiyamamoto/aibou/monitor/Tests/AdditionalTests.swift:53) covers malformed numeric values. Neither covers a non-connection label with missing or malformed PID syntax. Add that row after a valid attributed process and assert that owner and note do not carry over.

## Comparison with R5 review

| R5 repair item | R6 result |
| --- | --- |
| Inventory acquisition timestamps and monotonic TTL | **FIXED** |
| Saved-index top-level metadata validation | **FIXED**; the newly confirmed parent-kind gap is a separate structural invariant |
| Running `MonitorStore` versus one-shot snapshot documentation | **FIXED** |

The two MEDIUM findings above are new confirmed findings. They were not copied from `QA/R5_FIX_RESULTS.md` or `QA/R5_FIX_CODE_REVIEW.md`.

## Existing WATCH items, unchanged and not counted

The prior architecture WATCH items remain product tradeoffs rather than newly confirmed code defects in this review:

1. A queued pre-sleep sample can race with the clock baseline around sleep/wake.
2. Diagnostic projection currently rebuilds a full observation snapshot on `MainActor`.
3. History restoration currently runs on `MainActor`.
4. A 500,000-node saved index can require substantial JSON/index/Data memory.
5. Shutdown can enter the final index-build-to-save-registration gap before observing the pending save group.
6. Termination of the elevated `powermetrics` descendant remains unverified after stopping the direct `osascript` process.
7. Future multi-consumer use would require stronger ownership around the stateful `@unchecked Sendable` monitoring engine.

## Uncertain possibilities

No uncertain possibility is promoted to a finding. Wall-clock timestamp ordering is intentionally allowed to reflect clock corrections, and the elevated descendant-termination limitation remains explicitly documented as WATCH rather than asserted as a new defect.

## Verification evidence

- Independent inspection covered all 31 fixed-snapshot files, followed by comparison with the two prior R5 reports.
- A fresh isolated `test.sh` run completed with `AIBOU Monitor: ALL TESTS PASSED` in `QA/r6-tests.log`.
- A fresh isolated `run.sh --build` completed successfully; strict code-signature verification, both source and bundled plist checks, and shell syntax checks passed in `QA/r6-build.log` and `QA/r6-bundle-checks.log`.
- The diagnostic catalog check found 70 cases, 70 unique IDs, and no IDs missing from documentation in `QA/r6-catalog-check.json`.
- The bounded finding probe compiled only `Common.swift`, `StorageScanner.swift`, `AdditionalCollectors.swift`, and a temporary `@main` fixture with optimization and warnings-as-errors, using the snapshot module cache. Its temporary source, binary, and archive fixture were removed after the run.
- No dedicated editor LSP diagnostic surface was exposed for this custom non-package Swift build. The fresh all-source warnings-as-errors build is the available compiler-diagnostic evidence.

## Recommendation

**COMMENT.** Fix the two MEDIUM cases and add the focused regression fixtures before treating saved-tree structural validation and process attribution as complete. There are no CRITICAL or HIGH findings that block the broader R5 fix acceptance.
