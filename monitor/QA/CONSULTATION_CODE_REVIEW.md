# Consultation Feature Code Review

## Verdict

**APPROVE** — the bounded consultation feature review found no remaining actionable correctness, security, privacy, or lifecycle defect.

| Severity | Count |
| --- | ---: |
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |

**Files reviewed:** `Sources/CodexRPC.swift`, `Sources/ConsultationModel.swift`, `Sources/ConsultationPayload.swift`, `Sources/ConsultationView.swift`, the consultation changes in `Sources/App.swift` and `Sources/MonitorStore.swift`, `Tests/ConsultationTests.swift`, `Tests/TestMain.swift`, `CONSULTATION.md`, `README.md`, and `PrivacyInfo.xcprivacy`.

## Stage 1 — requested behavior

- The runtime isolates `CODEX_HOME`, does not inherit API-key or endpoint variables, forces ChatGPT login, and checks `account.type == chatgpt` again before every inference at [CodexRPC.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/CodexRPC.swift:45) and [ConsultationModel.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/ConsultationModel.swift:144). An API-key account cannot reach `thread/start` or `turn/start`.
- Threads are ephemeral and turns apply read-only sandboxing, `approvalPolicy: never`, and tool-network denial. Shell, unified execution, code mode, apps, plugins, hooks, multi-agent, browser, computer-use, image generation, and tool discovery are disabled at [CodexRPC.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/CodexRPC.swift:53). Server-initiated requests are rejected at [CodexRPC.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/CodexRPC.swift:152). There is no automatic repair path.
- Consultation attachments are built from an explicit category/metric allowlist and synthesize their source labels rather than copying source paths or error details at [ConsultationPayload.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/ConsultationPayload.swift:20). The projection uses top-level basic panel metrics only at [MonitorStore.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:107); process rows, storage-tree rows, connection rows, history, diagnostic results, and raw power details are excluded.
- The UI freezes a `ConsultationDraft` before presenting the complete transmitted text and sends that exact draft only after the explicit confirmation action at [ConsultationView.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/ConsultationView.swift:98). Model output is rendered as selectable plain text and cannot invoke links or actions.
- User messages carry explicit pending, accepted, or unconfirmed delivery state. The 20-turn limit counts accepted turn IDs in the current remote thread and resets when that thread is reset at [ConsultationModel.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/ConsultationModel.swift:144) and [ConsultationModel.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/ConsultationModel.swift:207). Old visible messages are not forwarded or counted against a new thread.
- Shutdown waits for normal exit or the bounded SIGKILL fallback through [CodexRPC.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/CodexRPC.swift:172), [ConsultationModel.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/ConsultationModel.swift:215), and [App.swift](/Users/sodaiyamamoto/aibou/monitor/Sources/App.swift:10).
- `PrivacyInfo.xcprivacy` declares linked user content and diagnostic data for app functionality, without tracking, consistent with the disclosed OpenAI transmission.

No fallback masks a failed primary contract: RPC parse, timeout, write, authentication, turn creation, and process-exit failures remain visible. The client does not automatically retry a possibly accepted turn.

## Issues resolved during review

Two concrete lifecycle/state gaps were identified and corrected before this final verdict:

1. **Process teardown:** `CodexRPC.close()` originally scheduled SIGKILL after returning without giving application termination a way to wait. The final code tracks child termination, exposes a bounded exit wait, joins it with monitor cleanup, and tests a SIGTERM-ignoring child at [ConsultationTests.swift](/Users/sodaiyamamoto/aibou/monitor/Tests/ConsultationTests.swift:159).
2. **Delivery and quota state:** The original implementation presented pre-accept failures as ordinary sent messages and derived the 20-turn limit from retained display history. The final code marks delivery as pending/accepted/unconfirmed, counts accepted remote turn IDs, and resets that count with the thread. Regression coverage verifies failed-send status and a new first turn after a 20-turn disconnect/reconnect at [ConsultationTests.swift](/Users/sodaiyamamoto/aibou/monitor/Tests/ConsultationTests.swift:125) and [ConsultationTests.swift](/Users/sodaiyamamoto/aibou/monitor/Tests/ConsultationTests.swift:136).

These resolved items are not included in the final severity count.

## Validation

- The full warnings-as-errors fixture suite passed after both fixes: `Consultation tests passed (fixtures; no paid inference)` and `AIBOU Monitor: ALL TESTS PASSED` in `QA/consultation-tests.log`.
- A real `codex-cli 0.145.0` isolated no-auth handshake passed `initialize`, `account/read`, and `config/read`: the dedicated environment reported `account=null`, `forced_login_method=chatgpt`, and the checked tool restrictions disabled. No login or inference was requested.
- A locally generated App Server v2 schema confirmed the implemented `developerInstructions`, `sandboxPolicy`, `networkAccess`, account, login-completion, and account-update field shapes. Schema generation used no account and no inference; its temporary output was removed.
- The consultation UI fixture rendered successfully without a real account or inference.
- The review did not access real authentication data or issue an inference request.
- A dedicated editor LSP diagnostic surface is unavailable for this custom Swift build. The warnings-as-errors compiler run is the available type and compiler-diagnostic evidence; the parent validation lane is completing the final application build and bundle checks.

## Recommendation

**APPROVE.** The feature meets the authorized subscription-only authentication, in-app follow-up conversation, aggregate attachment preview, restricted execution, explicit-send, no-automatic-fix, and bounded-shutdown requirements.
