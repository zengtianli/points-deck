import SwiftUI

@main
struct PointsDeckApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if UserDefaults.standard.bool(forKey: "widgetpreview") {
                WidgetPreviewView()
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
