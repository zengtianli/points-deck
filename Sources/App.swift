import SwiftUI

@main
struct PointsDeckApp: App {
    @StateObject private var store = Store()
    @StateObject private var session = ParentSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(session)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: ParentSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if UserDefaults.standard.bool(forKey: "widgetpreview") {
                WidgetPreviewView()
            } else if UserDefaults.standard.bool(forKey: "palette") {
                PalettePreview()
            } else {
            switch store.phase {
            case .checking:  SplashView()
            case .loggedOut: LoginView()
            case .loggedIn:  HomeView()
            }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.phase)
        .task { await store.restore() }
        // 回到前台就刷一次 —— 分是家长在别处加的，孩子这边不刷就看不到；
        // 升档的庆祝也靠这一下。
        .onChange(of: scenePhase) { _, phase in
            // 家长会话的自动上锁挂在这 —— 放桌上离开是最现实的泄漏场景
            session.scenePhaseChanged(to: phase)
            guard phase == .active, store.phase == .loggedIn else { return }
            Task { await store.refresh() }
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Era.slum.background.ignoresSafeArea()
            ProgressView().tint(.white).scaleEffect(1.3)
        }
    }
}
