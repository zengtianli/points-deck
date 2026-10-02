import Foundation
import WatchConnectivity

/// 手表这头接 iPhone 递来的登录态（发送端见 Sources/WatchLink.swift）。
///
/// 收到带 cookie 的上下文 → 装进手表自己的 HTTPCookieStorage，之后 `Api.request` 原样带上；
/// 收到不带 cookie 的 → 删掉，回到「在 iPhone 上登录」。
/// 账本地址和手表自己的不一致时整份忽略：不拿一个账本的会话去敲另一个账本的门。
@MainActor
final class WatchSessionReceiver: NSObject, ObservableObject {
    /// 一次登录态变化。带序号：连着两次「登录了」（换了一枚 cookie）也要各触发一次。
    struct Change: Equatable {
        let signedIn: Bool
        let serial: Int
    }

    /// 最近一次登录态变化。界面据此重新拉账本或清空。
    @Published private(set) var change: Change?
    private var serial = 0

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func apply(_ ctx: [String: Any]) {
        guard !ctx.isEmpty else { return }       // 从没收到过任何上下文
        if let base = ctx[WatchLink.Key.base] as? String, base != Api.base.absoluteString { return }
        let value = ctx[WatchLink.Key.cookie] as? String
        let expires = (ctx[WatchLink.Key.expires] as? Double).map { Date(timeIntervalSince1970: $0) }
        Api.installSessionCookie(value, expires: expires)
        serial += 1
        change = Change(signedIn: value?.isEmpty == false, serial: serial)
    }
}

extension WatchSessionReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        guard state == .activated else { return }
        let ctx = session.receivedApplicationContext
        Task { @MainActor in self.apply(ctx) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        Task { @MainActor in self.apply(ctx) }
    }
}
