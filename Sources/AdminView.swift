import SwiftUI

/// 管理面 —— 在手机上直接改**服务器上**的配置（2026-08-28 用户要的）。
///
/// 三条硬约束：
/// ① **没有本地副本。** 改的就是服务器那份，保存即生效，别的设备下一秒就看到。
///    存本地副本就要处理「两边同时改了同一条谁赢」，而冲突解错会静默丢改动。
/// ② **校验在服务端。** 这里只做「必填项空着就别让点保存」这种即时反馈；
///    真正的一致性（删掉的商品还被某档解锁引用着之类）由服务端全量交叉校验，
///    不过就整笔拒绝、一个字不写。端上补一份校验 = 第二套判据，迟早和服务端不一致。
/// ③ **整段替换。** 端上本来就持有整段，逐条 patch 要额外处理新增/顺序，不值得。
struct AdminView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var cfg: Config?
    @State private var loading = true
    @State private var err: String?

    private var era: Era { store.state?.era ?? .slum }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let cfg {
                    List {
                        Section {
                            NavigationLink {
                                RuleListView(cfg: cfg).environmentObject(store)
                            } label: {
                                row(String(localized: "Point Rules"), "checklist", String(localized: "\(cfg.rules.count) rules"))
                            }
                            NavigationLink {
                                ShopEditView(cfg: cfg).environmentObject(store)
                            } label: {
                                row(String(localized: "Rewards"), "gift", String(localized: "\(cfg.shop.count) rewards"))
                            }
                            NavigationLink {
                                TierEditView(cfg: cfg).environmentObject(store)
                            } label: {
                                row(String(localized: "Tiers and Benefits"), "stairs", String(localized: "\(cfg.tiers.count) tiers"))
                            }
                        } header: {
                            Text(String(localized: "Changes Apply Only to This Family"))
                        } footer: {
                            Text(String(localized: "Changes are saved to the server and take effect immediately. They appear on the web and your other devices after the next refresh. ")
                                 + String(localized: "This device does not keep a separate copy."))
                        }
                    }
                    .scrollContentBackground(.hidden)
                } else if let err {
                    VStack(spacing: 12) {
                        Text(String(localized: "Couldn’t Load Settings")).font(.headline)
                        Text(err).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(String(localized: "Try Again")) { Task { await load() } }
                    }
                    .padding(30)
                }
            }
            .background(TreasuryTheme.background)
            .navigationTitle(String(localized: "Manage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.light)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func row(_ t: String, _ icon: String, _ badge: String) -> some View {
        HStack {
            Label(t, systemImage: icon)
            Spacer()
            Text(badge).foregroundStyle(.secondary).font(.footnote)
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            cfg = try await Api.config()
            err = nil
        } catch {
            err = error.localizedDescription
        }
    }
}

// ── 通用保存条 ──────────────────────────────────────────────────────────────
/// 保存失败时**把服务端的原话原样显示出来**，不包成「保存失败」。
/// 服务端的拒绝理由是写给人看的中文（「档位『小木屋』解锁的商品 sh-late 不存在 ——
/// 是不是刚把它从兑换表里删了？」），包一层就把最有用的信息扔了。
private struct SaveBar: View {
    let busy: Bool
    let err: String?
    let dirty: Bool
    let save: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let err {
                Text(err)
                    .font(.footnote).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            Button(action: save) {
                HStack {
                    if busy { ProgressView().tint(.white) }
                    Text(dirty ? String(localized: "Save to Server") : String(localized: "No Changes"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(dirty ? Color.accentColor : Color.gray.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .disabled(!dirty || busy)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

// ── 商品 ────────────────────────────────────────────────────────────────────
struct ShopEditView: View {
    @EnvironmentObject var store: Store
    @State var cfg: Config
    @State private var items: [[String: Any]] = []
    @State private var original: String = ""
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField(String(localized: "Icon"), text: bind(i, "icon"))
                                .frame(width: 44)
                            TextField(String(localized: "Name"), text: bind(i, "label"))
                        }
                        HStack {
                            Text(String(localized: "Price")).foregroundStyle(.secondary)
                            TextField(String(localized: "points"), text: bindInt(i, "pts"))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text(String(localized: "points")).foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { idx in items.remove(atOffsets: idx) }
                Button {
                    // 新商品的 id 现生成 —— 让用户自己起 id 只会起重复
                    items.append(["id": "sh-\(UUID().uuidString.prefix(6).lowercased())",
                                  "icon": "🎁", "label": "", "pts": 100])
                } label: {
                    Label(String(localized: "Add Reward"), systemImage: "plus.circle")
                }
            }
            .scrollContentBackground(.hidden)
            SaveBar(busy: busy, err: err, dirty: dump() != original) { Task { await save() } }
        }
        .background(TreasuryTheme.background)
        .navigationTitle(String(localized: "Rewards"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .task {
            items = cfg.shop
            original = dump()
        }
    }

    private func bind(_ i: Int, _ k: String) -> Binding<String> {
        Binding(get: {
            guard items.indices.contains(i) else { return "" }
            return k == "icon" ? (items[i][k] as? String ?? "") : (Api.localizedText(items[i], k) ?? "")
        }, set: { value in
            guard items.indices.contains(i) else { return }
            var item = items[i]
            if k == "icon" { item[k] = value }
            else { Api.setLocalizedText(&item, k, value) }
            items[i] = item
        })
    }

    private func bindInt(_ i: Int, _ k: String) -> Binding<String> {
        Binding(get: { items.indices.contains(i) ? String(items[i][k] as? Int ?? 0) : "" },
                set: { if items.indices.contains(i) { items[i][k] = Int($0) ?? 0 } })
    }

    /// 用序列化后的字符串比对「改没改过」—— 字典数组没法直接 ==
    private func dump() -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: items,
                                                  options: [.sortedKeys]),
                     encoding: .utf8)) ?? ""
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            cfg.revision = try await Api.configPut(kind: "shop", items: items, revision: cfg.revision)
            await store.refresh()
            original = dump()
            err = nil
        } catch {
            err = error.localizedDescription
        }
    }
}

// ── 档位 ────────────────────────────────────────────────────────────────────
struct TierEditView: View {
    @EnvironmentObject var store: Store
    @State var cfg: Config
    @State private var items: [[String: Any]] = []
    @State private var original = ""
    @State private var busy = false
    @State private var err: String?

    private var shopNames: [String: String] {
        Dictionary(uniqueKeysWithValues: cfg.shop.compactMap { s -> (String, String)? in
            guard let id = s["id"] as? String else { return nil }
            return (id, "\(s["icon"] as? String ?? "")\(Api.localizedText(s, "label") ?? "")")
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(i + 1)").font(.caption.bold())
                                .foregroundStyle(.secondary).frame(width: 20)
                            TextField(String(localized: "Home Name"), text: bind(i, "name"))
                        }
                        HStack {
                            Text(String(localized: "Threshold")).foregroundStyle(.secondary)
                            TextField(String(localized: "points"), text: bindInt(i, "at"))
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            Text(String(localized: "points · Welcome Bonus")).foregroundStyle(.secondary)
                            TextField(String(localized: "points"), text: bindInt(i, "bonus"))
                                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                            Text(String(localized: "points")).foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        let un = (items[i]["unlock"] as? [String]) ?? []
                        if !un.isEmpty {
                            Text(String(localized: "Unlocks: \(un.map { shopNames[$0] ?? $0 }.joined(separator: String(localized: ", ")))"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } // 不给删档位：删一档会让所有人的房子往下掉，且已发的贺礼记录跟着错位。
            .scrollContentBackground(.hidden)
            SaveBar(busy: busy, err: err, dirty: dump() != original) { Task { await save() } }
        }
        .background(TreasuryTheme.background)
        .navigationTitle(String(localized: "Tiers and Benefits"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .task {
            items = cfg.tiers
            original = dump()
        }
    }

    private func bind(_ i: Int, _ k: String) -> Binding<String> {
        Binding(get: { items.indices.contains(i) ? (Api.localizedText(items[i], k) ?? "") : "" },
                set: { value in
                    guard items.indices.contains(i) else { return }
                    var item = items[i]
                    Api.setLocalizedText(&item, k, value)
                    items[i] = item
                })
    }

    private func bindInt(_ i: Int, _ k: String) -> Binding<String> {
        Binding(get: { items.indices.contains(i) ? String(items[i][k] as? Int ?? 0) : "" },
                set: { if items.indices.contains(i) { items[i][k] = Int($0) ?? 0 } })
    }

    private func dump() -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: items,
                                                  options: [.sortedKeys]),
                     encoding: .utf8)) ?? ""
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            cfg.revision = try await Api.configPut(kind: "tiers", items: items, revision: cfg.revision)
            await store.refresh()
            original = dump()
            err = nil
        } catch {
            err = error.localizedDescription
        }
    }
}

// ── 规则 ────────────────────────────────────────────────────────────────────
/// 规则按科目分组显示。**只改分值和名字**，不在手机上改 kind/calc ——
/// 那两个字段牵着服务端的计算器（`"15 + floor((n - 48) / 5)"` 这种表达式），
/// 在手机小屏上编辑表达式是给自己找麻烦，而且改错的代价是全家的分都算错。
/// 要动那些，去终端改 JSON 然后 `vps_setup.py pull` 拉回来 commit。
struct RuleListView: View {
    @EnvironmentObject var store: Store
    @State var cfg: Config
    @State private var items: [[String: Any]] = []
    @State private var original = ""
    @State private var busy = false
    @State private var err: String?

    private var subjectName: [String: String] {
        Dictionary(uniqueKeysWithValues: cfg.subjects.map { ($0.id, "\($0.icon) \($0.name)") })
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(cfg.subjects) { sub in
                    let idx = items.indices.filter { items[$0]["subject"] as? String == sub.id }
                    if !idx.isEmpty {
                        Section(subjectName[sub.id] ?? sub.name) {
                            ForEach(idx, id: \.self) { i in
                                HStack {
                                    TextField(String(localized: "Name"), text: bind(i, "label"))
                                    Spacer(minLength: 8)
                                    if (items[i]["kind"] as? String) == "calc" {
                                        // 计算器型没有固定分值，分是服务端按公式算的
                                        Text(String(localized: "Calculated")).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        TextField(String(localized: "points"), text: bindInt(i, "pts"))
                                            .keyboardType(.numbersAndPunctuation)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 64)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            SaveBar(busy: busy, err: err, dirty: dump() != original) { Task { await save() } }
        }
        .background(TreasuryTheme.background)
        .navigationTitle(String(localized: "Point Rules"))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .task {
            items = cfg.rules
            original = dump()
        }
    }

    private func bind(_ i: Int, _ k: String) -> Binding<String> {
        Binding(get: { items.indices.contains(i) ? (Api.localizedText(items[i], k) ?? "") : "" },
                set: { value in
                    guard items.indices.contains(i) else { return }
                    var item = items[i]
                    Api.setLocalizedText(&item, k, value)
                    items[i] = item
                })
    }

    private func bindInt(_ i: Int, _ k: String) -> Binding<String> {
        Binding(get: { items.indices.contains(i) ? String(items[i][k] as? Int ?? 0) : "" },
                set: { if items.indices.contains(i) { items[i][k] = Int($0) ?? 0 } })
    }

    private func dump() -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: items,
                                                  options: [.sortedKeys]),
                     encoding: .utf8)) ?? ""
    }

    private func save() async {
        busy = true; defer { busy = false }
        do {
            cfg.revision = try await Api.configPut(kind: "rules", items: items, revision: cfg.revision)
            await store.refresh()
            original = dump()
            err = nil
        } catch {
            err = error.localizedDescription
        }
    }
}
