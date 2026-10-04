import SwiftUI

enum TreasuryTheme {
    static let background = Color(hex: 0xF8F7F2)
    static let accent = Color(hex: 0x257F70)
    static let card = Color.white
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")
    var body: some View {
        Group {
            #if os(iOS)
            TabView(selection: $tab) {
                NavigationStack { DeckView().navigationTitle("账本") }
                    .tabItem { Label("账本", systemImage: "list.bullet.rectangle") }.tag(0)
                NavigationStack { TrendView().navigationTitle("走势") }
                    .tabItem { Label("走势", systemImage: "chart.line.uptrend.xyaxis") }.tag(1)
                NavigationStack { ScoreView() }
                    .tabItem { Label("加分", systemImage: "plusminus.circle.fill") }.tag(2)
                NavigationStack { ShopView() }
                    .tabItem { Label("兑换", systemImage: "gift.fill") }.tag(3)
                NavigationStack { AccountView() }
                    .tabItem { Label("账户", systemImage: "person.crop.circle") }.tag(4)
            }
            .tabViewStyle(.tabBarOnly)
            #else
            RegularHomeView(tab: $tab)
            #endif
        }
        .background(TreasuryTheme.background).tint(TreasuryTheme.accent).preferredColorScheme(.light)
        #if os(visionOS)
        .foregroundStyle(Color(hex: 0x25352F))
        #endif
        .safeAreaInset(edge: .bottom) {
            if store.offline {
                Text("离线：显示上次账本，恢复网络后刷新；当前无法记账。")
                    .font(.caption).padding(10).frame(maxWidth: .infinity).background(.regularMaterial)
            }
            if let message = store.notice {
                HStack {
                    Text(message).font(.subheadline)
                    Spacer()
                    if let id = store.undoEntryID {
                        Button("撤销") { Task { await store.undoEntry(id) } }.frame(minWidth: 48, minHeight: 48)
                    }
                }.padding(.horizontal, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 12)
            }
        }
        .overlay {
            if let name = store.promoted { CelebrationView(houseName: name, era: store.state?.era ?? .slum) { store.promoted = nil } }
        }
        .onAppear { LaneSignal.ready("treasury") }
    }
}
