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
