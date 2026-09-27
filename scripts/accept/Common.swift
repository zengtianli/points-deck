import Foundation

// Shared helpers for the fixed acceptance checks. The checks call the production Api / ParentSession
// directly; only the base URL is switched through the volatile argument domain (nothing written to disk).
enum Accept {
    static let env = ProcessInfo.processInfo.environment
    static var kidUser: String { env["ACCEPT_KID_USER"]! }
    static var kidPw: String { env["ACCEPT_KID_PW"]! }
    static var parentPw: String { env["ACCEPT_PARENT_PW"]! }
    static var port: String { env["ACCEPT_PORT"]! }

    static func step(_ text: String) { print("ACCEPT: " + text); fflush(stdout) }

    static func expect(_ ok: Bool, _ what: String,
                       file: StaticString = #fileID, line: UInt = #line) {
        if !ok { print("FAIL: \(what) (\(file):\(line))"); fflush(stdout); exit(1) }
    }

    /// The Api.Failure message a call produced, or nil when it succeeded.
    static func failure(_ body: () async throws -> Void) async -> String? {
        do { try await body(); return nil } catch { return error.localizedDescription }
    }

    static func useBase(_ url: String) {
        UserDefaults.standard.setVolatileDomain(["api_base": url], forName: UserDefaults.argumentDomain)
    }

    static func balance() async throws -> Int { try await Api.state().balance }

    /// A fixed-value rule with a positive score, picked from what the server itself published.
    static func fixedRule(_ s: LedgerState) -> LedgerState.Rule? {
        s.rules.first { $0.kind == "fixed" && $0.pts > 0 }
    }

    static func stopServer() {
        let pidFile = env["ACCEPT_PID_FILE"]!
        guard let pid = Int32((try? String(contentsOfFile: pidFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else { return }
        kill(pid, SIGTERM)
        for _ in 0..<50 where kill(pid, 0) == 0 { usleep(100_000) }
    }

    static func startServer() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [env["ACCEPT_PYTHON"] ?? "python3", "server.py", "serve"]
        p.currentDirectoryURL = URL(fileURLWithPath: env["ACCEPT_SERVER_DIR"]!)
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        try "\(p.processIdentifier)".write(toFile: env["ACCEPT_PID_FILE"]!, atomically: true, encoding: .utf8)
        let health = URL(string: "http://127.0.0.1:\(port)/api/health")!
        for _ in 0..<50 {
            if let (_, r) = try? awaitSync({ try await URLSession.shared.data(from: health) }),
               (r as? HTTPURLResponse)?.statusCode == 200 { return }
            usleep(100_000)
        }
        throw Api.Failure(message: "本地账本服务重启失败")
    }

    private static func awaitSync<T>(_ body: @escaping () async throws -> T) throws -> T {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<T, Error>!
        Task.detached { do { result = .success(try await body()) } catch { result = .failure(error) }; sem.signal() }
        sem.wait()
        return try result.get()
    }
}
