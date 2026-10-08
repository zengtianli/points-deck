import Foundation
import Darwin
#if os(iOS)
import UIKit
#endif

/// Uses production Api and the real isolated server. Each mode is a fresh
/// process; _exit deliberately skips Foundation's normal termination cleanup.
enum SessionPersistenceChecks {
    static func run() async {
        let mode = CommandLine.arguments.last!
        do {
            let fixtureURL = Bundle.main.url(forResource: "fixture", withExtension: "json")!
            let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
            UserDefaults.standard.set(fixture["url"] as! String, forKey: "api_base")
            switch mode {
            case "login":
                do {
                    try await Api.login(user: fixture["user"] as! String, password: "known-wrong-synthetic-password")
                    throw CheckFailure()
                } catch let failure as Api.Failure { guard failure.status == 401 else { throw CheckFailure() } }
                try await Api.login(user: fixture["user"] as! String, password: fixture["pw"] as! String)
                let state = try await Api.request("api/state")
                guard state["u"] as? String == fixture["user"] as? String,
                      let cookie = Api.sessionCookie(), !cookie.isSessionOnly,
                      cookie.expiresDate != nil else { throw CheckFailure() }
            case "restore":
                guard Api.sessionCookie() != nil else { throw CheckFailure() }
                let state = try await Api.request("api/state")
                guard state["u"] as? String == fixture["user"] as? String else { throw CheckFailure() }
            case "logout":
                await Api.logout()
                guard Api.sessionCookie() == nil else { throw CheckFailure() }
            case "signedout":
                guard Api.sessionCookie() == nil else { throw CheckFailure() }
                do { _ = try await Api.request("api/state"); throw CheckFailure() }
                catch let failure as Api.Failure { guard failure.status == 401 else { throw CheckFailure() } }
            default: throw CheckFailure()
            }
            FileHandle.standardOutput.write(Data("SESSION-PASS: \(mode)\n".utf8))
            _exit(0)
        } catch {
            // Never include request bodies, cookies or synthetic passwords.
            FileHandle.standardError.write(Data("SESSION-FAIL: \(mode) \(type(of: error))\n".utf8))
            _exit(1)
        }
    }
    struct CheckFailure: Error {}
}

#if os(iOS)
final class SessionProbeDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Probe", sessionRole: session.role)
        configuration.delegateClass = SessionProbeSceneDelegate.self
        return configuration
    }
}
final class SessionProbeSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        Task { await SessionPersistenceChecks.run() }
        // Adopt iPadOS 27 scene lifecycle without creating a window.
    }
}
@main struct SessionProbe {
    static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(SessionProbeDelegate.self))
    }
}
#else
@main struct SessionProbe {
    static func main() async { await SessionPersistenceChecks.run() }
}
#endif
