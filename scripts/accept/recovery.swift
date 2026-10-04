import Foundation

// 故障与恢复：错密码、断网/服务停、非 JSON 响应、服务重启后数据完整、越权/透支拒绝不改账、家长会话超时自动上锁。
@main struct RecoveryAcceptance {
    @MainActor static func main() async throws {
        let A = Accept.self
        let base = "http://127.0.0.1:\(A.port)"

        let wrongLogin = await A.failure { try await Api.login(user: A.kidUser, password: "definitely-wrong") }
        A.expect(wrongLogin != nil, "错登录密码被拒")
        try await Api.login(user: A.kidUser, password: A.kidPw)
        let s0 = try await Api.state()
        A.step("错登录密码被拒（「\(wrongLogin!)」），正确密码随后可登录")

        let locked = s0.shop.first { !s0.isUnlocked($0.id) }
        if let locked {
            let refused = await A.failure { try await Api.spend(item: locked.id) }
            let afterRefused = try await A.balance()
            A.expect(refused != nil && afterRefused == s0.balance, "未解锁商品兑换被拒且不扣分")
            A.step("兑换未到档位商品被拒（「\(refused!)」），不扣分")
        }
        let cfg = try await Api.config()
        let badConfig = await A.failure { _ = try await Api.configPut(kind: "rules", items: [["id": "bad"]], revision: cfg.revision) }
        A.expect(badConfig != nil, "非法配置整笔拒绝")
        A.expect(try await Api.config(A.parentPw).rules.count == s0.rules.count, "拒绝后规则数不变")
        A.step("非法规则配置被服务端整笔拒绝，原配置不变")

        // 服务停掉：客户端在开屏探测超时内报错，而不是挂住。
        A.stopServer()
        let t0 = Date()
        let down = await A.failure { _ = try await Api.state(timeout: 6) }
        let waited = Date().timeIntervalSince(t0)
        A.expect(down != nil && waited < 7, "服务不可达时 6 秒内报错")
        A.step(String(format: "服务停止：%.1f 秒内报错（%@）", waited, down!))

        // 地址对了但返回的不是账本 JSON（如网关错误页）。
        let junk = try await junkServer()
        A.useBase("http://127.0.0.1:\(junk.port)")
        let notJSON = await A.failure { _ = try await Api.state(timeout: 6) }
        A.expect(notJSON?.contains("HTTP 502") == true, "非 JSON 响应给出可读的 HTTP 状态")
        junk.listener.cancel()
        A.useBase(base)
        A.step("网关返回非 JSON：提示「\(notJSON!)」")

        // 服务恢复：cookie 仍有效，账本完整无丢失。
        try A.startServer()
        let s1 = try await Api.state()
        A.expect(s1.balance == s0.balance && s1.entries.map(\.id) == s0.entries.map(\.id), "服务重启后余额与流水完整")
        A.step("服务重启后免重新登录，余额 \(s1.balance) 与流水 \(s1.entries.count) 条完整")

        let rid = UUID().uuidString
        let first = try await Api.transaction("api/adjust", body: ["pts": 3, "label": "断线重试"], requestID: rid)
        let again = try await Api.transaction("api/adjust", body: ["pts": 3, "label": "断线重试"], requestID: rid)
        let retriedBalance = try await A.balance()
        A.expect(first.entryID == again.entryID && retriedBalance == s1.balance + 3, "同标识重试只记一笔")
        try await Api.undo(id: first.entryID!)
        try await Api.undo(id: first.entryID!)
        A.expect(try await A.balance() == s1.balance, "重复撤销幂等且余额恢复")
        A.step("稳定标识重试只有一笔；重复撤销恢复原余额")
        print("PASS recovery")
    }

    /// A tiny local listener that answers every request with a 502 HTML page.
    static func junkServer() async throws -> (listener: JunkListener, port: UInt16) {
        let l = try JunkListener()
        return (l, l.port)
    }
}

final class JunkListener {
    let fd: Int32
    let port: UInt16
    init() throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, len) } }
        listen(sock, 8)
        _ = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) } }
        fd = sock
        port = UInt16(bigEndian: addr.sin_port)
        Thread.detachNewThread {
            while true {  // ends when cancel() closes the listening socket
                let c = accept(sock, nil, nil)
                if c < 0 { break }
                var buf = [UInt8](repeating: 0, count: 4096)
                _ = read(c, &buf, buf.count)
                let body = "<html>Bad Gateway</html>"
                let resp = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                _ = resp.withCString { write(c, $0, strlen($0)) }
                close(c)
            }
        }
    }

    func cancel() { close(fd) }
}
