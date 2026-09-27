import Foundation

// 功能：登录 → 首屏状态 → 服务端预览 → 家长解锁 → 记一笔 → 撤销 → 兑换 → 改昵称 → 实时推送 → 退出。
@main struct FunctionalityAcceptance {
    @MainActor static func main() async throws {
        let A = Accept.self
        try await Api.login(user: A.kidUser, password: A.kidPw)
        let s0 = try await Api.state()
        A.expect(s0.user == A.kidUser && s0.balance > 0, "登录后拿到本人账本且余额为正")
        A.expect(!s0.entries.isEmpty && s0.entries.allSatisfy { $0.what != "—" && !$0.when.isEmpty },
                 "流水字段按服务端 label/day 解析（不出现「—」）")
        A.expect(s0.entries.first?.bal == s0.balance, "最新流水余额快照 = 账本余额（走势读 bal，不在端上累加）")
        A.expect(s0.ladder.count >= 5 && !s0.houseName.isEmpty && s0.houseName != "—", "档位阶梯与当前房子来自服务端")
        A.expect(s0.nextAt == nil || s0.toNext == max(0, s0.nextAt! - s0.balance), "还差 N 分升级 = 下一档阈值 - 余额")
        A.step("登录并读取首屏：余额 \(s0.balance)、\(s0.houseName)、流水 \(s0.entries.count) 条、阶梯 \(s0.ladder.count) 档")

        guard let rule = A.fixedRule(s0) else { A.expect(false, "服务端规则里有固定加分项"); return }
        let preview = try await Api.preview(RuleInput(rule: rule))
        A.expect(preview.pts > 0, "服务端预览给出正分值")
        A.step("服务端预览「\(rule.label)」= \(preview.pts) \(preview.cur)")

        let session = ParentSession()
        try await session.unlock(password: A.parentPw)
        A.expect(session.isUnlocked, "家长密码经只读接口验过后解锁")
        A.expect(try await A.balance() == s0.balance, "解锁本身不产生流水")
        A.step("家长会话解锁（只读 /api/config 验证，未记账）")

        let skipped = try await Api.earn(RuleInput(rule: rule), admin: session.password!)
        A.expect(skipped == nil, "记账未被跳过")
        session.noteEarned()
        let s1 = try await Api.state()
        let delta = preview.cur == "pts" ? preview.pts : 0
        A.expect(s1.balance == s0.balance + delta, "记账后余额 = 原余额 + 预览分值（预览与记账同一算法）")
        A.expect(s1.entries.first?.what.contains(rule.label) == true || s1.entries.first?.what == preview.label,
                 "最新流水就是刚记的这笔")
        A.step("解锁状态记一笔：余额 \(s0.balance) → \(s1.balance)，会话计数 \(session.count)")

        try await Api.undo(id: s1.entries.first!.id, admin: session.password!)
        A.expect(try await A.balance() == s0.balance, "撤销后余额回到原值")
        A.step("撤销最近一笔：余额回到 \(s0.balance)")

        let s2 = try await Api.state()
        if let item = s2.shop.filter({ s2.isUnlocked($0.id) && $0.pts <= s2.balance }).min(by: { $0.pts < $1.pts }) {
            try await Api.spend(item: item.id)
            A.expect(try await A.balance() == s2.balance - item.pts, "兑换按商品价扣分")
            A.step("兑换已解锁商品「\(item.label)」扣 \(item.pts) 分（无需家长密码）")
        } else {
            A.expect(false, "种子账本至少有一个已解锁且买得起的商品")
        }

        try await Api.profile(nick: "验收昵称")
        A.expect(try await Api.state().nick == "验收昵称", "改昵称回读一致")
        A.step("修改昵称并回读")

        // 实时推送：开一条 SSE，家长加分后应收到 ledger 事件（数据仍回 /api/state 取）。
        let stream = try await Api.events()
        let got = Task { () -> String? in
            for try await kind in stream where kind == "ledger" { return kind }
            return nil
        }
        try await Task.sleep(for: .milliseconds(300))
        try await Api.adjust(pts: 1, label: "验收推送", admin: session.password!)
        let timeout = Task { try await Task.sleep(for: .seconds(8)); got.cancel() }
        let kind = try? await got.value
        timeout.cancel()
        A.expect(kind == "ledger", "家长加分后 8 秒内收到 ledger 推送")
        A.step("实时推送：家长加分后收到 ledger 事件")

        session.lock()
        A.expect(!session.isUnlocked && session.password == nil, "上锁后内存中不再有家长密码")
        await Api.logout()
        A.expect(await A.failure { _ = try await Api.state() } != nil, "退出登录后读取账本被拒")
        A.step("上锁并退出登录：账本不可再读")
        print("PASS functionality")
    }
}
