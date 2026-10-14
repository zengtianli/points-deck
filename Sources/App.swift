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

    init() {
        #if os(iOS)
        if ProductBasicsSelfTest.requested { ProductBasicsSelfTest.prepareIsolation() }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if os(iOS)
                if ProductBasicsSelfTest.requested { ProductBasicsSelfTestView() }
                else { RootView() }
                #else
                RootView()
                #endif
            }
                .appLifecycleMobile(productID: "points-deck", channel: MobileProductLifecycle.channel, configuration: MobileProductLifecycle.configuration, placement: .settings)
                .environmentObject(store)
        }
        #if os(macOS) || os(visionOS)
        // Mac 默认窗口只有 900×450，看板摆不开；Vision Pro 的默认窗口偏扁。给一个看板正好铺开的尺寸。
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var lifecycle: MobileLifecycleModel
    @ObservedObject private var preferences = TreasuryPreferences.shared
    @State private var settings = false
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
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button { settings = true } label: { Label("设置", systemImage: "gearshape") }
                Button { refreshFromShortcut() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .disabled(store.phase != .loggedIn)
                    .keyboardShortcut(preferences.refreshBinding)
            }.padding(.horizontal)
        }
        .sheet(isPresented: $settings) { TreasurySettingsView(preferences: preferences, lifecycle: lifecycle) }
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
            guard phase == .active, store.phase == .loggedIn else { return }
            Task { await store.refresh() }
        }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 540)
        #endif
    }
    private func refreshFromShortcut() {
        // The keyboard and ordinary refresh button share the actual Store refresh path.
        Task { await TreasuryActions.refresh(store) }
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
