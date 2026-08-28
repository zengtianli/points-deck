import Foundation

/// 账本客户端 —— **只发请求，不算分**。
///
/// 分值一律服务端算(~/Edu 立的铁律，本 app 继承)：预览也走 /api/preview。
/// 两边各算各的迟早算出不同的数，而家长看到的是预览、孩子拿到的是记账。
/// 所以这个文件里不许出现任何一条规则的分值。
enum Api {
    /// 默认是线上账本。可用 launch 参数指向本地 server 做验证：
    ///   `xcrun simctl launch <udid> cyou.tianli.pointsdeck -api_base http://127.0.0.1:8788`
    /// 走 UserDefaults 而不是 #if DEBUG 的写死地址 —— 写死的那种改一次要重编一次，
    /// 而且很容易连着发版一起漏出去。
    static var base: URL {
        if let s = UserDefaults.standard.string(forKey: "api_base"), let u = URL(string: s) {
            return u
        }
        return URL(string: "https://edu.tianli.cyou")!
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// 服务端发的是 HttpOnly cookie，URLSession 的共享 cookie 存储会自己带上并持久化。
    /// 我们**不碰** cookie 的值 —— 碰了就等于在 app 里复制一份会话状态。
    private static func request(_ path: String, body: [String: Any]? = nil,
                                timeout: TimeInterval = 20) async throws -> [String: Any] {
        var req = URLRequest(url: Api.base.appendingPathComponent(path))
        req.timeoutInterval = timeout
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure(message: code == 200 ? "服务端返回的不是 JSON" : "连不上账本(HTTP \(code))")
        }
        if obj["ok"] as? Bool != true {
            // 服务端的 err 是给人看的中文，原样透出去比包一层「请求失败」有用
            throw Failure(message: obj["err"] as? String ?? "账本拒绝了这次请求(HTTP \(code))")
        }
        return obj
    }

    static func login(user: String, password: String) async throws {
        _ = try await request("api/login", body: ["u": user, "p": password])
    }

    static func state(timeout: TimeInterval = 20) async throws -> State {
        try State(json: await request("api/state", timeout: timeout))
    }

    static func logout() async {
        _ = try? await request("api/logout", body: [:])
    }
}

/// `/api/state` 的投影 —— 只取第一屏真用得上的字段。
/// 用不上的(rules/subjects/shop/calcs)先不解析：解析了就得维护，而它们要等家长面才用。
struct State {
    let user: String
    let nick: String
    let balance: Int
    let rate: Int          // 多少分 = 1 元
    let tv: Int            // 电视时间(分钟)
    let houseName: String
    let houseAt: Int
    let era: Era
    let nextName: String?
    let nextAt: Int?
    let entries: [Entry]

    struct Entry: Identifiable {
        let id: String
        let what: String     // 服务端字段名是 label
        let pts: Int
        let cur: String      // 缺省即 pts —— 服务端只在非 pts 时才写这个键
        let when: String     // day (YYYY-MM-DD)
        let note: String     // 「（开局模拟）」之类的后缀
    }

    init(json: [String: Any]) throws {
        guard let house = json["house"] as? [String: Any] else {
            throw Api.Failure(message: "账本没返回 house —— 服务端版本对不上")
        }
        user = json["u"] as? String ?? ""
        nick = json["nick"] as? String ?? user
        balance = json["balance"] as? Int ?? 0
        rate = json["rate"] as? Int ?? 100
        tv = json["tv"] as? Int ?? 0
        houseName = house["name"] as? String ?? "—"
        houseAt = house["at"] as? Int ?? 0
        era = Era(key: house["era"] as? String ?? "")
        let nxt = house["next"] as? [String: Any]
        nextName = nxt?["name"] as? String
        nextAt = nxt?["at"] as? Int
        // ⚠ 字段名是照着 server.py 的真实写入(第 498-504 行)对的，不是猜的 ——
        // 第一版猜了 what/t，跑出来整列事由全是「—」而进度条一切正常，界面看着毫无异样。
        entries = ((json["entries"] as? [[String: Any]]) ?? []).reversed().prefix(30).map { e in
            Entry(id: (e["id"] as? String) ?? UUID().uuidString,
                  what: (e["label"] as? String) ?? "—",
                  pts: (e["pts"] as? Int) ?? 0,
                  cur: (e["cur"] as? String) ?? "pts",
                  when: (e["day"] as? String) ?? "",
                  note: (e["note"] as? String) ?? "")
        }
    }

    /// 「还差 N 分升级到 X」—— 核心机制，永远在第一屏内。
    var toNext: Int? { nextAt.map { max(0, $0 - balance) } }

    /// 当前档内的进度 0…1。顶档时给满，不给 0(顶档不该看起来像刚起步)。
    var progress: Double {
        guard let nextAt else { return 1 }
        let span = nextAt - houseAt
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(balance - houseAt) / Double(span)))
    }

    var yuan: String { String(format: "%.2f", Double(balance) / Double(max(1, rate))) }
}
