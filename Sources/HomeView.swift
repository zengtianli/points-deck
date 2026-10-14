import SwiftUI

enum TreasuryTheme {
    static let background = Color(hex: 0xF8F7F2)
    static let accent = Color(hex: 0x257F70)
    static let card = Color.white
}

/// visionOS 的系统分段控件使用玻璃材质文字，在浅色账本上会白字白底。
/// 本端使用有明确对比度的选择按钮；其余平台保留原系统控件。
struct TreasuryChoice<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value)]

    var body: some View {
        #if os(visionOS)
        HStack(spacing: 6) {
            ForEach(options, id: \.1) { label, value in
                Button { selection = value } label: {
                    Text(label).font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(selection == value ? Color.white : Color(hex: 0x25352F))
                        .background(selection == value ? TreasuryTheme.accent : Color.white,
                                    in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                    .accessibilityLabel(label)
                    .accessibilityHint(title)
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        #else
        Picker(title, selection: $selection) {
            ForEach(options, id: \.1) { label, value in Text(label).tag(value) }
        }.pickerStyle(.segmented)
        #endif
    }
}

struct HomeView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var preferences = TreasuryPreferences.shared
    @State private var tab = UserDefaults.standard.object(forKey: "tab") != nil ? UserDefaults.standard.integer(forKey: "tab") : TreasuryPreferences.shared.startTab
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
            if preferences.celebrations, let name = store.promoted { CelebrationView(houseName: name, era: store.state?.era ?? .slum) { store.promoted = nil } }
        }
        .onAppear { LaneSignal.ready("treasury") }
    }
}
