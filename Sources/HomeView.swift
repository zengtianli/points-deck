import SwiftUI

/// 三个 tab + 右上角家长入口。
///
/// 为什么是 TabView 而不是一屏到底：孩子面的三块内容(账本/走势/兑换)是**并列**的，
/// 不是递进的 —— 塞进一个 ScrollView 会让「还差 N 分」被推到屏外，而那是核心钩子。
/// 家长面不占 tab：它不是孩子会点的东西，放右上角、且要过 Face ID。
struct HomeView: View {
    @EnvironmentObject var store: Store
    // 验证通道：`-tab 1` / `-parent 1` 直接落到某一屏，方便 headless 截图核对。
    // 和 -api_base 一样，只在显式传了 launch 参数时生效。
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")
    @State private var showParent = UserDefaults.standard.bool(forKey: "parent")

    private var era: Era { store.state?.era ?? .slum }

    var body: some View {
        ZStack {
            era.background.ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: era)   // 升档 = 场景切换，不是刷新

            VStack(spacing: 0) {
                topBar
                TabView(selection: $tab) {
                    DeckView().tag(0)
                    TrendView().tag(1)
                    ShopView().tag(2)
                    WrongView().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                tabBar
            }
        }
        .sheet(isPresented: $showParent) { ParentView().environmentObject(store) }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.state?.nick ?? "—").font(.headline).foregroundStyle(.white)
                Text(store.state?.houseName ?? "—").font(.subheadline).foregroundStyle(era.accent)
            }
            Spacer()
            Button { showParent = true } label: {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityLabel("家长记账")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            item(0, "账本", "list.bullet.rectangle")
            item(1, "走势", "chart.line.uptrend.xyaxis")
            item(2, "兑换", "gift")
            item(3, "错题", "camera")
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.white.opacity(0.08))
    }

    private func item(_ i: Int, _ title: String, _ icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { tab = i }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18))
                Text(title).font(.caption2)
            }
            .foregroundStyle(tab == i ? era.accent : .white.opacity(0.5))
            .frame(maxWidth: .infinity)
        }
    }
}
