import Foundation
import Darwin

@main
struct MonitorTestMain {
    @MainActor static func main() async throws {
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
        print("AIBOU Monitor: ALL TESTS PASSED")
    }
}
