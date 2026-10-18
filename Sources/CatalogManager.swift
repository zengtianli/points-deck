import SwiftUI

/// The sheet receives the requested mode as one presentation value.
struct CatalogPresentation: Identifiable {
    let id = UUID()
    let startNew: Bool
    var negative = false
}

/// 普通项目只编辑名称、分值与外观；原字典其余字段原样保留。
struct CatalogManager: View {
    let kind: String
    var startNew = false
    var negative = false
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var config: Config?
    @State private var items: [[String: Any]] = []
    @State private var editing: CatalogDraft?
    @State private var advanced = false
    @State private var busy = false
    @State private var dirty = false
    @State private var error: String?
    @State private var conflict = false
    @State private var serverCopy: Config?
    private var title: String { kind == "rules" ? String(localized: "Point Rules") : String(localized: "Rewards") }

    var body: some View {
        NavigationStack {
            List {
                if config == nil && error == nil { ProgressView() }
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    HStack {
                    Button {
                        editing = CatalogDraft(item: item, kind: kind)
                    } label: {
                        HStack {
                            CatalogIcon(icon: item["icon"] as? String ?? (kind == "rules" ? "star.fill" : "gift.fill"))
                            VStack(alignment: .leading) {
                                Text(Api.localizedText(item, "label") ?? String(localized: "Rule")).foregroundStyle(.primary)
                                Text(item["archived"] as? Bool == true ? String(localized: "Archived · Can Be Restored") : String(localized: "\(item["pts"] as? Int ?? 0) points"))
                                    .foregroundStyle(.secondary).font(.caption)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.frame(minHeight: 48)
                    }.buttonStyle(.plain)
                    #if !os(iOS)
                    Button(String(localized: "Move Up"), systemImage: "arrow.up") {
                        if index > 0 { items.swapAt(index, index - 1); dirty = true }
                    }.disabled(index == 0).buttonStyle(.borderless).frame(minHeight: 48)
                    Button(String(localized: "Move Down"), systemImage: "arrow.down") {
                        if index + 1 < items.count { items.swapAt(index, index + 1); dirty = true }
                    }.disabled(index + 1 == items.count).buttonStyle(.borderless).frame(minHeight: 48)
                    #endif
                    }
                }.onMove { indices, target in items.move(fromOffsets: indices, toOffset: target); dirty = true }
                    .onDelete { indices in for index in indices { items[index]["archived"] = true }; dirty = true }
                if let error {
                    Text(error).foregroundStyle(.red)
                    if conflict {
                        Text(String(localized: "Your edits are still here. Load the latest settings, review the merge, then save.")).font(.footnote)
                        Button(String(localized: "Load Latest Settings")) { Task { await prepareMerge() } }
                        if serverCopy != nil {
                            Button(String(localized: "Merge: Keep My Edits and New Server Items")) { merge() }
                        }
                    } else if config == nil { Button(String(localized: "Try Again")) { Task { await load() } } }
                }
                Section {
                    Text(String(localized: "Archiving preserves past transactions. Edit an item to restore it. Reorder the list using Edit or the arrow buttons.")).font(.footnote).foregroundStyle(.secondary)
                    Button(String(localized: "More Settings: Advanced Rules and Tiers")) { advanced = true }
                }
            }.navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } }
                    #if os(iOS)
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                    #endif
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(String(localized: "New"), systemImage: "plus") { add() }.disabled(config == nil)
                        Button(busy ? String(localized: "Saving…") : String(localized: "Save")) { Task { await save() } }.disabled(busy || !dirty || conflict)
                    }
                }
                .task { await load() }
                .sheet(item: $editing) { draft in
                    CatalogEditor(draft: draft) { item in
                        if let index = items.firstIndex(where: { ($0["id"] as? String) == (item["id"] as? String) }) { items[index] = item }
                        else { items.append(item) }
                        dirty = true
                    }
                }
                .sheet(isPresented: $advanced) { AdminView() }
        }.treasurySheetSize(minHeight: 480)
    }
    private func add() {
        let item: [String: Any] = ["id": "custom-" + UUID().uuidString.lowercased(), "label": "", "pts": 1,
                                   "subject": config?.subjects.first?.id ?? "", "kind": "fixed",
                                   "icon": kind == "rules" ? "star.fill" : "gift.fill",
                                   "requires_tier": false, "color": "mint"]
        editing = CatalogDraft(item: item, kind: kind, negative: negative)
    }
    private func load() async {
        do {
            let value = try await Api.config()
            config = value; items = kind == "rules" ? value.rules : value.shop
            error = nil
            if startNew { add() }
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard let config else { return }
        busy = true; defer { busy = false }
        do {
            let revision = try await Api.configPut(kind: kind, items: items, revision: config.revision)
            self.config?.revision = revision
            dirty = false; error = nil
            await store.refresh(); store.showNotice(String(localized: "Saved \(title)"))
        } catch {
            self.error = error.localizedDescription
            conflict = (error as? Api.Failure)?.status == 409
        }
    }
    private func prepareMerge() async {
        do { serverCopy = try await Api.config() }
        catch { self.error = error.localizedDescription }
    }
    private func merge() {
        guard let latest = serverCopy, let base = config else { return }
        let previous = kind == "rules" ? base.rules : base.shop
        let remote = kind == "rules" ? latest.rules : latest.shop
        // 未被本地改动的记录采用远端；同记录冲突明确保留本地，远端新增一并加入。
        let changed = Set(items.compactMap { item -> String? in
            let id = item["id"] as? String
            let original = previous.first { ($0["id"] as? String) == id }
            return NSDictionary(dictionary: original ?? [:]).isEqual(to: item) ? nil : id
        })
        items = items.map { item in
            guard let id = item["id"] as? String, !changed.contains(id) else { return item }
            return remote.first { ($0["id"] as? String) == id } ?? item
        }
        let ids = Set(items.compactMap { $0["id"] as? String })
        items += remote.filter { !ids.contains($0["id"] as? String ?? "") }
        config = latest; conflict = false; serverCopy = nil; dirty = true
        error = String(localized: "Merged. Your edits take priority for matching items. Review the result, then save.")
    }
}

struct CatalogDraft: Identifiable {
    let id: String
    var item: [String: Any]
    let kind: String
    var negative: Bool
    init(item: [String: Any], kind: String, negative: Bool? = nil) {
        self.item = item; self.kind = kind; self.id = item["id"] as? String ?? UUID().uuidString
        self.negative = negative ?? ((item["pts"] as? Int ?? 0) < 0)
    }
}

struct CatalogEditor: View {
    let draft: CatalogDraft
    let onSave: ([String: Any]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var points: String
    @State private var negative: Bool
    @State private var icon: String
    @State private var color: String
    @State private var detail: String
    @State private var archived: Bool
    private let icons = ["star.fill", "book.fill", "heart.fill", "sparkles", "figure.walk", "music.note", "house.fill", "gift.fill"]
    init(draft: CatalogDraft, onSave: @escaping ([String: Any]) -> Void) {
        self.draft = draft; self.onSave = onSave
        _label = State(initialValue: Api.localizedText(draft.item, "label") ?? "")
        _points = State(initialValue: String(abs(draft.item["pts"] as? Int ?? 1)))
        _negative = State(initialValue: draft.negative)
        _icon = State(initialValue: draft.item["icon"] as? String ?? "star.fill")
        _color = State(initialValue: draft.item["color"] as? String ?? "mint")
        _detail = State(initialValue: Api.localizedText(draft.item, "description") ?? "")
        _archived = State(initialValue: draft.item["archived"] as? Bool ?? false)
    }
    private var simple: Bool { draft.kind == "shop" || (draft.item["kind"] as? String ?? "fixed") == "fixed" }
    var body: some View {
        NavigationStack {
            Form {
                TextField(draft.kind == "rules" ? String(localized: "Rule Name") : String(localized: "Reward Name"), text: $label)
                if simple {
                    if draft.kind == "rules" {
                        TreasuryChoice(title: String(localized: "Type"), selection: $negative, options: [(String(localized: "Add Points"), false), (String(localized: "Deduct Points"), true)])
                    }
                    TextField(draft.kind == "rules" ? String(localized: "Positive Whole Number") : String(localized: "Points Required"), text: $points).keyboardType(.numberPad)
                } else { Text(String(localized: "This rule uses a formula. The formula is preserved. Edit its points in More Settings.")).font(.footnote) }
                Section(String(localized: "Icon")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))]) {
                        ForEach(icons, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                CatalogIcon(icon: symbol).overlay { if icon == symbol { RoundedRectangle(cornerRadius: 14).stroke(TreasuryTheme.accent, lineWidth: 2) } }
                            }.buttonStyle(.plain).accessibilityLabel(symbol)
                        }
                    }
                }
                if draft.kind == "shop" { TextField(String(localized: "Description (Optional)"), text: $detail, axis: .vertical) }
                else {
                    Picker(String(localized: "Color"), selection: $color) { Text(String(localized: "Mint")).tag("mint"); Text(String(localized: "Sky")).tag("blue"); Text(String(localized: "Sunshine")).tag("orange"); Text(String(localized: "Wisteria")).tag("purple") }
                }
                Toggle(String(localized: "Archive (Keep History)"), isOn: $archived)
                Text(String(localized: "Changes apply to future point entries and redemptions. Past transactions keep their original names and points.")).font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle(draft.kind == "rules" ? String(localized: "Edit Rule") : String(localized: "Edit Reward"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button(String(localized: "Done")) {
                            var item = draft.item
                            let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                            if cleanedLabel != (Api.localizedText(item, "label") ?? "") {
                                Api.setLocalizedText(&item, "label", cleanedLabel)
                            }
                            if simple { item["pts"] = abs(Int(points) ?? 0) * (draft.kind == "rules" && negative ? -1 : 1) }
                            item["icon"] = icon; item["color"] = color; item["archived"] = archived
                            if detail != (Api.localizedText(item, "description") ?? "") {
                                Api.setLocalizedText(&item, "description", detail)
                            }
                            onSave(item); dismiss()
                        }.disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (simple && (Int(points) ?? 0) <= 0))
                    }
                }
        }.treasurySheetSize(minHeight: 440)
    }
}
