import SwiftUI

struct ScoreView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var negative = false
    @State private var busy = Set<String>()
    @State private var retries: [String: String] = [:]
    @State private var picked: LedgerState.Rule?
    @State private var manager = false
    @State private var create = false
    @State private var temporary = false
    private var rules: [LedgerState.Rule] {
        (store.state?.rules ?? []).filter { !$0.archived && (negative ? $0.pts < 0 : $0.pts >= 0) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("当前积分 \(store.state?.balance ?? 0)").font(.title2.bold()).monospacedDigit()
                TreasuryChoice(title: "记分类型", selection: $negative, options: [("加分", false), ("减分", true)])
                if rules.isEmpty {
                    ContentUnavailableView("还没有\(negative ? "减分" : "加分")项目", systemImage: "plus.circle",
                                           description: Text("点右上角「新建」，设置自己的名称和积分。"))
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 290 : 145), spacing: 14)], spacing: 14) {
                    ForEach(rules) { rule in
                        Button {
                            if rule.kind == "fixed" { Task { await record(rule) } }
                            else { picked = rule }
                        } label: {
                            VStack(spacing: 10) {
                                CatalogIcon(icon: rule.icon, tint: negative ? .orange : CatalogIcon.color(rule.color))
                                Text(rule.label).font(.headline).multilineTextAlignment(.center)
                                if busy.contains(rule.id) { ProgressView() }
                                else if retries[rule.id] != nil { Text("未记入，重试").font(.subheadline).foregroundStyle(.orange) }
                                else {
                                    Text(rule.kind == "fixed" ? "\(rule.pts >= 0 ? "+" : "−")\(abs(rule.pts))" : "填写\(rule.unit.isEmpty ? "参数" : rule.unit)")
                                        .font(.title2.bold()).monospacedDigit()
                                }
                            }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 110).padding(12)
                                .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).disabled(busy.contains(rule.id))
                            .accessibilityLabel("\(rule.label)，\(rule.pts)积分")
                    }
                }
                Button("临时记一笔", systemImage: "square.and.pencil") { temporary = true }
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.bordered)
            }.padding(20).contentWidth(1100)
        }.background(TreasuryTheme.background).navigationTitle("加分")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("新建", systemImage: "plus") { create = true; manager = true }
                    Button("管理", systemImage: "slider.horizontal.3") { create = false; manager = true }
                }
            }
            .sheet(isPresented: $manager) { CatalogManager(kind: "rules", startNew: create, negative: negative) }
            .sheet(item: $picked) { ParameterScoreView(rule: $0) }
            .sheet(isPresented: $temporary) { TemporaryScoreView() }
            .refreshable { await store.refresh() }
    }
    private func record(_ rule: LedgerState.Rule) async {
        guard !busy.contains(rule.id) else { return }
        busy.insert(rule.id); defer { busy.remove(rule.id) }
        let id = retries[rule.id] ?? UUID().uuidString
        retries[rule.id] = id
        do {
            let receipt = try await Api.transaction("api/earn", body: RuleInput(rule: rule).body(), requestID: id)
            retries[rule.id] = nil
            await store.refresh()
            store.showNotice(receipt.message, entryID: receipt.entryID)
        } catch { store.showNotice("未记入：\(error.localizedDescription)，点卡片重试") }
    }
}

struct CatalogIcon: View {
    static func color(_ name: String) -> Color {
        switch name { case "blue": .blue; case "orange": .orange; case "pink": .pink; case "purple": .purple; default: TreasuryTheme.accent }
    }
    let icon: String
    var tint: Color = TreasuryTheme.accent
    var body: some View {
        Group {
            if icon.unicodeScalars.contains(where: { $0.value > 127 }) { Text(icon).font(.title) }
            else { Image(systemName: icon.isEmpty ? "star.fill" : icon).font(.title2) }
        }.foregroundStyle(tint).frame(width: 48, height: 48)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ParameterScoreView: View {
    let rule: LedgerState.Rule
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var input: RuleInput
    @State private var preview: Preview?
    @State private var error: String?
    @State private var busy = false
    @State private var requestID = UUID().uuidString
    init(rule: LedgerState.Rule) { self.rule = rule; var input = RuleInput(rule: rule); if rule.kind == "range" { input.pts = rule.min ?? 0 }; _input = State(initialValue: input) }
    var body: some View {
        NavigationStack {
            Form {
                Section(rule.label) {
                    switch rule.kind {
                    case "per", "tv": Stepper("数量：\(input.n) \(rule.unit)", value: $input.n, in: 0...999)
                    case "range": Stepper("分值：\(input.pts)", value: $input.pts, in: min(rule.min ?? 0, rule.max ?? 0)...max(rule.min ?? 0, rule.max ?? 0))
                    case "calc":
                        ForEach(store.state?.calcs[rule.calc ?? ""]?.inputs ?? []) { field in
                            TextField(field.label, text: Binding(get: { input.inputs[field.id] ?? "" }, set: { input.inputs[field.id] = $0 })).keyboardType(.numberPad)
                        }
                    default: Text("固定积分")
                    }
                    if let preview {
                        Text("服务端计算：\(preview.pts >= 0 ? "+" : "")\(preview.pts) \(preview.cur == "pts" ? "分" : preview.cur == "tv" ? "分钟" : "次心愿")").font(.title3.bold())
                        Text(preview.why)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(busy ? "提交中" : "记入账本") { Task { await submit() } }.disabled(busy || preview == nil)
                }.disabled(busy)
            }.navigationTitle("记一笔")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .task(id: String(describing: input.body())) {
                    preview = nil
                    guard input.ready else { return }
                    do {
                        try await Task.sleep(for: .milliseconds(200))
                        let value = try await Api.preview(input)
                        guard !Task.isCancelled else { return }
                        preview = value; error = nil
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
        }.treasurySheetSize(minHeight: 360)
    }
    private func submit() async {
        busy = true; defer { busy = false }
        do {
            let receipt = try await Api.transaction("api/earn", body: input.body(), requestID: requestID)
            await store.refresh(); store.showNotice(receipt.message, entryID: receipt.entryID); dismiss()
        } catch { self.error = "未记入，重试：\(error.localizedDescription)" }
    }
}

struct TemporaryScoreView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var negative = false
    @State private var points = ""
    @State private var label = ""
    @State private var busy = false
    @State private var error: String?
    @State private var requestID = UUID().uuidString
    var body: some View {
        NavigationStack {
            Form {
                TreasuryChoice(title: "类型", selection: $negative, options: [("加分", false), ("减分", true)])
                TextField("整数分值", text: $points).keyboardType(.numberPad)
                TextField("简短说明", text: $label)
                if let error { Text(error).foregroundStyle(.red) }
                Button(busy ? "提交中" : "记入账本") { Task { await submit() } }
                    .disabled(busy || (Int(points) ?? 0) <= 0 || label.trimmingCharacters(in: .whitespaces).isEmpty)
            }.disabled(busy).navigationTitle("临时记一笔")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.treasurySheetSize(minHeight: 360)
    }
    private func submit() async {
        busy = true; defer { busy = false }
        do {
            let receipt = try await Api.transaction("api/adjust", body: ["pts": (Int(points) ?? 0) * (negative ? -1 : 1), "label": label], requestID: requestID)
            await store.refresh(); store.showNotice(receipt.message, entryID: receipt.entryID); dismiss()
        } catch { self.error = "未记入，重试：\(error.localizedDescription)" }
    }
}
