import SwiftUI

struct ShopView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var busy: String?
    @State private var confirming: LedgerState.ShopItem?
    @State private var requestID = UUID().uuidString
    @State private var expectedRevision = ""
    @State private var manager: CatalogPresentation?
    @State private var error: String?
    var wide = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Current points: \(store.state?.balance ?? 0)").font(.title2.bold()).monospacedDigit()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 290 : 145), spacing: 14)], spacing: 14) {
                    ForEach((store.state?.shop ?? []).filter { !$0.archived }) { item in
                        Button {
                            requestID = UUID().uuidString
                            expectedRevision = store.state?.revision ?? ""
                            error = nil; confirming = item
                        } label: {
                            VStack(spacing: 10) {
                                CatalogIcon(icon: item.icon.isEmpty ? "gift.fill" : item.icon)
                                Text(item.label).font(.headline).multilineTextAlignment(.center)
                                Text("\(item.pts) points").font(.title2.bold()).monospacedDigit()
                                if !(store.state?.isUnlocked(item.id) ?? false) {
                                    Text("Requires \(store.state?.tierRequiring(item.id)?.name ?? String(localized: "the required tier"))").font(.caption)
                                } else if (store.state?.balance ?? 0) < item.pts {
                                    Text("\(item.pts - (store.state?.balance ?? 0)) more points needed").font(.caption)
                                } else { Text("Available").font(.caption).foregroundStyle(TreasuryTheme.accent) }
                            }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 110).padding(12)
                                .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).disabled(busy == item.id)
                    }
                }
                if (store.state?.shop ?? []).filter({ !$0.archived }).isEmpty {
                    ContentUnavailableView("Set up your first reward", systemImage: "gift", description: Text("Tap New to add a family reward and its points cost."))
                }
            }.padding(20).contentWidth(1100)
        }.background(TreasuryTheme.background).navigationTitle("Rewards")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("New", systemImage: "plus") { manager = CatalogPresentation(startNew: true) }
                    Button("Manage", systemImage: "slider.horizontal.3") { manager = CatalogPresentation(startNew: false) }
                }
            }
            .sheet(item: $manager) { request in CatalogManager(kind: "shop", startNew: request.startNew) }
            .sheet(item: $confirming) { item in
                NavigationStack {
                    Form {
                        Text(item.label).font(.title2.bold())
                        if !item.detail.isEmpty { Text(item.detail) }
                        LabeledContent("Points required", value: "\(item.pts)")
                        LabeledContent("Balance after redemption", value: "\((store.state?.balance ?? 0) - item.pts)")
                        if let error { Text(error).foregroundStyle(.red) }
                        Button(busy == nil ? String(localized: "Confirm redemption") : String(localized: "Redeeming…")) { Task { await spend(item) } }
                            .disabled(busy != nil || (store.state?.balance ?? 0) < item.pts || !(store.state?.isUnlocked(item.id) ?? false))
                    }.navigationTitle("Confirm redemption")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { confirming = nil } } }
                }.treasurySheetSize(minHeight: 300)
            }
            .refreshable { await store.refresh() }
    }
    private func spend(_ item: LedgerState.ShopItem) async {
        busy = item.id; defer { busy = nil }
        do {
            let receipt = try await Api.transaction("api/spend", body: ["item": item.id, "expected_pts": item.pts,
                                                                       "expected_revision": expectedRevision], requestID: requestID)
            await store.refresh(); confirming = nil
            store.showNotice(String(localized: "Redeemed: \(item.label)"), entryID: receipt.entryID)
        } catch {
            self.error = String(localized: "Not redeemed: \(error.localizedDescription)")
            if (error as? Api.Failure)?.status == 409 {
                await store.refresh()
                self.error = String(localized: "The reward's cost or requirements have changed. Cancel and confirm again.")
            }
        }
    }
}
