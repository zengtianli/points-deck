import SwiftUI
import UIKit

/// 兑换 —— 花的是孩子自己的分，**不需要家长密码**（服务端如此），但不许透支。
struct ShopView: View {
    @EnvironmentObject var store: Store
    @State private var busy: String?
    @State private var toast: String?
    @State private var confirming: State.ShopItem?

    private var s: State? { store.state }
    private var era: Era { s?.era ?? .slum }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                ForEach(s?.shop ?? []) { item in card(item) }
                Text("兑换不许赊账，锁着的也换不了 —— 这两道门都在服务端拦")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await store.refresh() }
        .overlay(alignment: .bottom) {
            if let t = toast {
                Text(t).font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog("要花掉吗？", isPresented: Binding(
            get: { confirming != nil },
            set: { if !$0 { confirming = nil } })) {
            if let it = confirming {
                Button("花 \(it.pts) 分换「\(it.label)」", role: .destructive) {
                    Task { await spend(it) }
                }
            }
            Button("再想想", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Text("现在有").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text("\(RollingNumber.grouped(s?.balance ?? 0)) 分")
                .font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(era.accent)
        }
        .padding(18)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
    }

    /// 一件商品有两种买不了：**没到档位**（锁着）和**分不够**。
    /// 这两种必须在界面上区分开 —— 都显示成「还差 N 分」的话，
    /// 孩子攒够了分点下去仍然失败，那就成了骗人的进度条。
    private func card(_ item: State.ShopItem) -> some View {
        let unlocked = s?.isUnlocked(item.id) ?? true
        let afford = (s?.balance ?? 0) >= item.pts
        let need = s?.tierRequiring(item.id)
        let usable = unlocked && afford
        return Button {
            confirming = item
        } label: {
            HStack(spacing: 14) {
                Text(item.icon).font(.system(size: 34))
                    .opacity(unlocked ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(item.label).font(.headline)
                            .foregroundStyle(.white.opacity(unlocked ? 1 : 0.6))
                        if !unlocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2).foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    if !unlocked, let need {
                        // 锁着时说的是**档位**，不是分数 —— 这两件事孩子会分得很清
                        Text("要住进「\(need.name)」才能换（\(RollingNumber.grouped(need.at)) 分）")
                            .font(.caption).foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text(afford ? "点一下换" : "还差 \(item.pts - (s?.balance ?? 0)) 分")
                            .font(.caption)
                            .foregroundStyle(afford ? era.accent : .white.opacity(0.45))
                    }
                }
                Spacer()
                if busy == item.id {
                    ProgressView().tint(.white)
                } else {
                    Text("\(item.pts)")
                        .font(.title3.weight(.bold)).monospacedDigit()
                        .foregroundStyle(usable ? .white : .white.opacity(0.35))
                }
            }
            .padding(16)
            .background(.white.opacity(usable ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 18))
        }
        .disabled(!usable || busy != nil)
    }

    private func spend(_ item: State.ShopItem) async {
        busy = item.id; defer { busy = nil }
        do {
            try await Api.spend(item: item.id)
            await store.refresh()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            show("换好了：\(item.icon) \(item.label)")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toast = nil }
        }
    }
}
