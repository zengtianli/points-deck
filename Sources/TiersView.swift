import SwiftUI

/// 等级总览 —— 「画饼」的主战场（2026-08-28 用户原话：
/// 「就是我要知道我升级到下个级别有什么好处…到了后面级别高了会怎么样。美团 花小猪
/// 都有这样的，看一共有几个级别」）。
///
/// 一条硬规矩：**没到的档位不隐藏、不打码、不写「敬请期待」。**
/// 看不见的饼不是饼 —— 这个页面存在的全部理由就是让人看见第 10 档有一次短途旅行，
/// 然后知道那要 40000 分。
///
/// 阈值与权益全部来自 `/api/state` 的 `ladder`，SSOT 在
/// `~/Edu/points/skins/skins.json`。这里一个数字都不许写死。
struct TiersView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    private var s: State? { store.state }
    private var era: Era { s?.era ?? .slum }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        summary
                        ForEach(Array((s?.ladder ?? []).enumerated()), id: \.element.id) { i, t in
                            tierCard(i, t).id(i)
                        }
                        footnote
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .onAppear {
                    // 一进来就滚到当前档 —— 11 档很长，让人自己找「我在哪」是差体验
                    guard let cur = s?.tier else { return }
                    withAnimation { proxy.scrollTo(cur, anchor: .center) }
                }
            }
            .background(era.background.ignoresSafeArea())
            .navigationTitle("等级与待遇")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 8) {
            if let s {
                Text("你在第 \(s.tier + 1) 级 · \(s.houseName)")
                    .font(.title3.weight(.bold)).foregroundStyle(.white)
                Text("共 \(s.ladder.count) 级 · 市值 \(RollingNumber.grouped(s.balance)) 分")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                if let toNext = s.toNext, let next = s.nextName {
                    Text("距「\(next)」还差 \(toNext) 分")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(era.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func tierCard(_ i: Int, _ t: State.Tier) -> some View {
        let cur = s?.tier ?? 0
        let passed = i < cur
        let now = i == cur
        let items = (s?.shop ?? []).filter { t.unlock.contains($0.id) }

        HStack(alignment: .top, spacing: 12) {
            // 时代底图缩略 —— 「后面级别高了会怎么样」得看得见，不能只是一行字
            ZStack {
                if let img = t.era.banner {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    t.era.background
                }
                if !passed && !now {
                    // 未达档位压暗但**不遮住** —— 看得见才有吸引力，
                    // 打码或换成问号等于把这页存在的理由抹掉
                    Color.black.opacity(0.45)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(now ? era.accent : .white.opacity(0.12), lineWidth: now ? 2 : 1))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.7))
                        .frame(width: 20, height: 20)
                        .background(now ? era.accent : .white.opacity(0.4), in: Circle())
                    Text(t.name)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(passed || now ? 1 : 0.75))
                    Spacer()
                    if passed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.45))
                    } else if now {
                        Text("现在").font(.caption2.weight(.bold))
                            .foregroundStyle(.black.opacity(0.75))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(era.accent, in: Capsule())
                    }
                }

                Text(t.at == 0 ? "起始档位" : "\(RollingNumber.grouped(t.at)) 分")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()

                if t.bonus > 0 {
                    Label("乔迁贺礼 \(t.bonus) 分", systemImage: "gift.fill")
                        .font(.caption).foregroundStyle(passed ? .white.opacity(0.5) : era.accent)
                }
                ForEach(items) { it in
                    Label("\(it.icon) \(it.label)　\(RollingNumber.grouped(it.pts)) 分",
                          systemImage: passed || now ? "lock.open.fill" : "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(passed || now ? 0.9 : 0.6))
                }
                if t.bonus == 0 && items.isEmpty {
                    Text("——").font(.caption).foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(now ? .white.opacity(0.16) : .white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(now ? era.accent.opacity(0.7) : .clear, lineWidth: 1.5))
    }

    private var footnote: some View {
        Text("解锁的东西按**当前**市值算 —— 花掉分掉了档，待遇也跟着回去。")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }
}
