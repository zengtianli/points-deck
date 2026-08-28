import SwiftUI

/// 家长解锁会话 —— 用户 2026-08-28 钦定：
/// 「就不要 faceid，就是打开密码 解锁 加分项目，全部选完，关闭解锁。就这样。干干净净。」
///
/// 所以这里**不是**「记住密码」，是一段**有始有终的会话**：
///   输一次密码 → 解锁 → 连着记若干笔（不再问）→ 手动关闭 → 密码从内存消失
///
/// 三条硬约束，删一条这东西就变味：
/// ① 密码只在**内存**里。不进 Keychain、不进 UserDefaults、不进文件。
///    进程一死就没了 —— 所以「孩子拿到手机」时它必然是锁着的。
/// ② 切后台超过 `idleLimit` 自动上锁。家长解锁完随手把手机放桌上，
///    这是最现实的泄漏场景，比「被猜到密码」现实得多。
/// ③ 服务端语义不变：每次记账仍然**带着密码发一次**（~/Edu 的「管理密码不发 cookie」
///    是有意的）。变的只是密码从内存拿，而不是每次弹框问。
@MainActor
final class ParentSession: ObservableObject {
    /// 解锁着的时候才有值。nil = 锁着。
    @Published private(set) var password: String?
    /// 本次会话记了几笔 —— 顶栏那句「已记 N 笔」，让家长知道自己在会话里。
    @Published private(set) var count = 0

    var isUnlocked: Bool { password != nil }

    /// 切后台多久自动上锁。10 分钟：短到「放桌上就锁」，长到不会打断一次连续记账。
    private static let idleLimit: TimeInterval = 600
    private var leftAt: Date?

    /// 解锁。**密码对不对不在这里判** —— 判它的唯一权威是服务端，
    /// 所以调用方先拿这个密码真记一笔，成了才调 `unlock`。
    /// 这样不会出现「本地觉得对、服务端一直拒」那种最难查的错。
    func unlock(_ pw: String) {
        password = pw
        count = 0
        leftAt = nil
    }

    func noteEarned() { count += 1 }

    /// 独立解锁 —— 拿一个**只读**接口去验密码，验过才置位。
    ///
    /// 这个方法补的是一个设计缺陷：原先 `askPassword` 只在「记这一笔」里触发，
    /// 意味着**想单纯解锁一下必须先凑一笔账出来**。找不到的入口等于没有 ——
    /// 用户第一句话就是「怎么解锁家长模式？」，那就是入口不成立的证据。
    func unlock(password pw: String) async throws {
        try await Api.verifyParent(pw)      // 密码对不对只有服务端说了算，本地不判
        unlock(pw)
    }

    func lock() {
        password = nil
        count = 0
        leftAt = nil
    }

    /// 切到后台记一下时刻；回前台时超时就锁。
    func scenePhaseChanged(to phase: ScenePhase) {
        guard isUnlocked else { return }
        switch phase {
        case .active:
            if let t = leftAt, Date().timeIntervalSince(t) > Self.idleLimit { lock() }
            leftAt = nil
        case .background, .inactive:
            if leftAt == nil { leftAt = Date() }
        @unknown default:
            break
        }
    }
}
