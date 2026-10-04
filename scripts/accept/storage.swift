import Foundation

/// Cross-process checks use production Keychain implementations and a unique HTTPS account.
/// The wrapper's .lane bundle keeps Snapshot away from the installed product's shared entry.
@main
struct StorageCheck {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        print("PASS: " + message)
    }
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        let mode = env["POINTS_STORAGE_MODE"]!
        let base = env["POINTS_STORAGE_BASE"]!
        let user = env["POINTS_STORAGE_USER"]!
        UserDefaults.standard.setVolatileDomain(["api_base": base], forName: UserDefaults.argumentDomain)
        Api.accountUser = user
        let body: [String: Any] = ["pts": 5, "label": "跨进程恢复验证"]
        if mode == "save" {
            require(Bundle.main.bundleIdentifier?.hasSuffix(".lane") == true, "isolated lane bundle")
            let data = try Data(contentsOf: URL(fileURLWithPath: env["POINTS_STORAGE_STATE"]!))
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            LedgerCache.save(json)
            require(TransactionJournal.begin(path: "api/adjust", body: body, proposed: "owned-original-id") == "owned-original-id", "stable request saved")
            Snapshot(balance: 1133, houseName: "小木屋", nextName: "砖瓦房", toNext: 67,
                     progress: 0.9, era: "cottage", updated: Date()).save()
            require(Snapshot.load().balance == 1133, "production snapshot written and read")
        } else if mode == "restore" {
            Api.installSessionCookie("owned-synthetic-session", expires: Date().addingTimeInterval(3600))
            let state = LedgerCache.load()
            require(state != nil, "production ledger cache survives process restart")
            require(state?.nick == "小满", "cached account and ledger preserved")
            Api.accountUser = user
            require(TransactionJournal.begin(path: "api/adjust", body: body, proposed: "different-proposed-id") == "owned-original-id", "pending request survives process restart")
            require(Snapshot.load().balance == 1133, "snapshot survives process restart")
            TransactionJournal.finish(path: "api/adjust", body: body)
            require(TransactionJournal.begin(path: "api/adjust", body: body, proposed: "finished-new-id") == "finished-new-id", "confirmed request removed")
        } else if mode == "clear" {
            TransactionJournal.clear()
            LedgerCache.clear()
            Snapshot.empty.save()
            Api.installSessionCookie(nil, expires: nil)
        } else if mode == "verify-clear" {
            Api.installSessionCookie("owned-synthetic-session", expires: Date().addingTimeInterval(3600))
            require(LedgerCache.load() == nil, "logout ledger removal persists")
            Api.accountUser = user
            require(TransactionJournal.begin(path: "api/adjust", body: body, proposed: "after-clear-id") == "after-clear-id", "logout pending removal persists")
            require(Snapshot.load().updated == .distantPast, "logout snapshot empty persists")
            TransactionJournal.clear()
            Api.installSessionCookie(nil, expires: nil)
        } else { throw NSError(domain: "invalid storage phase", code: 1) }
    }
}
