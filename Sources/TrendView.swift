import SwiftUI

/// 走势 —— 「像股票盘面」那条定位的落点。
///
/// 曲线用的是每条流水自带的 `bal` 快照（服务端在撤销时会重算它），
/// **不在这里累加求余额** —— 累加出来的曲线和服务端的余额迟早对不上。
struct TrendView: View {
    @EnvironmentObject var store: Store
    @State private var span = 30
    /// 宽屏把曲线画高一些、内容收窄居中；窄屏用默认值，与原来逐字相同。
    var chartHeight: CGFloat = 180
    var maxWidth: CGFloat? = nil

    private var s: LedgerState? { store.state }
    private var era: Era { s?.era ?? .slum }

    private var points: [TrendPoint] { TrendPoint.series(s, span: span) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                spanPicker
                TrendChart(points: points, era: era, height: chartHeight)
                TrendStats(points: points, era: era, practiceLeft: s?.practiceLeft ?? 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .contentWidth(maxWidth)
        }
        .refreshable { await store.loadHistory() }
        .task { await store.loadHistory() }
    }

    private var spanPicker: some View {
        HStack(spacing: 8) {
            ForEach([7, 30, 0], id: \.self) { n in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { span = n }
                } label: {
                    Text(n == 0 ? "全部" : "近 \(n) 天")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .background(span == n ? TreasuryTheme.accent.opacity(0.15) : TreasuryTheme.card,
                                    in: Capsule())
                        .foregroundStyle(span == n ? TreasuryTheme.accent : .primary)
                }
                .flatButton()
            }
            Spacer()
        }
    }

}

/// 走势曲线上的一个点：那一笔之后的余额快照（服务端记的 `bal`）。
struct TrendPoint {
    let day: String
    let bal: Int

    /// 只取积分那条线：电视时间与心愿是另外两本账，混进同一条曲线就是三本账画成一本。
    static func series(_ s: LedgerState?, span: Int) -> [TrendPoint] {
        guard let s else { return [] }
        let date = Calendar.current.date(byAdding: .day, value: -(max(1, span) - 1), to: Date()) ?? Date()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let cutoff = formatter.string(from: date)
        return s.entries.filter { $0.cur == "pts" }
            .reversed()                       // entries 已倒序，这里转回时间正序
            .filter { entry in
                guard span > 0 else { return true }
                return entry.when >= cutoff
            }
            .map { TrendPoint(day: $0.when, bal: $0.bal) }
    }
}

/// 余额曲线卡。走势页和宽屏看板共用。
struct TrendChart: View {
    let points: [TrendPoint]
    let era: Era
    var height: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if points.isEmpty {
                Text("还没有流水，去「加分」记第一笔。").font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                let vals = points.map { Double($0.bal) }
                let lo = vals.min() ?? 0, hi = vals.max() ?? 1
                let span = max(1, hi - lo)

                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let step = w / Double(max(1, vals.count - 1))
                    let pt: (Int) -> CGPoint = { i in
                        CGPoint(x: Double(i) * step,
                                y: h - (vals[i] - lo) / span * (h - 12) - 6)
                    }
                    ZStack {
                        // 填充：从曲线到底边，给「资产」一点体量感
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h))
                            for i in vals.indices { p.addLine(to: pt(i)) }
                            p.addLine(to: CGPoint(x: w, y: h))
                            p.closeSubpath()
                        }
                        .fill(LinearGradient(colors: [era.accent.opacity(0.35), era.accent.opacity(0.02)],
                                             startPoint: .top, endPoint: .bottom))
                        Path { p in
                            p.move(to: pt(0))
                            for i in vals.indices.dropFirst() { p.addLine(to: pt(i)) }
                        }
                        .stroke(era.accent, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                        Circle()
                            .fill(era.accent)
                            .frame(width: 9, height: 9)
                            .position(pt(vals.count - 1))
                    }
                }
                .frame(height: height)

                HStack {
                    Text(points.first?.day ?? "")
                    Spacer()
                    Text(points.last?.day ?? "")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// 涨跌 / 最高 / 最低 / 今天刷题余额。
struct TrendStats: View {
    let points: [TrendPoint]
    let era: Era
    let practiceLeft: Int

    var body: some View {
        let vals = points.map { $0.bal }
        let delta = (vals.last ?? 0) - (vals.first ?? 0)
        return VStack(spacing: 0) {
            row("这段涨跌", (delta >= 0 ? "+" : "") + "\(delta) 分",
                color: delta >= 0 ? era.accent : Color(hex: 0xB44740))
            Divider().overlay(.white.opacity(0.12))
            row("最高", "\(vals.max() ?? 0) 分")
            Divider().overlay(.white.opacity(0.12))
            row("最低", "\(vals.min() ?? 0) 分")
            Divider().overlay(.white.opacity(0.12))
            row("今天刷题还能得", "\(practiceLeft) 分")
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ k: String, _ v: String, color: Color = .primary) -> some View {
        HStack {
            Text(k).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
        .padding(.vertical, 12)
    }
}
