import Foundation

// Exercise the production Api and parent session. All requests are intercepted;
// no real account, Keychain entry, ledger, or server is touched.
private final class ParentTransport: URLProtocol {
    static var paths: [String] = []
    static var rejects = true
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.paths.append(request.url!.path)
        precondition(request.httpMethod == "POST")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.rejects ? 403 : 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((Self.rejects ? "{\"ok\":false,\"err\":\"wrong parent password\"}" : "{\"ok\":true}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ParentSessionChecks {
    @MainActor static func main() async throws {
        precondition(URLProtocol.registerClass(ParentTransport.self))
        defer { URLProtocol.unregisterClass(ParentTransport.self) }
        let session = ParentSession()
        precondition(!session.isUnlocked && session.password == nil && session.count == 0)
        do {
            try await session.unlock(password: "synthetic wrong")
            preconditionFailure("Server refusal must never unlock the parent session")
        } catch is Api.Failure {}
        precondition(!session.isUnlocked)
        ParentTransport.rejects = false
        try await session.unlock(password: "synthetic accepted")
        precondition(session.isUnlocked && session.count == 0)
        precondition(ParentTransport.paths == ["/api/config", "/api/config"],
                     "Unlock may only verify the read-only config endpoint, never create a ledger entry")
        session.noteEarned(); session.noteEarned()
        precondition(session.count == 2)
        let time = Date(timeIntervalSince1970: 1_000)
        session.scenePhaseChanged(to: .inactive, at: time)
        session.scenePhaseChanged(to: .background, at: time.addingTimeInterval(590))
        session.scenePhaseChanged(to: .active, at: time.addingTimeInterval(601))
        precondition(!session.isUnlocked && session.password == nil && session.count == 0,
                     "Repeated background transitions must not extend the original ten-minute expiry")
        session.unlock("synthetic accepted")
        session.scenePhaseChanged(to: .background, at: time)
        session.scenePhaseChanged(to: .active, at: time.addingTimeInterval(10))
        precondition(session.isUnlocked)
        session.lock()
        precondition(session.password == nil && !ParentSession().isUnlocked)
        print("PASS: server refusal stays locked; read-only unlock; ledger count; idle expiry; explicit lock; fresh session locked; 0 real network")
    }
}
