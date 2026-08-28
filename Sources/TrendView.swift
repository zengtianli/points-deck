import SwiftUI

/// 走势 —— 「像股票盘面」那条定位的落点。
///
/// 曲线用的是每条流水自带的 `bal` 快照（服务端在撤销时会重算它），
/// **不在这里累加求余额** —— 累加出来的曲线和服务端的余额迟早对不上。
struct TrendView: View {
    @EnvironmentObject var store: Store
    @State private var span = 30

    private var s: State? { store.state }
    private var era: Era { s?.era ?? .slum }

    /// 只取积分那条线：电视时间与心愿是另外两本账，混进同一条曲线就是三本账画成一本。
    private var points: [(day: String, bal: Int)] {
        guard let s else { return [] }
        return s.entries.filter { $0.cur == "pts" }
            .reversed()                       // entries 已倒序，这里转回时间正序
            .suffix(span)
            .map { ($0.when, $0.bal) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                spanPicker
                chart
                stats
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
    }

    private var spanPicker: some View {
        HStack(spacing: 8) {
            ForEach([14, 30, 100], id: \.self) { n in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { span = n }
                } label: {
                    Text("近 \(n) 笔")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(span == n ? era.accent.opacity(0.9) : .white.opacity(0.12),
                                    in: Capsule())
                        .foregroundStyle(span == n ? .black : .white.opacity(0.8))
                }
            }
            Spacer()
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            if points.count < 2 {
                Text("流水还太少，画不出走势").font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                let vals = points.map { Double($0.bal) }
                let lo = vals.min() ?? 0, hi = vals.max() ?? 1
                let span = max(1, hi - lo)

                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let step = w / Double(vals.count - 1)
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
                .frame(height: 180)

                HStack {
                    Text(points.first?.day ?? "")
                    Spacer()
                    Text(points.last?.day ?? "")
                }
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private var stats: some View {
        let vals = points.map { $0.bal }
        let delta = (vals.last ?? 0) - (vals.first ?? 0)
        return VStack(spacing: 0) {
            row("这段涨跌", (delta >= 0 ? "+" : "") + "\(delta) 分",
                color: delta >= 0 ? era.accent : Color(hex: 0xFF9E9E))
            Divider().overlay(.white.opacity(0.12))
            row("最高", "\(vals.max() ?? 0) 分")
            Divider().overlay(.white.opacity(0.12))
            row("最低", "\(vals.min() ?? 0) 分")
            Divider().overlay(.white.opacity(0.12))
            row("今天刷题还能得", "\(s?.practiceLeft ?? 0) 分")
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    private func row(_ k: String, _ v: String, color: Color = .white) -> some View {
        HStack {
            Text(k).font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(v).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
        .padding(.vertical, 12)
    }
}
