import SwiftUI

/// 宽屏主页（iPad 全屏 / 宽分屏、Mac、Vision Pro）：侧栏四项 + 详情看板 + 右侧家长 inspector。
///
/// 为什么不把窄屏的分页直接拉宽：iPad 上每张卡撑满约 1000pt，底图只剩一条细带，
/// 流水的金额离事由隔着半个屏（2026-10-02 iPad 模拟器实测）。宽屏要的是一眼看全 ——
/// 账本看板把底图、市值、还差 N 分、走势、流水并排摆开。
/// 家长面放 inspector 而不是 sheet：记一笔，左边的余额当场滚上去，家长看得见这笔落了账。
/// 卡片都是窄屏同一份（DeckView.swift / TrendView.swift 里拆出来的），这里只管摆法。
struct RegularHomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: ParentSession
    @Binding var tab: Int
    @Binding var showParent: Bool

    private var era: Era { store.state?.era ?? .slum }

    enum Pane: Int, CaseIterable, Identifiable {
        case deck, trend, shop, account
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .deck: return "账本"
            case .trend: return "走势"
            case .shop: return "兑换"
            case .account: return "账户"
            }
        }
        var icon: String {
            switch self {
            case .deck: return "list.bullet.rectangle"
            case .trend: return "chart.line.uptrend.xyaxis"
            case .shop: return "gift"
            case .account: return "person.crop.circle"
            }
        }
    }

    private var pane: Pane { Pane(rawValue: tab) ?? .deck }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationTitle(pane.title)
                #if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbar }
                .modifier(ParentPanel(isPresented: $showParent))
        }
        .preferredColorScheme(.dark)
    }

    // ── 侧栏：头像 / 昵称 / 房名 / 推送状态 + 四项 ──────────────────────────────
    private var sidebar: some View {
        List(selection: Binding<Int?>(get: { tab }, set: { if let v = $0 { tab = v } })) {
            Section {
                SidebarProfile()
            }
            Section {
                ForEach(Pane.allCases) { p in
                    Label(p.title, systemImage: p.icon).tag(p.rawValue as Int?)
                }
            }
        }
        .navigationTitle(AppIdentity.displayName)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        #if !os(visionOS)
        // 侧栏铺时代的天空色，和右边的整页渐变接成一片；Vision Pro 上保留系统玻璃
        .scrollContentBackground(.hidden)
        .background(era.palette.top.ignoresSafeArea())
        #endif
    }

    // ── 详情 ────────────────────────────────────────────────────────────────
    private var detail: some View {
        Group {
            switch pane {
            case .deck: DeckBoard()
            // 窄屏的这几页顶上有自绘的顶栏垫着；宽屏直接贴着导航栏，补一点上边距
            case .trend: TrendView(chartHeight: 280, maxWidth: 860).contentMargins(.top, 20, for: .scrollContent)
            case .shop: ShopView(wide: true)
            case .account: AccountView(maxWidth: 640).contentMargins(.top, 12, for: .scrollContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .eraBackdrop(era)
        .animation(.easeInOut(duration: 0.8), value: era)   // 升档 = 场景切换
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Mac 没有下拉刷新的手势（.refreshable 在那里摸不到），刷新要有一个看得见的按钮和 ⌘R
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("刷新账本（⌘R）")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showParent.toggle()
            } label: {
                Label("家长记账", systemImage: session.isUnlocked ? "lock.open" : "lock.shield")
            }
            .help(showParent ? "收起家长面" : "家长记账")
        }
    }
}

/// 家长面的摆法：iPad / Mac 是右侧 inspector 栏（左边余额随记账实时变）；
/// visionOS 没有 inspector，用系统的玻璃 sheet。
private struct ParentPanel: ViewModifier {
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: ParentSession
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        #if os(visionOS)
        content.sheet(isPresented: $isPresented) {
            ParentView()
                .environmentObject(store).environmentObject(session)
                .frame(minWidth: 520, minHeight: 640)
        }
        #else
        content.inspector(isPresented: $isPresented) {
            // 收起时不留着这棵树：Mac 上收起的 inspector 里的工具栏按钮（「关闭」）会漏到窗口工具栏上
            if isPresented {
                ParentView(onClose: { isPresented = false })
                    .environmentObject(store).environmentObject(session)
                    .inspectorColumnWidth(min: 340, ideal: 380, max: 480)
            }
        }
        #endif
    }
}

/// 侧栏顶上的「我是谁」：头像、昵称、住在哪一档、推送连没连上。
/// 推送状态得露出来 —— 不露的话，「推送坏了」和「今天没人加分」长得一模一样。
private struct SidebarProfile: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let s = store.state
        let era = s?.era ?? .slum
        HStack(spacing: 12) {
            Text(s?.avatar ?? "🐯")
                .font(.system(size: 28))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.12), in: Circle())
                .overlay(Circle().stroke(era.accent.opacity(0.55), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(s?.nick ?? "—").font(.headline).foregroundStyle(.white)
                HStack(spacing: 5) {
                    Image(systemName: "house.fill").font(.caption2)
                    Text(s?.houseName ?? "—").font(.caption.weight(.semibold))
                }
                .foregroundStyle(era.accent)
                HStack(spacing: 5) {
                    Circle().fill(store.live ? .green : .orange).frame(width: 6, height: 6)
                    Text(store.live ? "实时同步中" : "未连上推送")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// 宽屏的账本看板。够宽（≥ 780pt）时两列：左列底图 + 市值 + 还差 N 分，右列走势 + 统计 + 流水；
/// 不够宽（iPad 竖屏开着家长面、窄窗口）时收成一列、限宽居中。
struct DeckBoard: View {
    @EnvironmentObject var store: Store
    @State private var shown: Double = 0
    @State private var width: CGFloat = 0

    private var s: LedgerState? { store.state }
    private var era: Era { s?.era ?? .slum }
    private var points: [TrendPoint] { TrendPoint.series(s, span: 30) }

    var body: some View {
        ScrollView {
            Group {
                if twoColumns {
                    // 两列平分，左列封顶 460pt，余下的都给走势与流水
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 20) { primary }
                            .frame(maxWidth: 460)
                        VStack(spacing: 20) { secondary }
                    }
                } else {
                    VStack(spacing: 20) {
                        primary
                        secondary
                    }
                    .contentWidth(680)
                }
            }
            .padding(24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .refreshable { await store.refresh() }
        .task {
            // 和窄屏一样：进来先把数字从 0 滚上去，之后的刷新只滚差值
            guard let s else { return }
            withAnimation(.easeOut(duration: 1.1)) { shown = Double(s.balance) }
        }
        .onChange(of: s?.balance) { _, new in
            guard let new else { return }
            withAnimation(.easeOut(duration: 0.6)) { shown = Double(new) }
        }
    }

    /// 量出来的宽度只用来选一列还是两列，不拿它去定任何尺寸 —— 尺寸跟着量值走，
    /// 量值又跟着尺寸变，Mac 上开着 inspector 时会在布局里来回打转（2026-10-02 实测主线程 100%）。
    private var twoColumns: Bool { width >= 780 }

    @ViewBuilder
    private var primary: some View {
        EraBanner(era: era, houseName: s?.houseName ?? "", height: 220, fitsColumn: true)
        MarketValueCard(state: s, era: era, shown: shown)
        NextTierCard(state: s, era: era)
    }

    @ViewBuilder
    private var secondary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("走势 · 近 30 笔").font(.caption).foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 4)
            TrendChart(points: points, era: era, height: 200)
        }
        TrendStats(points: points, era: era, practiceLeft: s?.practiceLeft ?? 0)
        LedgerCard(entries: s?.entries ?? [], era: era)
    }
}
