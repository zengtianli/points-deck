import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class Store: ObservableObject {
    enum Phase { case checking, loggedOut, loggedIn }

    @Published var phase: Phase = .checking
    @Published var state: LedgerState?
    @Published var error: String?
    @Published var busy = false

    @Published var notice: String?
    @Published var undoEntryID: String?
    private var noticeTask: Task<Void, Never>?
    func showNotice(_ message: String, entryID: String? = nil) {
        noticeTask?.cancel()
        notice = message; undoEntryID = entryID
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            notice = nil; undoEntryID = nil
        }
    }
    @discardableResult
    func undoEntry(_ id: String) async -> Bool {
        do {
            try await Api.undo(id: id)
            await refresh()
            showNotice("已撤销，账本和走势已恢复")
            return true
        } catch { showNotice("撤销失败：\(error.localizedDescription)"); return false }
    }

    /// 刚刚升档到了哪一档 —— 非 nil 时界面弹「乔迁新居」。
    /// **只庆不罚**：回落一声不吭(~/Apps/edu/web 的规矩，页面本身已经在说话了)。
    @Published var promoted: String?

    /// 上一次看到的档位序号。**存盘而不是只放内存** —— 最常见的升档场景是
    /// 「家长加分时孩子没开着 app，孩子后来才打开」，只放内存的话那一次永远庆祝不了，
    /// 而那恰恰是最该被看见的一次。
    ///
    /// 用序号不用房名：房名可能在 skins.json 里被改字，而序号是位置，改名不会假装成升档。
    private var lastTier: Int? {
        get {
            let d = UserDefaults.standard
            return d.object(forKey: tierKey) as? Int
        }
        set { UserDefaults.standard.set(newValue, forKey: tierKey) }
    }

    private var tierKey: String = "lastTier"

    /// 实时推送的连接任务。**只留一个** —— 每次登录/回前台都新建一条的话，
    /// 连接会越积越多，服务端每条都占一个线程。
    private var eventTask: Task<Void, Never>?
    /// 推送是否连着 —— 界面上给一个小圆点，断了要能看出来。
    /// 不显示的话，「推送坏了」和「今天没人加分」长得一模一样。
    @Published var live = false
    @Published var offline = false

    /// 开屏先拿一次 state：cookie 还在就直接进，不必再问一次密码。
    /// 拿不到**不等于**密码错了 —— 也可能是没网。所以只在 401 那种「账本拒绝」时才退到登录页，
    /// 其余错误留在登录页上把原因显示出来，不假装成「你没登录」。
    /// ⚠ 超时给 6s 而不是默认的 20s：这一次请求挡在**任何界面之前**，
    /// 没网时用户要盯着转圈等满 20 秒才看到登录页 —— 那是「app 坏了」的观感。
    /// 探测失败一律退到登录页，那里能重试，也能显示原因。
    func restore() async {
        AccountHints.restore()   // 上次存的账号流程数字与提示，登录页出现之前就位
        // 验证通道：只有显式传了 launch 参数才生效，生产路径上这两个 key 永远是 nil。
        //   ... -dev_user jingbao -dev_pw <密码>
        let d = UserDefaults.standard
        if let u = d.string(forKey: "dev_user"), let pw = d.string(forKey: "dev_pw") {
            await login(user: u, password: pw)
            return
        }
        do {
            let fresh = try await Api.state(timeout: 6)
            noteTier(fresh)
            state = fresh
            offline = false
            phase = .loggedIn
            publishSnapshot()
            startEvents()
            WatchLink.shared.publishSession()
        } catch {
            // 探测失败不等于退出登录（也可能只是没网）—— 所以这里**不**通知手表下线
            if error is URLError, let cached = LedgerCache.load() {
                state = cached; phase = .loggedIn; offline = true; startEvents()
            } else {
                self.error = error.localizedDescription
                if (error as? Api.Failure)?.status == 401 { dropSession(); WatchLink.shared.publishSignedOut() }
                phase = .loggedOut
            }
        }
    }

    func login(user: String, password: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Api.login(user: user, password: password)
            let fresh = try await Api.state()
            noteTier(fresh)
            state = fresh
            offline = false
            phase = .loggedIn
            publishSnapshot()
            startEvents()
            WatchLink.shared.publishSession()
        } catch {
            self.error = error.localizedDescription
            // ⚠ 必须落回 loggedOut：从 restore() 的 dev 分支进来时 phase 还是 .checking，
            // 不落回就永远停在开屏转圈上 —— 界面不动，也没有任何错误可看。
            phase = .loggedOut
        }
    }

    func loadHistory() async {
        do { state = try await Api.state(full: true); offline = false }
        catch {
            if (error as? Api.Failure)?.status == 401 {
                dropSession(); WatchLink.shared.publishSignedOut()
            } else { showNotice("读取历史失败：\(error.localizedDescription)") }
        }
    }

    /// 短信认证已取得原服务 cookie，读真实账本后才进入主界面。
    func acceptSession() async throws {
        let fresh = try await Api.state()
        noteTier(fresh); state = fresh; offline = false; error = nil; phase = .loggedIn
        publishSnapshot(); startEvents(); WatchLink.shared.publishSession()
    }

    func refresh() async {
        do {
            let fresh = try await Api.state()
            noteTier(fresh)
            state = fresh
            offline = false
            publishSnapshot()
        } catch {
            self.error = error.localizedDescription
            offline = error is URLError
            if (error as? Api.Failure)?.status == 401 {
                dropSession()
                WatchLink.shared.publishSignedOut()
            }
        }
    }

    /// 账号接口的业务错误与会话失效分开；只在 state 身份闸再次确认 401 后清会话。
    func confirmSessionFailure(_ failure: Error) async {
        guard (failure as? Api.Failure)?.status == 401 else { return }
        await refresh()
    }

    /// 比对档位。**装完 app 第一次**拿到状态时只记不庆（没有基准，谈不上「升」了）；
    /// 之后就算 app 被关掉过，升档照样庆祝 —— 基准在盘上。
    private func noteTier(_ fresh: LedgerState) {
        tierKey = "lastTier." + fresh.user
        defer { lastTier = fresh.tier }
        guard let old = lastTier, fresh.tier > old else { return }
        promoted = fresh.houseName
    }

    /// 把当前状态写进共享 keychain 仓给 Widget 读。
    /// Widget 自己不联网(要处理登录态/超时/重试，而刷新预算由系统说了算)，
    /// 拿不到新数据时它显示上一次的快照，比显示一个转圈有用。
    func publishSnapshot() {
        guard let s = state else { return }
        Snapshot(balance: s.balance, houseName: s.houseName, nextName: s.nextName,
                 toNext: s.toNext, progress: s.progress, era: s.era.rawValue,
                 updated: .now).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 开一条推送长连接。断了自动重连，退避 2→4→8→…→60 秒。
    ///
    /// 为什么要退避而不是固定间隔：服务端重启或没网时，固定 1 秒重连会把
    /// 一个已经出问题的服务打得更惨，而且日志会被刷满。
    func startEvents() {
        guard Self.livePush, eventTask == nil else { return }
        eventTask = Task { [weak self] in
            var backoff: UInt64 = 2
            while !Task.isCancelled {
                do {
                    let stream = try await Api.events()
                    await MainActor.run { self?.live = true }
                    backoff = 2                                  // 连上了就把退避清零
                    for try await kind in stream {
                        guard let self else { return }
                        // 推送只是信号，数据一律回 /api/state 拿（见 Api.events 的说明）
                        if kind == "ledger" || kind == "profile" || kind == "config" {
                            await self.refresh()
                        }
                    }
                } catch {
                    // 连不上/断了都走这里 —— 包括登录态失效，那时 refresh 会自己退到登录页
                }
                await MainActor.run { self?.live = false }
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(Double(backoff)))
                backoff = min(backoff * 2, 60)
            }
        }
    }

    /// 手表不开长连接：一条常驻的 SSE 会让手表的无线一直醒着，电量扛不住。
    /// 手表上抬腕回到前台刷新一次（WatchRootView），复杂功能读刷新时写下的快照。
    private static var livePush: Bool {
        #if os(watchOS)
        return false
        #else
        return true
        #endif
    }

    func stopEvents() {
        eventTask?.cancel()
        eventTask = nil
        live = false
    }

    func register(email: String, password: String, nick: String, grant: String) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Api.register(email: email, password: password, nick: nick, grant: grant)
            let fresh = try await Api.state()
            noteTier(fresh)
            state = fresh
            offline = false
            phase = .loggedIn
            publishSnapshot()
            startEvents()
            WatchLink.shared.publishSession()
        } catch {
            self.error = error.localizedDescription        // 邮箱已注册 / 格式不对 / 名额满，服务端文案原样
        }
    }

    /// 注销账号。成功回 true 并落回登录页；失败把原因放进 error（密码不对 → 403 的那句）。
    func deleteAccount(password: String) async -> Bool {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Api.deleteAccount(password: password)
            dropSession()
            WatchLink.shared.publishSignedOut()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func logout() async {
        stopEvents()
        await Api.logout()
        dropSession()
        WatchLink.shared.publishSignedOut()
    }

    /// 会话在别处结束了（手表收到 iPhone 退出 / 注销的同步）：只清本地，不再发 /api/logout。
    func dropSession() {
        stopEvents()
        TransactionJournal.clear()
        Api.accountUser = nil
        LedgerCache.clear()
        Api.installSessionCookie(nil, expires: nil)
        Snapshot.empty.save()
        WidgetCenter.shared.reloadAllTimelines()
        state = nil; promoted = nil; offline = false
        phase = .loggedOut
    }
}
