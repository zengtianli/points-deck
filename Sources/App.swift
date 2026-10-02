import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct PointsDeckApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(LaneAppDelegate.self) private var laneDelegate
    #endif
    @StateObject private var store = Store()
    @StateObject private var session = ParentSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(session)
        }
        #if os(macOS) || os(visionOS)
        // Mac 默认窗口只有 900×450，看板摆不开；Vision Pro 的默认窗口偏扁。给一个看板正好铺开的尺寸。
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var session: ParentSession
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var hSize
    /// 只认 iPad 的 regular：iPhone Pro Max 横屏时尺寸类也是 regular，但那块屏摆不下侧栏 + 看板，
    /// 仍走原来的窄屏布局。
    private var wide: Bool { hSize == .regular && UIDevice.current.userInterfaceIdiom == .pad }
    #else
    private let wide = true      // Mac 与 Vision Pro 的窗口一律按宽屏排
    #endif

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
        .environment(\.wideLayout, wide)
        .animation(.easeInOut(duration: 0.35), value: store.phase)
        .task {
            LaneSignal.applyOrientation()
            LaneSignal.applyWindowFrame()
            WatchLink.shared.activate()
            await store.restore()
        }
        // 回到前台就刷一次 —— 分是家长在别处加的，孩子这边不刷就看不到；
        // 升档的庆祝也靠这一下。
        .onChange(of: scenePhase) { _, phase in
            // 家长会话的自动上锁挂在这 —— 放桌上离开是最现实的泄漏场景
            session.scenePhaseChanged(to: phase)
            guard phase == .active, store.phase == .loggedIn else { return }
            Task { await store.refresh() }
        }
        #if os(macOS)
        // Mac 窗口晾着时 scenePhase 可能一直 active：另数「多久没操作」，同样 10 分钟上锁
        .modifier(MacIdleLock())
        .frame(minWidth: 760, minHeight: 540)
        #endif
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            #if !os(visionOS)
            Era.slum.background.ignoresSafeArea()
            #endif
            ProgressView().tint(.white).scaleEffect(1.3)
        }
    }
}
