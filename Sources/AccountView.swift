import SwiftUI

/// 账户页 —— 「就和账户一样」（2026-08-28 用户原话）。
///
/// 它回答四个在别处无处可问的问题：**我是谁 / 我到哪一级了 / 我有多少 / 怎么设置**。
/// 其中「我到哪一级了」是重点：等级卡不是一个数字，是一个能点进去看完整阶梯的入口 ——
/// 看不见的饼不是饼。
struct AccountView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: ParentSession

    @State private var showTiers = false
    @State private var showAdmin = false
    @State private var askUnlock = false
    @State private var typedPw = ""
    @State private var unlockErr: String?
    @State private var unlocking = false
    @State private var showProfile = false
    @State private var confirmLogout = false
    @State private var askDelete = false
    @State private var askParent = false
    @State private var parentAcct = ""
    @State private var parentPw = ""
    @State private var parentMsg: String?
    @State private var deletePw = ""
    @State private var deleteErr: String?

    private var s: State? { store.state }
    private var era: Era { s?.era ?? .slum }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                levelCard
                assets
                settings
                about
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showTiers) {
            TiersView().environmentObject(store)
        }
        .sheet(isPresented: $showProfile) {
            ProfileEditView().environmentObject(store)
        }
        .sheet(isPresented: $showAdmin) {
            AdminView().environmentObject(store).environmentObject(session)
        }
        .alert("解锁家长模式", isPresented: $askUnlock) {
            SecureField("管理密码", text: $typedPw)
            Button("解锁") { Task { await unlock() } }
            Button("取消", role: .cancel) { typedPw = "" }
        } message: {
            Text("解锁后可以记账、也能改规则和商品。上锁、退出 app、或切后台超过 10 分钟会自动锁回去。")
        }
        // App Store 5.1.1(v)：能注册就必须能在 app 内删号。要密码，二次确认，文案说清删什么。
        // 家长密码按账号各自一把：改它要账号密码（登录态不够）
        .alert("设置家长密码", isPresented: $askParent) {
            SecureField("账号密码", text: $parentAcct)
            SecureField("新的家长密码（至少 4 位）", text: $parentPw)
            Button("保存") {
                Task {
                    do { try await Api.setParent(password: parentAcct, parent: parentPw); parentMsg = "家长密码已更新" }
                    catch { parentMsg = error.localizedDescription }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("记账、撤销、改规则都要这把密码；只有家长知道。")
        }
        .alert("家长密码", isPresented: Binding(get: { parentMsg != nil }, set: { if !$0 { parentMsg = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(parentMsg ?? "") }
        .alert("注销账号？", isPresented: $askDelete) {
            SecureField("当前密码", text: $deletePw)
            Button("永久删除", role: .destructive) {
                Task {
                    if await store.deleteAccount(password: deletePw) { deleteErr = nil }
                    else { deleteErr = store.error }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("账号、积分账本、学习存档、头像会一起删除，不可恢复。输入当前密码确认。")
        }
        .alert("没删成", isPresented: Binding(get: { deleteErr != nil }, set: { if !$0 { deleteErr = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(deleteErr ?? "") }
        .alert("退出登录？", isPresented: $confirmLogout) {
            Button("退出", role: .destructive) { Task { await store.logout() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("账本在服务器上，退出不会丢任何数据。")
        }
    }

    // ── 头部：头像 + 昵称 + 当前档位徽章 ──────────────────────────────────────
    private var header: some View {
        VStack(spacing: 10) {
            Text(s?.avatar ?? "🐯")
                .font(.system(size: 56))
                .frame(width: 96, height: 96)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(era.accent.opacity(0.55), lineWidth: 2))

            Text(s?.nick ?? "—")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: "house.fill").font(.caption)
                Text(s?.houseName ?? "—").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(era.accent)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.white.opacity(0.12), in: Capsule())

            Button {
                showProfile = true
            } label: {
                Label("编辑资料", systemImage: "pencil")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.top, 8)
    }

    // ── 等级卡 —— 本页的核心 ─────────────────────────────────────────────────
    private var levelCard: some View {
        Button {
            showTiers = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("等级")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    if let s {
                        Text("第 \(s.tier + 1) 级 / 共 \(max(s.ladder.count, s.tier + 1)) 级")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }

                if let s {
                    ProgressView(value: s.progress)
                        .tint(era.accent)
                        .scaleEffect(x: 1, y: 1.6, anchor: .center)

                    // 「还差多少」是钩子，必须是这张卡上最显眼的一行字
                    if let toNext = s.toNext, let next = s.nextName {
                        HStack(spacing: 4) {
                            Text("距").foregroundStyle(.white.opacity(0.6))
                            Text(next).foregroundStyle(era.accent).fontWeight(.semibold)
                            Text("还差").foregroundStyle(.white.opacity(0.6))
                            Text("\(toNext)").foregroundStyle(.white).fontWeight(.bold)
                                .monospacedDigit()
                            Text("分").foregroundStyle(.white.opacity(0.6))
                        }
                        .font(.subheadline)

                        // 下一档给什么 —— 这一行就是饼本身。没有它，进度条只是个进度条。
                        if let nextTier = s.ladder.first(where: { $0.at == s.nextAt }) {
                            nextReward(nextTier)
                        }
                    } else {
                        Text("已经是最高一档了 👑")
                            .font(.subheadline).foregroundStyle(era.accent)
                    }
                }

                HStack {
                    Text("查看全部等级与待遇")
                    Image(systemName: "chevron.right")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(era.accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func nextReward(_ t: State.Tier) -> some View {
        let items = (s?.shop ?? []).filter { t.unlock.contains($0.id) }
        if t.bonus > 0 || !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("升上去能拿到")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                if t.bonus > 0 {
                    Label("贺礼 \(t.bonus) 分", systemImage: "gift.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                ForEach(items) { it in
                    Label("解锁 \(it.icon) \(it.label)", systemImage: "lock.open.fill")
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.top, 2)
        }
    }

    // ── 资产 ────────────────────────────────────────────────────────────────
    private var assets: some View {
        card("资产") {
            row("市值", value: RollingNumber.grouped(s?.balance ?? 0) + " 分")
            if let s, s.rate > 0 {
                row("折合", value: String(format: "¥%.2f", Double(s.balance) / Double(s.rate)),
                    dim: true)
            }
            row("电视时间", value: "\(s?.tv ?? 0) 分钟")
            row("今天还能刷题挣", value: "\(s?.practiceLeft ?? 0) 分")
            // 推送状态得露出来 —— 不露的话，「推送坏了」和「今天没人加分」长得一模一样
            HStack {
                Circle().fill(store.live ? .green : .orange).frame(width: 7, height: 7)
                Text(store.live ? "实时同步中" : "未连上推送（下拉可手动刷新）")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                Spacer()
            }
        }
    }

    // ── 设置 ────────────────────────────────────────────────────────────────
    private var settings: some View {
        card("设置") {
            tapRow("改昵称 / 换头像", icon: "person.text.rectangle") { showProfile = true }
            // 家长模式 —— **解锁必须是一个能直接点的按钮**。
            // 原先只有「记这一笔」会顺带弹密码框，等于想解锁得先凑一笔账出来，
            // 那个入口找不到就是不存在。
            HStack {
                Label("家长模式", systemImage: session.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                if session.isUnlocked {
                    Text("已解锁 · \(session.count) 笔")
                        .font(.footnote).foregroundStyle(.white.opacity(0.55))
                    Button("上锁") { session.lock() }
                        .font(.footnote).buttonStyle(.borderless)
                        .foregroundStyle(era.accent)
                } else {
                    Button("解锁") { unlockErr = nil; askUnlock = true }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                        .foregroundStyle(era.accent)
                }
            }
            .font(.subheadline)
            if let unlockErr {
                Text(unlockErr).font(.caption).foregroundStyle(.orange)
            }
            if session.isUnlocked {
                tapRow("管理规则 / 商品 / 档位", icon: "slider.horizontal.3") { showAdmin = true }
            }
            tapRow("退出登录", icon: "rectangle.portrait.and.arrow.right",
                   tint: .red.opacity(0.9)) { confirmLogout = true }
            tapRow("家长密码", icon: "key.fill") { parentPw = ""; parentAcct = ""; askParent = true }
            tapRow("注销账号", icon: "person.crop.circle.badge.xmark",
                   tint: .red.opacity(0.9)) { deletePw = ""; askDelete = true }
        }
    }

    private var about: some View {
        VStack(spacing: 4) {
            Text("\(AppIdentity.displayName) · \(Bundle.main.shortVersion)")
            Text("账本在 edu.tianli.cyou，本机不存账")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.35))
        .padding(.top, 6)
    }

    private func unlock() async {
        let pw = typedPw; typedPw = ""
        guard !pw.isEmpty else { return }
        unlocking = true; defer { unlocking = false }
        do {
            try await session.unlock(password: pw)
            unlockErr = nil
        } catch {
            // 服务端的原话（「家长密码不对」）比「解锁失败」有用
            unlockErr = error.localizedDescription
        }
    }

    // ── 小零件 ──────────────────────────────────────────────────────────────
    private func card<C: View>(_ title: String,
                               @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ title: String, value: String, dim: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(dim ? 0.55 : 0.9))
            Spacer()
            Text(value).foregroundStyle(dim ? .white.opacity(0.55) : .white)
                .fontWeight(dim ? .regular : .semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    private func tapRow(_ title: String, icon: String, tint: Color = .white.opacity(0.9),
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(tint)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.white.opacity(0.35))
            }
            .font(.subheadline)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }
}
