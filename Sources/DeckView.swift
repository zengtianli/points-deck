import SwiftUI

/// 孩子面第一屏 —— 市值 / 「还差 N 分」/ 流水。
/// 家长面、走势图、兑换都还没写：先跑通这一屏，看过导航范式再铺开(/appios 硬约束)。
struct DeckView: View {
    @EnvironmentObject var store: Store
    @State private var shown: Double = 0

    private var s: State? { store.state }
    private var era: Era { s?.era ?? .slum }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                    banner
                    marketValue
                    nextTier
                    ledger
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
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

    /// 天际线底图带 —— 「住什么房」这件事**得看得见**，不能只是一行字。
    /// 11 档房名映射到 5 个时代(skins.json 的 era)，所以小木屋与砖瓦房共用一张图 ——
    /// 那是 ~/Edu 既定的美术分档，不在端上另立一套。
    @ViewBuilder
    private var banner: some View {
        if let img = era.banner {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 132)
                    .clipped()
                // 底部压一层渐变，房名压在图上才读得清
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .center, endPoint: .bottom)
                Text(s?.houseName ?? "")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.8), value: era)   // 升档时换图也是一次转场
        }
    }

    private var marketValue: some View {
        VStack(spacing: 6) {
            Text("总市值").font(.caption).foregroundStyle(.white.opacity(0.6))
            RollingNumber(value: shown).foregroundStyle(.white)
            HStack(spacing: 14) {
                Text("≈ ¥\(s?.yuan ?? "0.00")")
                if let tv = s?.tv, tv != 0 {
                    Text("📺 \(tv) 分钟")
                }
            }
            .font(.subheadline).foregroundStyle(era.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
    }

    /// 「差一点就完成」必须一直在眼前 —— 这是整套激励的钩子，不是装饰。
    private var nextTier: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s, let need = s.toNext, let name = s.nextName {
                Text("还差 \(RollingNumber.grouped(need)) 分升级到「\(name)」")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(era.accent)
                            .frame(width: max(6, geo.size.width * s.progress))
                            .animation(.easeOut(duration: 0.8), value: s.progress)
                    }
                }
                .frame(height: 10)
            } else {
                Text("已经住到顶了 —— 云端天堂")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
            }
        }
        .padding(18)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近流水").font(.caption).foregroundStyle(.white.opacity(0.6))
            if let es = s?.entries, !es.isEmpty {
                ForEach(es) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.what).font(.subheadline).foregroundStyle(.white)
                            Text(e.when + (e.note.isEmpty ? "" : " " + e.note))
                                .font(.caption2).foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        Text(sign(e))
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(e.pts >= 0 ? era.accent : Color(hex: 0xFF9E9E))
                    }
                    if e.id != es.last?.id { Divider().overlay(.white.opacity(0.12)) }
                }
            } else {
                Text("还没有流水").font(.subheadline).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    /// 三种币种走同一条时间线(服务端如此)，所以单位要跟着条目走，不能一律写「分」。
    private func sign(_ e: State.Entry) -> String {
        let unit = e.cur == "tv" ? " 分钟" : (e.cur == "wish" ? " 次" : "")
        return (e.pts >= 0 ? "+" : "") + "\(e.pts)" + unit
    }
}
