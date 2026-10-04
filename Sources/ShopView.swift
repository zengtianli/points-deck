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
                Text("当前积分 \(store.state?.balance ?? 0)").font(.title2.bold()).monospacedDigit()
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
                                Text("\(item.pts) 分").font(.title2.bold()).monospacedDigit()
                                if !(store.state?.isUnlocked(item.id) ?? false) {
                                    Text("需达到\(store.state?.tierRequiring(item.id)?.name ?? "指定等级")").font(.caption)
                                } else if (store.state?.balance ?? 0) < item.pts {
                                    Text("还差 \(item.pts - (store.state?.balance ?? 0)) 分").font(.caption)
                                } else { Text("可兑换").font(.caption).foregroundStyle(TreasuryTheme.accent) }
                            }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 110).padding(12)
                                .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).disabled(busy == item.id)
                    }
                }
                if (store.state?.shop ?? []).filter({ !$0.archived }).isEmpty {
                    ContentUnavailableView("设置第一个奖励", systemImage: "gift", description: Text("点「新建」，设置家庭约定的奖励和所需积分。"))
                }
            }.padding(20).contentWidth(1100)
        }.background(TreasuryTheme.background).navigationTitle("兑换")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("新建", systemImage: "plus") { manager = CatalogPresentation(startNew: true) }
                    Button("管理", systemImage: "slider.horizontal.3") { manager = CatalogPresentation(startNew: false) }
                }
            }
            .sheet(item: $manager) { request in CatalogManager(kind: "shop", startNew: request.startNew) }
            .sheet(item: $confirming) { item in
                NavigationStack {
                    Form {
                        Text(item.label).font(.title2.bold())
                        if !item.detail.isEmpty { Text(item.detail) }
                        LabeledContent("所需积分", value: "\(item.pts)")
                        LabeledContent("兑换后余额", value: "\((store.state?.balance ?? 0) - item.pts)")
                        if let error { Text(error).foregroundStyle(.red) }
                        Button(busy == nil ? "确认兑换" : "兑换中") { Task { await spend(item) } }
                            .disabled(busy != nil || (store.state?.balance ?? 0) < item.pts || !(store.state?.isUnlocked(item.id) ?? false))
                    }.navigationTitle("确认兑换")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { confirming = nil } } }
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
            store.showNotice("已兑换：\(item.label)", entryID: receipt.entryID)
        } catch {
            self.error = "未兑换：\(error.localizedDescription)"
            if (error as? Api.Failure)?.status == 409 {
                await store.refresh()
                self.error = "奖励价格或条件已变化，请取消后重新确认。"
            }
        }
    }
}
