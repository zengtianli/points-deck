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
            } else if let slug = UserDefaults.standard.string(forKey: "lesson") {
                // 验证通道：`-lesson <slug>` 直接开某一课，不必先登录。
                // 和 -tab / -palette 同一路数（只影响启动落点，不带任何凭证）——
                // 练习引擎本身不依赖登录:页面自包含，登录只决定分记不记得上。
                // 有了它，「离线能不能做题」这条才验得了:不登录、不联网，照样该能做完一套。
                LessonPreview(slug: slug).environmentObject(store)
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
