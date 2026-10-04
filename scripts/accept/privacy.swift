import Foundation

// 实际 Swift API 对隔离账号验证登录门、跨户读写和站点管理边界。
@main struct PrivacyAcceptance {
    @MainActor static func main() async throws {
        let A = Accept.self
        A.expect(await A.failure { _ = try await Api.state() } != nil, "未登录读取被拒")
        A.step("未登录读不到账本")
        try await Api.login(user: A.kidUser, password: A.kidPw)
        let original = try await Api.state()
        let cfg = try await Api.config()
        A.expect(cfg.revision.count > 0, "登录即可取得家庭配置与版本")
        await Api.logout()
        try await Api.login(user: "otherfamily", password: "another long unique phrase")
        let other = try await Api.state()
        A.expect(other.balance == 0 && Set(original.entries.map(\.id)).intersection(other.entries.map(\.id)).isEmpty, "两户账本隔离")
        A.expect(await A.failure { try await Api.undo(id: original.entries.first!.id) } != nil, "不能撤销另一户流水")
        A.expect(await A.failure { _ = try await Api.request("api/passwd_reset", body: ["user": A.kidUser, "new": "unauthorized", "admin": A.parentPw]) } != nil, "普通账号不能取得站点管理权限")
        try await Api.adjust(pts: 5, label: "本户记录")
        A.expect(try await A.balance() == 5, "普通家长直接记本户账")
        A.step("普通账号可直接记本户账；跨户撤销和站点重置被拒")
        await Api.logout()
        try await Api.login(user: A.kidUser, password: A.kidPw)
        let back = try await Api.state()
        A.expect(back.balance == original.balance && back.entries.map(\.id) == original.entries.map(\.id), "另一户记账不影响本户")
        A.step("重新登录原账号，余额与流水完整")
        await Api.logout()
        print("PASS privacy")
    }
}
