import Foundation
import Security

/// 账本客户端 —— **只发请求，不算分**。
///
/// 分值一律服务端算(~/Apps/edu/web 立的铁律，本 app 继承)：预览也走 /api/preview。
/// 两边各算各的迟早算出不同的数，而家长看到的是预览、孩子拿到的是记账。
/// 所以这个文件里不许出现任何一条规则的分值。
enum Api {
    static var accountUser: String?
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
        var status: Int = 0
        var errorDescription: String? { message }
    }

    /// 服务端发的是 HttpOnly cookie，URLSession 的共享 cookie 存储会自己带上并持久化。
    /// 我们**不碰** cookie 的值 —— 碰了就等于在 app 里复制一份会话状态。
    ///
    /// ⚠ 唯一的例外（2026-10-02 放宽）：Apple Watch。手表上没有输入框可登录，
    /// 由 iPhone 把同一枚 `edu_sess` 经 WatchConnectivity 转过去（`sessionCookie` /
    /// `installSessionCookie`，只在这两处碰值）。转的是同一个会话、不是新造一份：
    /// 服务端的 pwv 机制照样管它 —— 改密码，手表和 iPhone 一起下线；iPhone 退出 / 注销时
    /// 也会发一条不带 cookie 的同步，手表随即删掉。除此之外仍然不读不写 cookie。
    static func request(_ path: String, body: [String: Any]? = nil,
                                timeout: TimeInterval = 20) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: path, relativeTo: Api.base.appendingPathComponent("/"))!.absoluteURL)
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
            throw Failure(message: obj["err"] as? String ?? "账本拒绝了这次请求(HTTP \(code))", status: code)
        }
        return obj
    }

    static func login(user: String, password: String) async throws {
        _ = try await request("api/login", body: ["u": user, "p": password])
    }

    static func state(timeout: TimeInterval = 20, full: Bool = false) async throws -> LedgerState {
        let json = try await request(full ? "api/state?all=1" : "api/state", timeout: timeout)
        accountUser = json["u"] as? String
        LedgerCache.save(json)
        return try LedgerState(json: json)
    }

    /// 预览 —— **和记账走的是服务端同一个 compute()**，这里只发规则和输入。
    static func preview(_ input: RuleInput) async throws -> Preview {
        let o = try await request("api/preview", body: input.body())
        return Preview(pts: o["pts"] as? Int ?? 0,
                       label: o["label"] as? String ?? "",
                       cur: o["cur"] as? String ?? "pts",
                       why: o["why"] as? String ?? "")
    }

    /// 请求标识由一次用户操作持有，网络失败后核对原请求，重试不生成新交易。
    static func transaction(_ path: String, body: [String: Any], requestID: String) async throws -> Transaction {
        var payload = body
        let journalID = TransactionJournal.begin(path: path, body: body, proposed: requestID)
        payload["request_id"] = journalID
        do {
            let result = try await request(path, body: payload)
            TransactionJournal.finish(path: path, body: body)
            return Transaction(json: result)
        } catch let error as URLError {
            let result = try await request("api/request_result", body: ["request_id": journalID])
            if result["found"] as? Bool == true { TransactionJournal.finish(path: path, body: body); return Transaction(json: result) }
            throw error
        } catch let failure as Failure {
            if failure.status > 0 && failure.status < 500 { TransactionJournal.finish(path: path, body: body) }
            throw failure
        }
    }

    static func earn(_ input: RuleInput, admin: String = "", note: String = "") async throws -> String? {
        var body = input.body()
        body["note"] = note
        let receipt = try await transaction("api/earn", body: body, requestID: UUID().uuidString)
        return receipt.entryID == nil ? receipt.message : nil
    }

    static func adjust(pts: Int, label: String, admin: String = "") async throws {
        _ = try await transaction("api/adjust", body: ["pts": pts, "label": label], requestID: UUID().uuidString)
    }

    static func undo(id: String, admin: String = "") async throws {
        _ = try await request("api/undo", body: ["id": id])
    }

    static func spend(item: String) async throws {
        _ = try await transaction("api/spend", body: ["item": item], requestID: UUID().uuidString)
    }

    static func profile(nick: String? = nil, emoji: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let nick { body["nick"] = nick }
        if let emoji { body["emoji"] = emoji }
        _ = try await request("api/profile", body: body)
    }

    static func config(_ legacyPassword: String = "") async throws -> Config {
        Config(json: try await request("api/config", body: [:]))
    }

    @discardableResult
    static func configPut(_ legacyPassword: String = "", kind: String,
                          items: [[String: Any]], revision: String) async throws -> String {
        let result = try await request("api/config_put", body: ["kind": kind, "items": items, "revision": revision])
        return result["revision"] as? String ?? ""
    }

    static func sendCode(email: String, purpose: String, password: String = "", identityGrant: String = "") async throws -> String {
        let response = try await request("api/email_send", body: ["email": email, "purpose": purpose, "password": password, "identity_grant": identityGrant])
        return response["challenge"] as? String ?? ""
    }

    static func verifyCode(challenge: String, code: String) async throws -> String {
        let response = try await request("api/email_verify", body: ["challenge": challenge, "code": code])
        return response["grant"] as? String ?? ""
    }

    /// 实时推送 —— 一条 SSE 长连接。收到事件只表示「有东西变了」，
    /// 拿到信号去 `/api/state` 拉一次完整状态，**不从推送里读数据**：
    /// 推数据等于多一条下发路径，两条路给出不同答案时根本查不清谁对。
    ///
    /// `URLSession.bytes` 给的是逐字节的异步序列，按行解析即可。
    /// 断线由调用方决定怎么重连（这里不自己重试 —— 重试策略是 Store 的事）。
    static func events() async throws -> AsyncThrowingStream<String, Error> {
        var req = URLRequest(url: base.appendingPathComponent("api/events"))
        req.timeoutInterval = 0                 // 长连接：不能有超时，否则每 N 秒被自己掐断
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure(message: "推送连不上(HTTP \(code))") }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        // `event: ledger` / `event: config`；`: ping` 是心跳，忽略
                        if line.hasPrefix("event:") {
                            continuation.yield(String(line.dropFirst(6))
                                .trimmingCharacters(in: .whitespaces))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func logout() async {
        _ = try? await request("api/logout", body: [:])
    }

    /// 会话 cookie 的名字（server.py 发的那枚 HttpOnly cookie）。
    static let sessionCookieName = "edu_sess"

    /// 当前账本地址下的会话 cookie —— **只给 iPhone 转交 Apple Watch 用**（见 `request` 上方的例外）。
    static func sessionCookie() -> HTTPCookie? {
        HTTPCookieStorage.shared.cookies(for: base)?.first { $0.name == sessionCookieName }
    }

    /// 手表装上 iPhone 转来的会话 cookie；`value` 为 nil 就只删不装（iPhone 退出 / 注销了）。
    /// 装在手表自己的账本地址下，之后 `request` 原样由 URLSession 带上，别处不用改。
    static func installSessionCookie(_ value: String?, expires: Date?) {
        let jar = HTTPCookieStorage.shared
        for c in jar.cookies(for: base) ?? [] where c.name == sessionCookieName { jar.deleteCookie(c) }
        guard let value, !value.isEmpty, let host = base.host else { return }
        var props: [HTTPCookiePropertyKey: Any] = [.name: sessionCookieName, .value: value,
                                                   .domain: host, .path: "/"]
        if base.scheme == "https" { props[.secure] = "TRUE" }
        if let expires { props[.expires] = expires }
        if let c = HTTPCookie(properties: props) { jar.setCookie(c) }
    }

    static func register(email: String, password: String, nick: String, grant: String) async throws {
        _ = try await request("api/register", body: ["email": email, "p": password, "nick": nick, "grant": grant])
    }

    /// 自助注销：要当前密码；服务端把账本/存档整体归档后清 cookie。
    static func deleteAccount(password: String) async throws {
        _ = try await request("api/account_del", body: ["p": password])
    }
}

/// 可编辑配置的投影 —— 管理面用。
struct Config {
    var revision: String
    var subjects: [LedgerState.Subject]
    var rules: [[String: Any]]      // 保持原始字典：规则的字段随 kind 变，
    var shop: [[String: Any]]       // 强类型化会在「服务端加了个字段」时把它吃掉
    var tiers: [[String: Any]]
    var eras: [String: String]

    init(json: [String: Any]) {
        revision = json["revision"] as? String ?? ""
        subjects = ((json["subjects"] as? [[String: Any]]) ?? []).map {
            LedgerState.Subject(id: $0["k"] as? String ?? "",
                          name: $0["name"] as? String ?? "",
                          icon: $0["icon"] as? String ?? "")
        }
        rules = (json["rules"] as? [[String: Any]]) ?? []
        shop = (json["shop"] as? [[String: Any]]) ?? []
        tiers = (json["tiers"] as? [[String: Any]]) ?? []
        eras = (json["eras"] as? [String: String]) ?? [:]
    }
}

/// `/api/state` 的投影 —— 只取第一屏真用得上的字段。
/// 用不上的(rules/subjects/shop/calcs)先不解析：解析了就得维护，而它们要等家长面才用。
struct LedgerState {
    let user: String
    let total: Int
    let revision: String
    let nick: String
    let balance: Int
    let rate: Int          // 多少分 = 1 元
    let tv: Int            // 电视时间(分钟)
    let houseName: String
    let houseAt: Int
    let tier: Int
    let era: Era
    let nextName: String?
    let nextAt: Int?
    let entries: [Entry]
    let subjects: [Subject]
    let rules: [Rule]
    let calcs: [String: Calc]
    let shop: [ShopItem]
    let practiceLeft: Int
    /// 整条家园阶梯（含每档权益）—— 等级总览页要把 11 档全摊开。
    /// ⚠ 阈值与权益的 SSOT 在 ~/Apps/edu/web/points/skins/skins.json，这里只是它的投影。
    /// **不许在端上补一份**：加一档、改一个红包数，端上什么都不用动。
    let ladder: [Tier]
    /// 当前已解锁的商品 id。服务端算的 —— 端上藏按钮只是观感，
    /// 真正拦住的是 /api/spend 里那道门。
    let unlocked: Set<String>
    let avatar: String
    /// 可选头像 —— 服务端下发，端上不写第二份
    let avatarChoices: [String]

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
        var kind: String = ""
        var isRedemption: Bool { kind == "spend" }

        /// 流水金额的显示：三种币种走同一条时间线(服务端如此)，所以单位要跟着条目走，不能一律写「分」。
        var signed: String {
            let unit = cur == "tv" ? " 分钟" : (cur == "wish" ? " 次" : "")
            return (pts >= 0 ? "+" : "") + "\(pts)" + unit
        }
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
        var icon: String = "star.fill"
        var color: String = "mint"
        var archived: Bool = false
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

    /// 一档家园 + 它的权益。
    struct Tier: Identifiable, Hashable {
        let at: Int
        let name: String
        let era: Era
        let bonus: Int          // 升到这一档一次性到账
        let unlock: [String]    // 这一档解锁的 shop id
        var id: Int { at }
    }

    struct ShopItem: Identifiable, Hashable {
        let id: String
        let icon: String
        let label: String
        let pts: Int
        var archived: Bool = false
        var detail: String = ""
    }

    init(json: [String: Any]) throws {
        guard let house = json["house"] as? [String: Any] else {
            throw Api.Failure(message: "账本没返回 house —— 服务端版本对不上")
        }
        user = json["u"] as? String ?? ""
        total = json["total"] as? Int ?? (json["entries"] as? [Any])?.count ?? 0
        revision = json["config_revision"] as? String ?? ""
        nick = json["nick"] as? String ?? user
        balance = json["balance"] as? Int ?? 0
        rate = json["rate"] as? Int ?? 100
        tv = json["tv"] as? Int ?? 0
        houseName = house["name"] as? String ?? "—"
        houseAt = house["at"] as? Int ?? 0
        tier = house["tier"] as? Int ?? 0
        era = Era(key: house["era"] as? String ?? "")
        let nxt = house["next"] as? [String: Any]
        nextName = nxt?["name"] as? String
        nextAt = nxt?["at"] as? Int
        // ⚠ 字段名是照着 server.py 的真实写入(第 498-504 行)对的，不是猜的 ——
        // 第一版猜了 what/t，跑出来整列事由全是「—」而进度条一切正常，界面看着毫无异样。
        entries = ((json["entries"] as? [[String: Any]]) ?? []).reversed().map { e in
            Entry(id: (e["id"] as? String) ?? UUID().uuidString,
                  what: (e["label"] as? String) ?? "—",
                  pts: (e["pts"] as? Int) ?? 0,
                  cur: (e["cur"] as? String) ?? "pts",
                  when: (e["day"] as? String) ?? "",
                  note: (e["note"] as? String) ?? "",
                  bal: (e["bal"] as? Int) ?? 0, kind: e["kind"] as? String ?? "")
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
                 calc: $0["calc"] as? String, icon: $0["icon"] as? String ?? "star.fill",
                 color: $0["color"] as? String ?? "mint", archived: $0["archived"] as? Bool ?? false)
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
                     label: $0["label"] as? String ?? "", pts: $0["pts"] as? Int ?? 0,
                     archived: $0["archived"] as? Bool ?? false, detail: $0["description"] as? String ?? "")
        }
        practiceLeft = json["practice_left"] as? Int ?? 0
        ladder = ((json["ladder"] as? [[String: Any]]) ?? []).map {
            Tier(at: $0["at"] as? Int ?? 0,
                 name: $0["name"] as? String ?? "",
                 era: Era(key: $0["era"] as? String ?? ""),
                 bonus: $0["bonus"] as? Int ?? 0,
                 unlock: ($0["unlock"] as? [String]) ?? [])
        }
        unlocked = Set((json["unlocked"] as? [String]) ?? [])
        // 头像：服务端发的是 {k, v}，k=preset 时 v 是 emoji，k=img 时要另外拉图。
        // 这一版只认 emoji —— 上传头像还没接，认了也画不出来。
        let av = json["avatar"] as? [String: Any]
        avatar = (av?["k"] as? String) == "img" ? "🖼" : ((av?["v"] as? String) ?? "🐯")
        avatarChoices = (json["avatars"] as? [String]) ?? []
    }

    /// 这一档是否已经解锁了某商品。
    func isUnlocked(_ itemID: String) -> Bool { unlocked.contains(itemID) }

    /// 某商品要住进哪一档才换得了 —— 兑换页上锁着的那行字。
    func tierRequiring(_ itemID: String) -> Tier? {
        ladder.first { $0.unlock.contains(itemID) }
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
    let rule: LedgerState.Rule
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

struct Transaction {
    let entryID: String?
    let message: String
    init(json: [String: Any]) {
        let entry = json["entry"] as? [String: Any]
        entryID = entry?["id"] as? String
        if let entry, let pts = entry["pts"] as? Int {
            let unit = entry["cur"] as? String == "tv" ? "分钟" : entry["cur"] as? String == "wish" ? "个心愿" : "分"
            message = "\(entry["label"] as? String ?? "记录") \(pts >= 0 ? "+" : "")\(pts) \(unit)，已记入账本"
        } else { message = json["why"] as? String ?? "本次未产生流水" }
    }
}

/// 最近一次成功回读的账本，保存在本设备钥匙串；退出、注销和 401 同步清除。
enum LedgerCache {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "cyou.tianli.pointsdeck.ledger-cache",
         kSecAttrAccount as String: Api.base.absoluteString]
    }
    static func save(_ json: [String: Any]) {
        guard Api.base.scheme == "https" else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            SecItemAdd(add as CFDictionary, nil)
        }
    }
    static func load() -> LedgerState? {
        guard Api.sessionCookie() != nil else { return nil }
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        Api.accountUser = json["u"] as? String
        return try? LedgerState(json: json)
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

/// 未确认交易保留稳定标识；重启后再次提交同一输入仍查询同一笔。只保存记分输入，无凭据。
enum TransactionJournal {
    private static var query: [String: Any]? {
        guard Api.base.scheme == "https", let user = Api.accountUser else { return nil }
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "cyou.tianli.pointsdeck.pending",
                kSecAttrAccount as String: Api.base.absoluteString + ":" + user]
    }
    private static func key(_ path: String, _ body: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["path": path, "body": body], options: .sortedKeys)) ?? Data()
        return data.base64EncodedString()
    }
    private static func load() -> [String: String] {
        guard var q = query else { return [:] }
        q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }
    private static func save(_ values: [String: String]) {
        guard let q = query, let data = try? JSONEncoder().encode(values) else { return }
        var add = q; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound { SecItemAdd(add as CFDictionary, nil) }
    }
    static func begin(path: String, body: [String: Any], proposed: String) -> String {
        var values = load(); let key = key(path, body)
        if let id = values[key] { return id }
        values[key] = proposed; save(values); return proposed
    }
    static func finish(path: String, body: [String: Any]) {
        var values = load(); values.removeValue(forKey: key(path, body)); save(values)
    }
    static func clear() { if let q = query { SecItemDelete(q as CFDictionary) } }
}
