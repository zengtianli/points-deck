import Foundation
#if os(iOS)
import WatchConnectivity
#endif

/// iPhone → Apple Watch 的登录态转交。
///
/// 手表上没有键盘可登录，所以由 iPhone 在登录 / 恢复 / 注册成功后把会话 cookie 递过去，
/// 退出 / 注销时递一份**不带 cookie** 的上下文，手表随即删掉。
/// 走 `updateApplicationContext`：只保留最新一份，手表下次启动时就能读到，iPhone 不用开着。
/// 上下文里带上账本地址：iPhone 指着本地验证服务时，手表若指着线上，就不装这枚 cookie ——
/// 不能把一个账本的会话拿去敲另一个账本的门。
///
/// 手表那头的接收在 Watch/WatchSessionReceiver.swift。iPad、Mac、Vision 上这里全是空操作。
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    /// 上下文里的键 —— 两端只认这几个。
    enum Key {
        static let cookie = "edu_sess"
        static let expires = "expires"
        static let base = "base"
        static let at = "at"
    }

    #if os(iOS)
    /// 激活完成前想发的那一份（激活是异步的，开机就登录时常会赶在它前面）。
    private var pending: [String: Any]?
    /// iPhone 这边当前是否登录着 —— 换表 / 装上手表 app 时只在登录着才补发
    private var signedIn = false

    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        if s.activationState != .activated { s.activate() }
    }

    func publishSession() {
        signedIn = true
        guard let c = Api.sessionCookie() else { return }
        var ctx: [String: Any] = [Key.cookie: c.value, Key.base: Api.base.absoluteString,
                                  Key.at: Date().timeIntervalSince1970]
        if let e = c.expiresDate { ctx[Key.expires] = e.timeIntervalSince1970 }
        send(ctx)
    }

    func publishSignedOut() {
        signedIn = false
        send([Key.base: Api.base.absoluteString, Key.at: Date().timeIntervalSince1970])
    }

    private func send(_ ctx: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated else {
            pending = ctx
            activate()
            return
        }
        pending = nil
        // 没配对手表、或手表上没装本 app 时 WatchConnectivity 会抛错：这是常态，不是故障
        guard s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(ctx)
    }
    #else
    func activate() {}
    func publishSession() {}
    func publishSignedOut() {}
    #endif
}

#if os(iOS)
extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        Task { @MainActor in
            if let p = self.pending { self.send(p) }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// 换了一块手表：旧会话失效，重新激活才能给新手表发
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// 配对或装上手表 app 之后，补发一次当前的登录态
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            guard self.signedIn, session.isPaired, session.isWatchAppInstalled else { return }
            self.publishSession()
        }
    }
}
#endif
