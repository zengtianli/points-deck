import SwiftUI

struct ScoreView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var negative = false
    @State private var busy = Set<String>()
    @State private var retries: [String: String] = [:]
    @State private var picked: LedgerState.Rule?
    @State private var manager: CatalogPresentation?
    @State private var temporary = false
    private var rules: [LedgerState.Rule] {
        (store.state?.rules ?? []).filter { !$0.archived && (negative ? $0.pts < 0 : $0.pts >= 0) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Current points: \(store.state?.balance ?? 0)").font(.title2.bold()).monospacedDigit()
                TreasuryChoice(title: String(localized: "Entry type"), selection: $negative,
                               options: [(String(localized: "Add Points"), false), (String(localized: "Deduct Points"), true)])
                if rules.isEmpty {
                    ContentUnavailableView(negative ? String(localized: "No deduction items yet") : String(localized: "No points items yet"), systemImage: "plus.circle",
                                           description: Text("Tap New to set up an item with a name and points."))
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
                                else if retries[rule.id] != nil { Text("Not recorded. Retry.").font(.subheadline).foregroundStyle(.orange) }
                                else {
                                    Text(rule.kind == "fixed" ? "\(rule.pts >= 0 ? "+" : "−")\(abs(rule.pts))" :
                                            (rule.unit.isEmpty ? String(localized: "Enter details") : String(localized: "Enter \(rule.unit)")))
                                        .font(.title2.bold()).monospacedDigit()
                                }
                            }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 110).padding(12)
                                .background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).disabled(busy.contains(rule.id))
                            .accessibilityLabel("\(rule.label), \(rule.pts) points")
                    }
                }
                Button("Custom entry", systemImage: "square.and.pencil") { temporary = true }
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.bordered)
            }.padding(20).contentWidth(1100)
        }.background(TreasuryTheme.background).navigationTitle("Add Points")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("New", systemImage: "plus") { manager = CatalogPresentation(startNew: true, negative: negative) }
                    Button("Manage", systemImage: "slider.horizontal.3") { manager = CatalogPresentation(startNew: false, negative: negative) }
                }
            }
            .sheet(item: $manager) { request in
                CatalogManager(kind: "rules", startNew: request.startNew, negative: request.negative)
            }
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
        } catch { store.showNotice(String(localized: "Not recorded: \(error.localizedDescription). Tap the card to retry.")) }
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
                    case "per", "tv": Stepper("Quantity: \(input.n) \(rule.unit)", value: $input.n, in: 0...999)
                    case "range": Stepper("Points: \(input.pts)", value: $input.pts, in: min(rule.min ?? 0, rule.max ?? 0)...max(rule.min ?? 0, rule.max ?? 0))
                    case "calc":
                        ForEach(store.state?.calcs[rule.calc ?? ""]?.inputs ?? []) { field in
                            TextField(field.label, text: Binding(get: { input.inputs[field.id] ?? "" }, set: { input.inputs[field.id] = $0 })).keyboardType(.numberPad)
                        }
                    default: Text("Fixed points")
                    }
                    if let preview {
                        Text("Calculated by server: \(preview.pts >= 0 ? "+" : "")\(preview.pts) \(preview.cur == "pts" ? String(localized: "points") : preview.cur == "tv" ? String(localized: "minutes") : String(localized: "wishes"))").font(.title3.bold())
                        Text(preview.why)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(busy ? String(localized: "Recording…") : String(localized: "Record entry")) { Task { await submit() } }.disabled(busy || preview == nil)
                }.disabled(busy)
            }.navigationTitle("Record an entry")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
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
        } catch { self.error = String(localized: "Not recorded. Retry: \(error.localizedDescription)") }
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
                TreasuryChoice(title: String(localized: "Type"), selection: $negative,
                               options: [(String(localized: "Add Points"), false), (String(localized: "Deduct Points"), true)])
                TextField("Whole number of points", text: $points).keyboardType(.numberPad)
                TextField("Brief description", text: $label)
                if let error { Text(error).foregroundStyle(.red) }
                Button(busy ? String(localized: "Recording…") : String(localized: "Record entry")) { Task { await submit() } }
                    .disabled(busy || (Int(points) ?? 0) <= 0 || label.trimmingCharacters(in: .whitespaces).isEmpty)
            }.disabled(busy).navigationTitle("Custom entry")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }.treasurySheetSize(minHeight: 360)
    }
    private func submit() async {
        busy = true; defer { busy = false }
        do {
            let receipt = try await Api.transaction("api/adjust", body: ["pts": (Int(points) ?? 0) * (negative ? -1 : 1), "label": label], requestID: requestID)
            await store.refresh(); store.showNotice(receipt.message, entryID: receipt.entryID); dismiss()
        } catch { self.error = String(localized: "Not recorded. Retry: \(error.localizedDescription)") }
    }
}
