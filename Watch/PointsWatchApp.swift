import SwiftUI

/// Apple Watch 版：孩子抬腕看的**只读**一面 —— 余额、住在哪一档、还差多少升级、最近 10 笔。
///
/// 和 iPhone 是同一个账本、同一份 Store / Api / LedgerState，不另算任何数。
/// 第一版不做兑换（手表上太容易误触，花掉的分不好退）和家长记账（每次都要在表上输家长密码）。
/// 登录态由 iPhone 递过来（WatchSessionReceiver）；模拟器验收照旧用 -api_base / -dev_user / -dev_pw。
@main
struct PointsWatchApp: App {
    @StateObject private var store = Store()
    @StateObject private var link = WatchSessionReceiver()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(store)
                .onChange(of: link.change) { _, change in
                    guard let change else { return }
                    if change.signedIn {
                        Task {
                            if store.phase == .loggedIn { await store.refresh() } else { await store.restore() }
                        }
                    } else {
                        store.dropSession()
                    }
                }
        }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.phase {
            case .checking:  ProgressView()
            case .loggedOut: WatchSignedOutView()
            case .loggedIn:  WatchHomeView()
            }
        }
        .task { await store.restore() }
        // 手表不开推送长连接（Store.livePush）：抬腕回到前台就拉一次
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if store.phase == .loggedIn { await store.refresh() }
                else if store.phase == .loggedOut { await store.restore() }
            }
        }
    }
}

/// 没有登录态：只说一句话，指向 iPhone。手表上不放输入框。
struct WatchSignedOutView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Era.garden.accent)
                VStack(spacing: 2) {
                    Text("在 iPhone 上登录")
                    Text(AppIdentity.displayName)
                }
                .font(.headline)
                .multilineTextAlignment(.center)
                Text("登录后手表会自动同步")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .containerBackground(Era.garden.background, for: .navigation)
        }
    }
}
