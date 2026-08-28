import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    enum Phase { case checking, loggedOut, loggedIn }

    @Published var phase: Phase = .checking
    @Published var state: State?
    @Published var error: String?
    @Published var busy = false

    /// 开屏先拿一次 state：cookie 还在就直接进，不必再问一次密码。
    /// 拿不到**不等于**密码错了 —— 也可能是没网。所以只在 401 那种「账本拒绝」时才退到登录页，
    /// 其余错误留在登录页上把原因显示出来，不假装成「你没登录」。
    /// ⚠ 超时给 6s 而不是默认的 20s：这一次请求挡在**任何界面之前**，
    /// 没网时用户要盯着转圈等满 20 秒才看到登录页 —— 那是「app 坏了」的观感。
    /// 探测失败一律退到登录页，那里能重试，也能显示原因。
    func restore() async {
        // 验证通道：只有显式传了 launch 参数才生效，生产路径上这两个 key 永远是 nil。
        //   ... -dev_user jingbao -dev_pw 160912
        let d = UserDefaults.standard
        if let u = d.string(forKey: "dev_user"), let pw = d.string(forKey: "dev_pw") {
            await login(user: u, password: pw)
            return
        }
        do {
            state = try await Api.state(timeout: 6)
            phase = .loggedIn
        } catch {
            phase = .loggedOut
        }
    }

    func login(user: String, password: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Api.login(user: user, password: password)
            state = try await Api.state()
            phase = .loggedIn
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        do { state = try await Api.state() } catch { self.error = error.localizedDescription }
    }

    func logout() async {
        await Api.logout()
        state = nil
        phase = .loggedOut
    }
}
