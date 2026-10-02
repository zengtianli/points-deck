import SwiftUI

/// 手表主页：上下翻两页。
/// 第一页是抬腕那一眼要看到的：住在哪一档、余额、还差多少升级 + 进度；
/// 第二页是最近 10 笔流水。配色和 iPhone 一样从时代插画派生（Era），一档一个颜色。
struct WatchHomeView: View {
    @EnvironmentObject var store: Store
    // 验证通道：和 iPhone 一样认 `-tab 1`，直接落到流水页（headless 截图翻不了页）。不传就是第一页。
    @State private var page = UserDefaults.standard.integer(forKey: "tab") == 1 ? 1 : 0

    private var s: LedgerState? { store.state }
    private var era: Era { s?.era ?? .slum }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                balancePage
                    .containerBackground(for: .tabView) { backdrop }
                    .tag(0)
                ledgerPage
                    .containerBackground(era.background, for: .tabView)
                    .tag(1)
            }
            .tabViewStyle(.verticalPage)
        }
        // 主页只在拿到账本后才出现：这就是手表上「第一屏有数据」的时刻
        .onAppear { LaneSignal.ready("watch-home") }
    }

    // ── 第一页：余额 + 还差 N 分 ────────────────────────────────────────────
    private var balancePage: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "house.fill").font(.caption2)
                Text(s?.houseName ?? "—").font(.footnote.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(era.accent)
            Text(RollingNumber.grouped(s?.balance ?? 0))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
            Text("≈ ¥\(s?.yuan ?? "0.00")")
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 6)
            if let s, let need = s.toNext, let name = s.nextName {
                Text("还差 \(RollingNumber.grouped(need)) 分升「\(name)」")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                // 和 iPhone 账本页同一种细进度条（系统 ProgressView 在表上又粗又贴边）
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(era.accent)
                            .frame(width: max(6, geo.size.width * s.progress))
                    }
                }
                .frame(height: 7)
            } else {
                Text("已经住到顶了 —— 云端天堂")
                    .font(.caption2.weight(.medium)).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 10)        // 圆角屏的下角会切掉贴底的东西
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 这一页不放导航标题：标题压在插画上读不清，房名本身就是这一页的抬头
    }

    /// 第一页的底：时代渐变，顶上淡淡压一层这一档的插画（住什么房得看得见），
    /// 再在最上沿压一点暗，右上角的时间别被米白的天空吃掉。
    private var backdrop: some View {
        ZStack(alignment: .top) {
            era.background
            if let img = era.banner {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 130)
                    .clipped()
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .center, endPoint: .bottom))
                    .opacity(0.5)
                LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 60)
            }
        }
    }

    // ── 第二页：最近 10 笔 ──────────────────────────────────────────────────
    private var ledgerPage: some View {
        List {
            let es = Array((s?.entries ?? []).prefix(10))
            if es.isEmpty {
                Text("还没有流水").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(es) { e in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(e.what).font(.footnote).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(e.signed)
                            .font(.footnote.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(e.pts >= 0 ? era.accent : Color(hex: 0xFF9E9E))
                    }
                    Text(e.when).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.10)))
            }
        }
        .navigationTitle("最近流水")
    }
}
