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

    /// 预览 —— **和记账走的是服务端同一个 compute()**，这里只发规则和输入。
    static func preview(_ input: RuleInput) async throws -> Preview {
        let o = try await request("api/preview", body: input.body())
        return Preview(pts: o["pts"] as? Int ?? 0,
                       label: o["label"] as? String ?? "",
                       cur: o["cur"] as? String ?? "pts",
                       why: o["why"] as? String ?? "")
    }

    /// 记一笔。admin 是**每次现取现发**的家长密码，不缓存、不落 cookie。
    static func earn(_ input: RuleInput, admin: String, note: String = "") async throws -> String? {
        var b = input.body()
        b["admin"] = admin
        if !note.isEmpty { b["note"] = note }
        let o = try await request("api/earn", body: b)
        if o["skipped"] as? Bool == true { return o["why"] as? String ?? "这次算下来是 0 分，没记账" }
        return nil
    }

    static func adjust(pts: Int, label: String, admin: String) async throws {
        _ = try await request("api/adjust", body: ["pts": pts, "label": label, "admin": admin])
    }

    /// 撤销 = 服务端直接删(条目挪进 deleted 区留底 + 其后 bal 快照重算)，不是红冲。
    static func undo(id: String, admin: String) async throws {
        _ = try await request("api/undo", body: ["id": id, "admin": admin])
    }

    /// 兑换 —— **不要家长密码**(服务端如此：花的是孩子自己的分)，但不许透支。
    static func spend(item: String) async throws {
        _ = try await request("api/spend", body: ["item": item])
    }

    // ── 错题本 ────────────────────────────────────────────────────────────────
    struct Wrong: Identifiable {
        let id: String
        let at: String
        let subject: String
        let status: String   // new=待录入 / ingested=已进题库(原图已回收)
        let bytes: Int
    }

    static func wrongs() async throws -> [Wrong] {
        let o = try await request("api/wrongs")
        return ((o["items"] as? [[String: Any]]) ?? []).map {
            Wrong(id: $0["id"] as? String ?? "",
                  at: String(($0["at"] as? String ?? "").prefix(16).replacingOccurrences(of: "T", with: " ")),
                  subject: $0["subject"] as? String ?? "",
                  status: $0["status"] as? String ?? "new",
                  bytes: $0["bytes"] as? Int ?? 0)
        }.reversed()
    }

    /// 传一张错题照片。服务端**从真实字节认格式**，所以这里的 mime 前缀只是形式；
    /// 但大小它是真拦的(单张 ≤3MB)，压缩要在端上做完再传。
    static func uploadWrong(jpeg: Data, subject: String, note: String) async throws {
        let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        _ = try await request("api/wrong",
                              body: ["data": dataURL, "subject": subject, "note": note],
                              timeout: 60)
    }

    static func deleteWrong(id: String) async throws {
        _ = try await request("api/wrong_del", body: ["id": id])
    }

    /// 原图 —— 走同一个 URLSession(带 cookie)，服务端只发自己的那些。
    static func wrongImage(id: String) async throws -> Data {
        var req = URLRequest(url: base.appendingPathComponent("api/wrong_img"))
        req.url = URL(string: req.url!.absoluteString + "?id=" + id)
        let (d, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure(message: "取不到这张图")
        }
        return d
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
    let subjects: [Subject]
    let rules: [Rule]
    let calcs: [String: Calc]
    let shop: [ShopItem]
    let practiceLeft: Int

    struct Entry: Identifiable {
        let id: String
        let what: String     // 服务端字段名是 label
        let pts: Int
        let cur: String      // 缺省即 pts —— 服务端只在非 pts 时才写这个键
        let when: String     // day (YYYY-MM-DD)
        let note: String     // 「（开局模拟）」之类的后缀
        /// 服务端记的**余额快照**。撤销时它会被整条重算 —— 所以走势图读它，
        /// 不在端上累加 pts 求余额(累加出来的曲线和服务端的余额迟早对不上)。
        let bal: Int
    }

    struct Subject: Identifiable, Hashable {
        let id: String       // k
        let name: String
        let icon: String
    }

    /// 一条积分规则。**这里没有分值计算，只有「长什么样、要填什么」** ——
    /// pts 字段只用于在列表里给个提示，真数字一律以 /api/preview 的返回为准。
    struct Rule: Identifiable, Hashable {
        let id: String
        let subject: String
        let label: String
        let kind: String     // fixed / per / range / calc / tv
        let pts: Int
        let unit: String
        let hint: String
        let min: Int?
        let max: Int?
        let calc: String?
    }

    struct Calc: Hashable {
        let label: String
        let inputs: [Input]
        struct Input: Hashable, Identifiable {
            let id: String   // k
            let label: String
            let hint: String
        }
    }

    struct ShopItem: Identifiable, Hashable {
        let id: String
        let icon: String
        let label: String
        let pts: Int
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
                  note: (e["note"] as? String) ?? "",
                  bal: (e["bal"] as? Int) ?? 0)
        }
        subjects = ((json["subjects"] as? [[String: Any]]) ?? []).map {
            Subject(id: $0["k"] as? String ?? "", name: $0["name"] as? String ?? "",
                    icon: $0["icon"] as? String ?? "")
        }
        rules = ((json["rules"] as? [[String: Any]]) ?? []).map {
            Rule(id: $0["id"] as? String ?? "",
                 subject: $0["subject"] as? String ?? "",
                 label: $0["label"] as? String ?? "",
                 kind: $0["kind"] as? String ?? "fixed",
                 pts: $0["pts"] as? Int ?? 0,
                 unit: $0["unit"] as? String ?? "",
                 hint: $0["hint"] as? String ?? "",
                 min: $0["min"] as? Int, max: $0["max"] as? Int,
                 calc: $0["calc"] as? String)
        }
        calcs = ((json["calcs"] as? [String: [String: Any]]) ?? [:]).mapValues { c in
            Calc(label: c["label"] as? String ?? "",
                 inputs: ((c["inputs"] as? [[String: Any]]) ?? []).map {
                     Calc.Input(id: $0["k"] as? String ?? "",
                                label: $0["label"] as? String ?? "",
                                hint: String(describing: $0["hint"] ?? ""))
                 })
        }
        shop = ((json["shop"] as? [[String: Any]]) ?? []).map {
            ShopItem(id: $0["id"] as? String ?? "", icon: $0["icon"] as? String ?? "",
                     label: $0["label"] as? String ?? "", pts: $0["pts"] as? Int ?? 0)
        }
        practiceLeft = json["practice_left"] as? Int ?? 0
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


/// 一条规则 + 家长填的输入 → 请求体。
///
/// 键名照着 server.py 的 _compute() 对：
///   fixed {rule} · per {rule,n} · range {rule,pts} · calc {rule,inputs} · tv {rule,n}
/// **这里只组装参数，不算分。**
struct RuleInput {
    let rule: State.Rule
    var n: Int = 0                    // per / tv
    var pts: Int = 0                  // range
    var inputs: [String: String] = [:] // calc

    func body() -> [String: Any] {
        var b: [String: Any] = ["rule": rule.id]
        switch rule.kind {
        case "per", "tv": b["n"] = n
        case "range":     b["pts"] = pts
        case "calc":
            // 服务端的 ast 求值器要数字，空的一律给 0(它会按 else 档判)
            b["inputs"] = inputs.mapValues { Int($0) ?? 0 }
        default: break
        }
        return b
    }

    /// 参数够不够 —— 不够就别去打服务端，也别把「填 0」当成用户的意思。
    var ready: Bool {
        switch rule.kind {
        case "per", "tv": return n > 0
        case "range":     return pts != 0
        case "calc":      return inputs.values.contains { !$0.isEmpty }
        default:          return true
        }
    }
}

struct Preview {
    let pts: Int
    let label: String
    let cur: String
    let why: String
}
