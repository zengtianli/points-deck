import SwiftUI

/// 孩子面第一屏 —— 市值 / 「还差 N 分」/ 流水。
/// 家长面、走势图、兑换都还没写：先跑通这一屏，看过导航范式再铺开(/appios 硬约束)。
///
/// 四块卡片拆成了下面几个独立视图，窄屏这里和宽屏看板（DeckBoard）用的是同一份；
/// 窄屏的参数与原来逐字相同（底图带 132pt、间距 22），拆分前后截图逐像素一致。
struct DeckView: View {
    @EnvironmentObject var store: Store
    @State private var shown: Double = 0
    @State private var filter = "全部"
    @State private var selected: LedgerState.Entry?

    private var s: LedgerState? { store.state }
    private var era: Era { s?.era ?? .slum }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                    EraBanner(era: era, houseName: s?.houseName ?? "", height: 132)
                    MarketValueCard(state: s, era: era, shown: shown)
                    NextTierCard(state: s, era: era)
                    TreasuryChoice(title: "流水筛选", selection: $filter,
                                   options: ["全部", "加分", "减分", "兑换"].map { ($0, $0) })
                    LazyVStack(spacing: 10) {
                        ForEach((s?.entries ?? []).filter { entry in
                            filter == "全部" || (filter == "加分" && entry.pts > 0) ||
                            (filter == "减分" && entry.pts < 0 && !entry.isRedemption) ||
                            (filter == "兑换" && entry.isRedemption)
                        }) { entry in
                            Button { selected = entry } label: {
                                LedgerCard(entries: [entry], era: era)
                            }.buttonStyle(.plain)
                        }
                        if let s, s.total > s.entries.count {
                            Button("查看更早流水") { Task { await store.loadHistory() } }.frame(minHeight: 48)
                        }
                        if (s?.entries ?? []).isEmpty { Text("还没有流水，去「加分」记第一笔。") }
                    }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { entry in
            NavigationStack {
                Form {
                    Text(entry.what).font(.headline)
                    LabeledContent("实际积分", value: entry.signed)
                    LabeledContent("时间", value: entry.when)
                    if !entry.note.isEmpty { Text(entry.note) }
                    Button("撤销这笔误记", role: .destructive) {
                        Task { if await store.undoEntry(entry.id) { selected = nil } }
                    }
                }.navigationTitle("流水详情")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { selected = nil } } }
            }.frame(minWidth: 320, minHeight: 320)
        }
        .task {
            // 进来先把数字从 0 滚上去，之后的刷新只滚差值
            guard let s else { return }
            withAnimation(.easeOut(duration: 1.1)) { shown = Double(s.balance) }
        }
        .onChange(of: s?.balance) { _, new in
            guard let new else { return }
            withAnimation(.easeOut(duration: 0.6)) { shown = Double(new) }
        }
    }
}

/// 天际线底图带 —— 「住什么房」这件事**得看得见**，不能只是一行字。
/// 11 档房名映射到 5 个时代(skins.json 的 era)，所以小木屋与砖瓦房共用一张图 ——
/// 那是 ~/Apps/edu/web 既定的美术分档，不在端上另立一套。
struct EraBanner: View {
    let era: Era
    let houseName: String
    var height: CGFloat = 132
    /// 宽屏看板传 true：底图是约 2:1 的横幅，列窄而带子高（220pt）时按 fill 铺满高度，图会横向撑出列外，
    /// 所以改成「先占满列宽、再把图裁进去」。窄屏不传，走原来那几行，一个像素不变。
    var fitsColumn = false

    var body: some View {
        if let img = era.banner {
            ZStack(alignment: .bottomLeading) {
                if fitsColumn {
                    Color.clear
                        .frame(height: height)
                        .overlay {
                            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                        }
                        .clipped()
                } else {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: height)
                    .clipped()
                }
                // 底部压一层渐变，房名压在图上才读得清
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
                Text(houseName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.8), value: era)   // 升档时换图也是一次转场
        }
    }
}

/// 总市值大字（滚动数字）+ 折合人民币 + 电视时间。`shown` 由外层驱动滚动动画。
struct MarketValueCard: View {
    let state: LedgerState?
    let era: Era
    let shown: Double

    var body: some View {
        VStack(spacing: 6) {
            Text("当前积分").font(.caption).foregroundStyle(.secondary)
            RollingNumber(value: shown).foregroundStyle(.primary)
            HStack(spacing: 14) {
                Text("≈ ¥\(state?.yuan ?? "0.00")")
                if let tv = state?.tv, tv != 0 {
                    Text("📺 \(tv) 分钟")
                }
            }
            .font(.subheadline).foregroundStyle(TreasuryTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

/// 「差一点就完成」必须一直在眼前 —— 这是整套激励的钩子，不是装饰。
struct NextTierCard: View {
    let state: LedgerState?
    let era: Era

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = state, let need = s.toNext, let name = s.nextName {
                Text("还差 \(RollingNumber.grouped(need)) 分升级到「\(name)」")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TreasuryTheme.accent.opacity(0.12))
                        Capsule().fill(era.accent)
                            .frame(width: max(6, geo.size.width * s.progress))
                            .animation(.easeOut(duration: 0.8), value: s.progress)
                    }
                }
                .frame(height: 10)
            } else {
                Text("已经住到顶了 —— 云端天堂")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            }
        }
        .padding(18)
        .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// 最近流水（服务端给的最近 30 笔，倒序）。
struct LedgerCard: View {
    let entries: [LedgerState.Entry]
    let era: Era

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !entries.isEmpty {
                ForEach(entries) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.what).font(.subheadline).foregroundStyle(.primary)
                            Text(e.when + (e.note.isEmpty ? "" : " " + e.note))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(e.signed)
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(e.pts >= 0 ? era.accent : Color(hex: 0xB44740))
                    }
                    if e.id != entries.last?.id { Divider().overlay(.white.opacity(0.12)) }
                }
            } else {
                Text("还没有流水").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
