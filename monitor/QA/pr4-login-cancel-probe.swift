import Foundation
import Combine

enum ConsultationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        if case .message(let value) = self { return value }
        return nil
    }
}

@MainActor
protocol ConsultationRPC: AnyObject {
    var onNotification: ((String, [String: Any]) -> Void)? { get set }
    var onDisconnect: ((String) -> Void)? { get set }
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any]
    func notify(_ method: String, _ params: [String: Any]) throws
    func close()
    func afterExit(timeout: TimeInterval, completion: @escaping (Bool) -> Void)
}

extension ConsultationRPC {
    func afterExit(timeout: TimeInterval, completion: @escaping (Bool) -> Void) { completion(true) }
}

enum CodexConsultationRuntime {
    static var defaultDirectory: URL { URL(fileURLWithPath: "/tmp") }
    static func findExecutable() -> URL? { nil }
}

@MainActor
final class CodexRPC: ConsultationRPC {
    var onNotification: ((String, [String: Any]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    init(executable: URL, directory: URL) throws {}
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] { [:] }
    func notify(_ method: String, _ params: [String: Any]) throws {}
    func close() {}
}

struct ConsultationDraft {
    let question: String
    let attachment: String?
    var transmittedText: String { question + (attachment ?? "") }
}

@MainActor
private final class CancelRaceRPC: ConsultationRPC {
    var onNotification: ((String, [String: Any]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    func notify(_ method: String, _ params: [String: Any]) throws {}
    func close() {}

    var accountSignedIn = false
    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "account/read":
            if accountSignedIn { return ["account": ["type": "chatgpt", "planType": "plus"]] }
            return ["account": NSNull()]
        case "account/login/start":
            return ["type": "chatgpt", "loginId": "login-2", "authUrl": "https://auth.openai.com/test"]
        case "account/login/cancel":
            accountSignedIn = true
            onNotification?("account/login/completed", [
                "loginId": "login-2", "success": true, "error": NSNull()
            ])
            onNotification?("account/updated", ["authMode": "chatgpt"])
            return ["status": "notFound"]
        default:
            return [:]
        }
    }
}

@main
struct LoginOrderProbe {
    static func main() async {
        let cancelRPC = CancelRaceRPC()
        let cancelModel = ConsultationModel(factory: { _, _ in cancelRPC })
        await cancelModel.connect()
        await cancelModel.login()
        await cancelModel.cancelLogin()
        print("cancel-race serverSignedIn=\(cancelRPC.accountSignedIn) signedIn=\(cancelModel.signedIn) loginURL=\(cancelModel.loginURL != nil) status=\(cancelModel.status)")
    }
}
