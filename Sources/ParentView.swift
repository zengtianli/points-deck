import SwiftUI
import UIKit

/// 家长面 —— 选规则 → 填输入 → **服务端预览** → Face ID 取密码 → 记账。
///
/// 三条硬约束：
/// ① 分值不在这里算，`/api/preview` 与记账走服务端同一个 compute()
/// ② 家长密码每次现取现发，不落 cookie(孩子拿到解锁的手机也加不了分)
/// ③ 撤销是服务端直接删，不是红冲
struct ParentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var subject: String = ""
    @State private var picked: State.Rule?
    @State private var input: RuleInput?
    @State private var preview: Preview?
    @State private var previewErr: String?
    @State private var busy = false
    @State private var toast: String?
    @State private var askPassword = false
    @State private var typed = ""
    @State private var pendingUndo: State.Entry?

    private var s: State? { store.state }

    var body: some View {
        NavigationStack {
            Group {
                if let s {
                    Form {
                        subjectSection(s)
                        if let r = picked { inputSection(r) }
                        undoSection(s)
                        gateSection
                    }
                    .scrollContentBackground(.hidden)     // 让底下的时代背景透出来
                    .background((store.state?.era ?? .slum).background.ignoresSafeArea())
                } else {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background((store.state?.era ?? .slum).background.ignoresSafeArea())
                }
            }
            .navigationTitle("家长记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)      // 家长面是工具面，但配色跟着 app 走
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) { toastView }
            .alert("家长密码", isPresented: $askPassword) {
                SecureField("管理密码", text: $typed)
                Button("保存并记账") { Task { await saveThenEarn() } }
                Button("取消", role: .cancel) { typed = "" }
            } message: {
                Text("存进 Keychain，以后靠 Face ID 取出来 —— 仍然每次现发一次，不留登录状态。")
            }
        }
    }

    // ── 选规则 ────────────────────────────────────────────────────────────────
    private func subjectSection(_ s: State) -> some View {
        Section("记一笔") {
            Picker("科目", selection: $subject) {
                Text("请选择").tag("")
                ForEach(s.subjects) { sub in
                    Text("\(sub.icon) \(sub.name)").tag(sub.id)
                }
            }
            .onChange(of: subject) { _, _ in picked = nil; input = nil; preview = nil }

            if !subject.isEmpty {
                let rs = s.rules.filter { $0.subject == subject }
                Picker("事由", selection: Binding(
                    get: { picked?.id ?? "" },
                    set: { id in
                        picked = rs.first { $0.id == id }
                        input = picked.map { RuleInput(rule: $0) }
                        preview = nil; previewErr = nil
                        if let i = input, i.ready { Task { await runPreview(i) } }
                    })) {
                    Text("请选择").tag("")
                    ForEach(rs) { r in Text(r.label).tag(r.id) }
                }
                .pickerStyle(.navigationLink)
            }
        }
    }

    // ── 按 kind 渲染输入 ──────────────────────────────────────────────────────
    @ViewBuilder
    private func inputSection(_ r: State.Rule) -> some View {
        Section(r.label) {
            switch r.kind {
            case "per", "tv":
                stepper(title: r.kind == "tv" ? "数量\(r.unit.isEmpty ? "" : "(\(r.unit))")"
                                              : "个数\(r.unit.isEmpty ? "" : "(\(r.unit))")",
                        value: Binding(get: { input?.n ?? 0 },
                                       set: { v in input?.n = v; schedulePreview() }))
            case "range":
                if let lo = r.min, let hi = r.max {
                    stepper(title: "分值(\(min(lo, hi))~\(max(lo, hi)))",
                            value: Binding(get: { input?.pts ?? 0 },
                                           set: { v in input?.pts = v; schedulePreview() }),
                            range: min(lo, hi)...max(lo, hi))
                }
            case "calc":
                if let key = r.calc, let c = s?.calcs[key] {
                    ForEach(c.inputs) { f in
                        HStack {
                            Text(f.label)
                            Spacer()
                            TextField(f.hint, text: Binding(
                                get: { input?.inputs[f.id] ?? "" },
                                set: { v in input?.inputs[f.id] = v; schedulePreview() }))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                }
            default:
                Text("固定分").foregroundStyle(.secondary)
            }

            // 预览 —— 这个数字来自服务端，不是本地算的
            if let p = preview {
                HStack {
                    Text("算下来")
                    Spacer()
                    Text(display(p)).fontWeight(.semibold)
                        .foregroundStyle(p.pts >= 0 ? .green : .red)
                }
                if !p.why.isEmpty {
                    Text(p.why).font(.caption).foregroundStyle(.secondary)
                }
            } else if let e = previewErr {
                Text(e).font(.caption).foregroundStyle(.orange)
            }

            Button {
                Task { await earn() }
            } label: {
                HStack {
                    if busy { ProgressView() }
                    Text("记这一笔")
                }
            }
            .disabled(busy || preview == nil)
        }
    }

    private func stepper(title: String, value: Binding<Int>,
                         range: ClosedRange<Int> = 0...999) -> some View {
        Stepper(value: value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    // ── 撤销 ──────────────────────────────────────────────────────────────────
    private func undoSection(_ s: State) -> some View {
        Section("撤销最近的") {
            if s.entries.isEmpty {
                Text("还没有流水").foregroundStyle(.secondary)
            }
            ForEach(s.entries.prefix(5)) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.what)
                        Text(e.when).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(e.pts >= 0 ? "+" : "")\(e.pts)").monospacedDigit()
                    Button(role: .destructive) {
                        pendingUndo = e
                        Task { await undo(e) }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .disabled(busy)
                }
            }
            Text("撤销 = 直接删掉这笔，走势图上当它没发生过")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var gateSection: some View {
        Section("家长密码") {
            HStack {
                Image(systemName: AdminGate.hasSaved ? "faceid" : "key")
                Text(AdminGate.hasSaved ? "已存在 Keychain，用 Face ID 取" : "还没保存")
                    .foregroundStyle(.secondary)
            }
            if AdminGate.hasSaved {
                Button("忘掉这个密码", role: .destructive) { AdminGate.forget() }
            }
            Text("密码不会变成登录状态 —— 每次记账都是取出来发一次就丢。孩子拿到解锁的手机也加不了分。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let t = toast {
            Text(t)
                .font(.subheadline)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // ── 动作 ──────────────────────────────────────────────────────────────────
    private func display(_ p: Preview) -> String {
        let unit = p.cur == "tv" ? " 分钟" : (p.cur == "wish" ? " 次心愿" : " 分")
        return (p.pts >= 0 ? "+" : "") + "\(p.pts)" + unit
    }

    private func schedulePreview() {
        guard let i = input else { return }
        preview = nil
        guard i.ready else { previewErr = nil; return }
        Task { await runPreview(i) }
    }

    private func runPreview(_ i: RuleInput) async {
        do {
            preview = try await Api.preview(i)
            previewErr = nil
        } catch {
            preview = nil
            previewErr = error.localizedDescription
        }
    }

    private func earn() async {
        guard let i = input else { return }
        guard AdminGate.hasSaved else { askPassword = true; return }
        busy = true; defer { busy = false }
        do {
            let pw = try await AdminGate.password(reason: "记一笔积分")
            let skipped = try await Api.earn(i, admin: pw)
            await store.refresh()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            show(skipped ?? "记好了")
            picked = nil; input = nil; preview = nil
        } catch {
            show(error.localizedDescription)
        }
    }

    private func saveThenEarn() async {
        let pw = typed; typed = ""
        guard !pw.isEmpty, let i = input else { return }
        busy = true; defer { busy = false }
        do {
            // 先拿这次记账验一下密码对不对，**验过了才存** —— 存一个错密码进 Keychain，
            // 之后每次都会 Face ID 通过却被服务端拒，那种错最难查。
            let skipped = try await Api.earn(i, admin: pw)
            try AdminGate.save(pw)
            await store.refresh()
            show(skipped ?? "记好了，密码已存进 Keychain")
            picked = nil; input = nil; preview = nil
        } catch {
            show(error.localizedDescription)
        }
    }

    private func undo(_ e: State.Entry) async {
        busy = true; defer { busy = false }
        do {
            let pw = AdminGate.hasSaved
                ? try await AdminGate.password(reason: "撤销一笔")
                : { askPassword = true; return "" }()
            guard !pw.isEmpty else { return }
            try await Api.undo(id: e.id, admin: pw)
            await store.refresh()
            show("已撤销：\(e.what)")
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ t: String) {
        withAnimation { toast = t }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toast = nil }
        }
    }
}
