import SwiftUI

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
    private var title: String { kind == "rules" ? "记分项目" : "兑换奖励" }

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
                                Text(item["label"] as? String ?? "项目").foregroundStyle(.primary)
                                Text(item["archived"] as? Bool == true ? "已归档 · 可恢复" : "\(item["pts"] as? Int ?? 0) 分")
                                    .foregroundStyle(.secondary).font(.caption)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.frame(minHeight: 48)
                    }.buttonStyle(.plain)
                    #if !os(iOS)
                    Button("上移", systemImage: "arrow.up") {
                        if index > 0 { items.swapAt(index, index - 1); dirty = true }
                    }.disabled(index == 0).buttonStyle(.borderless).frame(minHeight: 48)
                    Button("下移", systemImage: "arrow.down") {
                        if index + 1 < items.count { items.swapAt(index, index + 1); dirty = true }
                    }.disabled(index + 1 == items.count).buttonStyle(.borderless).frame(minHeight: 48)
                    #endif
                    }
                }.onMove { indices, target in items.move(fromOffsets: indices, toOffset: target); dirty = true }
                    .onDelete { indices in for index in indices { items[index]["archived"] = true }; dirty = true }
                if let error {
                    Text(error).foregroundStyle(.red)
                    if conflict {
                        Text("本地编辑仍保留。读取最新配置后，确认合并再保存。").font(.footnote)
                        Button("读取最新配置") { Task { await prepareMerge() } }
                        if serverCopy != nil {
                            Button("合并：保留本地改动和新增远端项目") { merge() }
                        }
                    } else if config == nil { Button("重试") { Task { await load() } } }
                }
                Section {
                    Text("归档保留历史，编辑可恢复；列表编辑或上下箭头调整常用顺序。").font(.footnote).foregroundStyle(.secondary)
                    Button("更多设置（高级规则与档位）") { advanced = true }
                }
            }.navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    #if os(iOS)
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                    #endif
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("新建", systemImage: "plus") { add() }.disabled(config == nil)
                        Button(busy ? "保存中" : "保存") { Task { await save() } }.disabled(busy || !dirty || conflict)
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
            await store.refresh(); store.showNotice("已保存\(title)")
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
        error = "已合并，本地修改的同名项目优先；请检查后点保存。"
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
        _label = State(initialValue: draft.item["label"] as? String ?? "")
        _points = State(initialValue: String(abs(draft.item["pts"] as? Int ?? 1)))
        _negative = State(initialValue: draft.negative)
        _icon = State(initialValue: draft.item["icon"] as? String ?? "star.fill")
        _color = State(initialValue: draft.item["color"] as? String ?? "mint")
        _detail = State(initialValue: draft.item["description"] as? String ?? "")
        _archived = State(initialValue: draft.item["archived"] as? Bool ?? false)
    }
    private var simple: Bool { draft.kind == "shop" || (draft.item["kind"] as? String ?? "fixed") == "fixed" }
    var body: some View {
        NavigationStack {
            Form {
                TextField(draft.kind == "rules" ? "项目名" : "奖励名", text: $label)
                if simple {
                    if draft.kind == "rules" {
                        Picker("类型", selection: $negative) { Text("加分").tag(false); Text("减分").tag(true) }.pickerStyle(.segmented)
                    }
                    TextField(draft.kind == "rules" ? "正整数分值" : "所需积分", text: $points).keyboardType(.numberPad)
                } else { Text("这是参数型项目。原公式保留，分值请在「更多设置」中编辑。").font(.footnote) }
                Section("图标") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52))]) {
                        ForEach(icons, id: \.self) { symbol in
                            Button { icon = symbol } label: {
                                CatalogIcon(icon: symbol).overlay { if icon == symbol { RoundedRectangle(cornerRadius: 14).stroke(TreasuryTheme.accent, lineWidth: 2) } }
                            }.buttonStyle(.plain).accessibilityLabel(symbol)
                        }
                    }
                }
                if draft.kind == "shop" { TextField("说明（可选）", text: $detail, axis: .vertical) }
                else {
                    Picker("颜色", selection: $color) { Text("薄荷").tag("mint"); Text("天空").tag("blue"); Text("暖阳").tag("orange"); Text("紫藤").tag("purple") }
                }
                Toggle("归档（保留历史）", isOn: $archived)
                Text("只影响后续记分或兑换，已有流水保留当时的名称和积分。").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle(draft.kind == "rules" ? "编辑项目" : "编辑奖励")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .primaryAction) {
                        Button("完成") {
                            var item = draft.item
                            item["label"] = label.trimmingCharacters(in: .whitespacesAndNewlines)
                            if simple { item["pts"] = abs(Int(points) ?? 0) * (draft.kind == "rules" && negative ? -1 : 1) }
                            item["icon"] = icon; item["color"] = color; item["archived"] = archived; item["description"] = detail
                            onSave(item); dismiss()
                        }.disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (simple && (Int(points) ?? 0) <= 0))
                    }
                }
        }.treasurySheetSize(minHeight: 440)
    }
}
