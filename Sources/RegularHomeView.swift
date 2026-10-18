import SwiftUI

struct RegularHomeView: View {
    @Binding var tab: Int
    private var titles: [String] {
        [String(localized: "Ledger"), String(localized: "Trends"), String(localized: "Add Points"),
         String(localized: "Rewards"), String(localized: "Account")]
    }
    private let icons = ["list.bullet.rectangle", "chart.line.uptrend.xyaxis", "plusminus.circle.fill", "gift.fill", "person.crop.circle"]
    var body: some View {
        NavigationSplitView {
            List {
                ForEach(0..<titles.count, id: \.self) { index in
                    Button { tab = index } label: {
                        Label(titles[index], systemImage: icons[index]).frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 48).foregroundStyle(tab == index ? TreasuryTheme.accent : .primary)
                    }.buttonStyle(.plain)
                }
            }.navigationTitle(AppIdentity.displayName)
        } detail: {
            NavigationStack {
                Group {
                    switch tab {
                    case 1: TrendView(chartHeight: 260, maxWidth: 1100)
                    case 2: ScoreView()
                    case 3: ShopView(wide: true)
                    case 4: AccountView()
                    default: DeckView()
                    }
                }.navigationTitle(titles[min(max(tab, 0), 4)])
            }
        }
    }
}
