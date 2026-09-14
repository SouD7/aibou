import Foundation
import Darwin

@main
struct MonitorTestMain {
    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--app-detail-preview" {
            try await renderApplicationDetailPreview(to: URL(fileURLWithPath: CommandLine.arguments[2])); return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--launcher-launch-smoke" {
            try await runApplicationLaunchSmoke(at: URL(fileURLWithPath: CommandLine.arguments[2])); return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--launcher-preview" {
            try await renderApplicationLauncherPreview(to: URL(fileURLWithPath: CommandLine.arguments[2])); return
        }
        if CommandLine.arguments.contains("--consultation-rpc-fixture") { try runConsultationRPCFixture(); return }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--codex-handshake" {
            try await runCodexConsultationHandshake(executable: URL(fileURLWithPath: CommandLine.arguments[2])); return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--consultation-preview" {
            try await renderConsultationPreview(to: URL(fileURLWithPath: CommandLine.arguments[2])); return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--ignore-term-fixture" {
            signal(SIGTERM, SIG_IGN)
            alarm(5) // Independent cleanup if the test runner fails before cancellation.
            try Data([1]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            while true { Darwin.pause() }
        }
        try runCoreTests()
        try runDeviceTests()
        try runStorageTests()
        try runAdditionalTests()
        try runHistoryTests()
        try runObservationTests()
        try runDiagnosticTests()
        try await runStoreTests()
        try await runConsultationTests()
        try await runApplicationLauncherTests()
        try runApplicationUsageTests()
        try runApplicationStorageTests()
        try await runApplicationDetailLifecycleTests()
        print("AIBOU Monitor: ALL TESTS PASSED")
    }
}
