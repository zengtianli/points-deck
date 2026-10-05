import SwiftUI

struct PhoneVerification: View {
    let phone: String
    let purpose: String
    var password = ""
    var identityGrant = ""
    @Binding var grant: String
    @State private var challenge = ""
    @State private var code = ""
    @State private var requestID = UUID().uuidString
    @State private var busy = false
    @State private var canResend = true
    @State private var message: String?
    @State private var cooldown = UUID()
    @State private var signName = "恒创联众"
    @State private var resendSeconds = AccountHints.resendSeconds()
    @State private var codeMinutes = AccountHints.codeMinutes()
    var body: some View {
        Group {
            Button(challenge.isEmpty ? "获取短信验证码" : canResend ? "重新获取短信" : AccountHints.resendWaitLabel(resendSeconds)) {
                Task {
                    busy = true; defer { busy = false }
                    canResend = false; cooldown = UUID()
                    do {
                        let response = try await Api.request("api/phone_send", body: ["phone": phone, "purpose": purpose,
                            "password": password, "identity_grant": identityGrant, "request_id": requestID])
                        challenge = response["challenge"] as? String ?? ""
                        grant = ""; code = ""
                        message = response["message"] as? String
                        signName = response["sign_name"] as? String ?? signName
                        codeMinutes = AccountHints.codeMinutes(receipt: response["expires_in"])
                        // 回执里的间隔和正在倒数的不一样（后台改过）才重新倒数；一样时与原先完全相同
                        let fresh = AccountHints.resendSeconds(receipt: response["resend_after"])
                        if fresh != resendSeconds { resendSeconds = fresh; cooldown = UUID() }
                    } catch { message = error.localizedDescription }
                }
            }.frame(minHeight: 48).disabled(busy || !canResend || phone.isEmpty)
            if !challenge.isEmpty && grant.isEmpty {
                TextField("6 位短信验证码", text: $code).keyboardType(.numberPad)
                    .textContentType(.oneTimeCode).privacySensitive().frame(minHeight: 48)
                Button("验证手机号") {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            let response = try await Api.request("api/phone_verify", body: ["challenge": challenge, "code": code])
                            grant = response["grant"] as? String ?? ""; code = ""; message = "手机验证完成"
                        } catch { message = error.localizedDescription }
                    }
                }.frame(minHeight: 48).disabled(busy || code.count != 6)
            }
            if !grant.isEmpty { Label("手机验证完成", systemImage: "checkmark.circle.fill").foregroundStyle(TreasuryTheme.accent) }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            Text(AccountHints.phoneFootnote(sign: signName, minutes: codeMinutes)).font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: phone) { _, _ in reset() }
        .onChange(of: purpose) { _, _ in reset() }
        .onChange(of: password) { _, _ in reset() }
        .onChange(of: identityGrant) { _, _ in reset() }
        .task(id: cooldown) {
            guard !canResend else { return }
            try? await Task.sleep(for: .seconds(resendSeconds))
            if !Task.isCancelled { canResend = true; requestID = UUID().uuidString }
        }
    }
    private func reset() { challenge = ""; code = ""; grant = ""; requestID = UUID().uuidString; message = nil; canResend = true }
}

struct PhoneRegisterView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var grant = ""
    @State private var agreed = false
    @State private var terms = false
    @State private var privacy = false
    @State private var email = false
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("家长本人手机号") {
                    TextField("+86 手机号", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).privacySensitive()
                    PhoneVerification(phone: phone, purpose: "register", grant: $grant)
                    Text(T("account.phone.register_note", "已有旧账号请先登录再绑定手机号，避免新建空账本。注册后从0分起步，昵称、密码和邮箱可稍后设置。")).font(.footnote)
                }
                Section {
                    Button("阅读用户协议") { terms = true }
                    Button("阅读隐私政策") { privacy = true }
                    Toggle("我已阅读并同意用户协议与隐私政策", isOn: $agreed)
                }
                Button(busy ? "注册中" : "注册并登录") {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            _ = try await Api.request("api/phone_register", body: ["grant": grant, "agreed": agreed])
                            try await store.acceptSession()
                            dismiss()
                        } catch { message = error.localizedDescription }
                    }
                }.frame(minHeight: 48).disabled(busy || grant.isEmpty || !agreed)
                Button("其他地区／使用邮箱注册") { email = true }.frame(minHeight: 48)
                if let message { Text(message).foregroundStyle(.red) }
            }.navigationTitle("手机号注册")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .sheet(isPresented: $terms) { AccountPolicyView() }
                .sheet(isPresented: $privacy) { AccountPolicyView(privacy: true) }
                .sheet(isPresented: $email) { RegisterView() }
        }
    }
}

struct PhoneSecurityView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var hasPassword = true
    @State private var identity = ""
    @State private var newGrant = ""
    @State private var oldGrant = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("当前手机号") { Text(current.isEmpty ? "未绑定" : current).privacySensitive() }
                Section("重新确认身份") {
                    if hasPassword { PasswordInput(title: "当前登录密码", text: $password) }
                    else { PhoneVerification(phone: current, purpose: "phone_identity", grant: $identity) }
                }
                Section(current.isEmpty ? "绑定手机号" : "验证新手机号") {
                    TextField("+86 家长手机号", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).privacySensitive()
                    PhoneVerification(phone: phone, purpose: current.isEmpty ? "phone_new" : "phone_change_new",
                        password: password, identityGrant: identity, grant: $newGrant)
                }
                if !current.isEmpty {
                    Section("确认原手机号") {
                        PhoneVerification(phone: current, purpose: "phone_old", password: password, identityGrant: identity, grant: $oldGrant)
                    }
                }
                Button(busy ? "保存中" : "确认保存手机号") {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            let response = try await Api.request("api/phone_bind", body: ["phone": phone, "password": password,
                                "identity_grant": identity, "grant": newGrant, "old_grant": oldGrant])
                            message = response["message"] as? String
                            password = ""; identity = ""; newGrant = ""; oldGrant = ""; await load()
                            WatchLink.shared.publishSession(); await store.refresh()
                        } catch { message = error.localizedDescription }
                    }
                }.frame(minHeight: 48).disabled(busy || newGrant.isEmpty || (!current.isEmpty && oldGrant.isEmpty))
                if let message { Text(message) }
                Text(T("account.phone.bind_note", "绑定和换绑保留原内部账号、积分和配置。换绑后其他旧会话失效；号码被占用时不会合并账号。")).font(.footnote)
                Link("原手机号无法使用／账号恢复申诉", destination: URL(string: "mailto:hi@tianli.cyou")!)
            }.navigationTitle("手机绑定与换绑")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .task { await load() }
        }
    }
    private func load() async {
        do { let me = try await Api.request("api/me"); current = me["phone"] as? String ?? ""; hasPassword = me["has_password"] as? Bool ?? true }
        catch { message = error.localizedDescription }
    }
}

struct PhonePasswordSetView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var grant = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Text(T("account.phone.password_set_note", "确认当前绑定手机后设置独立登录密码。已有密码请使用修改或找回流程。")).font(.footnote)
                PhoneVerification(phone: phone, purpose: "phone_identity", grant: $grant)
                PasswordInput(title: "新密码（15–128字符）", text: $password, new: true)
                PasswordInput(title: "确认密码", text: $confirm, new: true)
                Button(busy ? "保存中" : "设置登录密码") {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            _ = try await Api.request("api/password_set", body: ["identity_grant": grant, "new": password])
                            WatchLink.shared.publishSession(); await store.refresh(); dismiss()
                        } catch { message = error.localizedDescription }
                    }
                }.frame(minHeight: 48).disabled(busy || grant.isEmpty || password.count < 15 || password != confirm)
                if let message { Text(message).foregroundStyle(.red) }
            }.navigationTitle("设置登录密码")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .task { do { phone = try await Api.request("api/me")["phone"] as? String ?? "" } catch { message = error.localizedDescription } }
        }
    }
}
