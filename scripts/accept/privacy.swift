import Foundation

// 隐私边界：未登录读不到账本；家长权限不能靠登录态或别家密码取得；两个账号的账本互不可见；
// 家长密码只在会话内存里，上锁/新会话即消失（run.sh 另查客户端 HOME 无密码明文落盘）。
@main struct PrivacyAcceptance {
    @MainActor static func main() async throws {
        let A = Accept.self

        let anon = await A.failure { _ = try await Api.state() }
        A.expect(anon != nil, "未登录读取账本被拒")
        A.step("未登录读取账本被拒（「\(anon!)」）")

        try await Api.login(user: A.kidUser, password: A.kidPw)
        let s0 = try await Api.state()
        guard let rule = A.fixedRule(s0) else { A.expect(false, "有固定加分规则"); return }
        let noAdminEarn = await A.failure { _ = try await Api.earn(RuleInput(rule: rule), admin: "") }
        let noAdminAdjust = await A.failure { try await Api.adjust(pts: 100, label: "越权", admin: "") }
        let noAdminUndo = await A.failure { try await Api.undo(id: s0.entries.first!.id, admin: "") }
        let noAdminConfig = await A.failure { _ = try await Api.config("") }
        let after = try await A.balance()
        A.expect(noAdminEarn != nil && noAdminAdjust != nil && noAdminUndo != nil && noAdminConfig != nil,
                 "只有登录态（孩子账号）时记账/调分/撤销/读配置全部被拒")
        A.expect(after == s0.balance, "越权尝试后余额不变")
        A.step("孩子登录态下无家长密码：记账、调分、撤销、读配置 4 类请求全部被拒，余额不变")

        // 另一户：邮箱注册的新账号，有自己的家长密码。
        await Api.logout()
        let otherParent = "other-parent-\(UUID().uuidString.prefix(8))"
        try await Api.register(email: "accept-\(UUID().uuidString.prefix(8))@example.invalid",
                               password: "other-\(UUID().uuidString.prefix(8))", nick: "另一户", parent: otherParent)
        let other = try await Api.state()
        A.expect(other.user != s0.user && other.balance == 0, "新账号从 0 分起步，不是第一户的账本")
        let seen = Set(s0.entries.map(\.id)).intersection(other.entries.map(\.id))
        A.expect(seen.isEmpty, "新账号看不到第一户的任何流水")
        let crossParent = await A.failure { _ = try await Api.earn(RuleInput(rule: rule), admin: A.parentPw) }
        A.expect(crossParent != nil, "第一户的家长密码不能给另一户记账")
        let crossUndo = await A.failure { try await Api.undo(id: s0.entries.first!.id, admin: otherParent) }
        A.expect(crossUndo != nil, "另一户不能撤销第一户的流水")
        A.step("两户隔离：新账号 0 分、看不到第一户 \(s0.entries.count) 条流水；跨户家长密码与跨户撤销均被拒")

        await Api.logout()
        try await Api.login(user: A.kidUser, password: A.kidPw)
        let back = try await Api.state()
        A.expect(back.balance == s0.balance && back.entries.map(\.id) == s0.entries.map(\.id), "第一户账本未被另一户改动")
        A.step("第一户账本未被另一户改动")

        let session = ParentSession()
        try await session.unlock(password: A.parentPw)
        A.expect(session.isUnlocked, "正确家长密码可解锁")
        session.lock()
        A.expect(session.password == nil && !ParentSession().isUnlocked, "上锁后密码清空，新会话默认上锁")
        A.step("家长密码只在会话内存：上锁即清空，新会话默认上锁")
        await Api.logout()
        print("PASS privacy")
    }
}
