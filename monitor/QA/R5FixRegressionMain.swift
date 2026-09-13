import Foundation
import Darwin

@main
struct R5FixRegressionMain {
    static func main() {
        do {
            if CommandLine.arguments.last == "storage" { try runStorageTests() }
            else { try runDeviceTests() }
            print("R5 targeted regression passed")
        } catch {
            print("R5 targeted regression failed: \(error)")
            exit(1)
        }
    }
}
