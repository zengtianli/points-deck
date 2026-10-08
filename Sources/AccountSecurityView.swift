import SwiftUI

struct PasswordInput: View {
    let title: String
    @Binding var text: String
    var new = false
    @State private var visible = false
    var body: some View {
        HStack {
            Group {
                if visible { TextField(title, text: $text) }
                else { SecureField(title, text: $text) }
            }.textContentType(new ? .newPassword : .password).autocorrectionDisabled()
                .textInputAutocapitalization(.never).privacySensitive()
            Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye") }
                .buttonStyle(.plain).frame(minWidth: 48, minHeight: 48)
                .accessibilityLabel(visible ? "隐藏密码" : "显示密码")
        }
    }
}

struct EmailVerification: View {
    @EnvironmentObject private var store: Store
    let email: String
    let purpose: String
    var password = ""
    var identityGrant = ""
    @Binding var grant: String
    @State private var epoch = UUID()
    private var context: [String] { [email, purpose, password, identityGrant] }
    @State private var challenge = ""
    @State private var code = ""
    @State private var busy = false
    @State private var canResend = true
    @State private var message: String?
    var body: some View {
        Group {
            Button(challenge.isEmpty ? "发送验证码" : canResend ? "重新发送" : "60 秒后可重新发送") {
                Task {
                    let generation = epoch; let target = context
                    busy = true; defer { busy = false }
                    do {
                        let fresh = try await Api.sendCode(email: email, purpose: purpose, password: password, identityGrant: identityGrant)
                        guard generation == epoch && target == context else { return }
                        challenge = fresh
                        grant = ""; code = ""; canResend = false
                        message = purpose == "recover" ? T("account.email.recover_sent", "若该邮箱已绑定验证，将收到找回邮件。请检查垃圾邮件。") : T("account.email.sent", "邮件已提交投递，请检查收件箱和垃圾邮件。")
                    } catch { if generation == epoch && target == context { await store.confirmSessionFailure(error); message = error.localizedDescription } }
                }
            }.disabled(busy || !canResend || email.isEmpty)
            if !challenge.isEmpty && grant.isEmpty {
                TextField("6 位验证码", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).privacySensitive()
                Button("验证邮箱") {
                    Task {
                        let generation = epoch; let target = context; let checked = challenge
                        busy = true; defer { busy = false }
                        do {
                            let fresh = try await Api.verifyCode(challenge: challenge, code: code)
                            guard generation == epoch && target == context && checked == challenge else { return }
                            grant = fresh; message = "邮箱已验证"
                        } catch { if generation == epoch && target == context { await store.confirmSessionFailure(error); message = error.localizedDescription } }
                    }
                }.disabled(busy || code.count != 6)
            }
            if !grant.isEmpty { Label("验证完成", systemImage: "checkmark.circle.fill").foregroundStyle(TreasuryTheme.accent) }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        }
        .onChange(of: email) { _, _ in reset() }
        .onChange(of: purpose) { _, _ in reset() }
        .onChange(of: password) { _, _ in reset() }
        .onChange(of: identityGrant) { _, _ in reset() }
        .task(id: challenge) {
            guard !challenge.isEmpty else { return }
            try? await Task.sleep(for: .seconds(60))
            if !Task.isCancelled { canResend = true }
        }
    }
    private func reset() { epoch = UUID(); challenge = ""; grant = ""; code = ""; message = nil; canResend = true }
}

struct AccountSecurityView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var currentEmail = ""
    @State private var verified = false
    @State private var email = ""
    @State private var password = ""
    @State private var newGrant = ""
    @State private var oldGrant = ""
    @State private var busy = false
    @State private var message: String?
    @State private var changePassword = false
    @State private var phoneSecurity = false
    @State private var setPassword = false
    @State private var hasPassword = true
    @State private var phone = ""
    @State private var identity = ""
    @State private var events: [String] = []
    private var changing: Bool { verified && !currentEmail.isEmpty && currentEmail.lowercased() != email.trimmingCharacters(in: .whitespaces).lowercased() }
    var body: some View {
        NavigationStack {
            Form {
                Section("手机与密码") {
                    Text(phone.isEmpty ? "手机未绑定" : "手机 \(phone.prefix(6))****\(phone.suffix(4))").privacySensitive()
                    Button("绑定／更换手机号") { phoneSecurity = true }
                    Button(hasPassword ? "修改登录密码" : "设置登录密码") { if hasPassword { changePassword = true } else { setPassword = true } }
                }
                Section("当前邮箱") {
                    Text(currentEmail.isEmpty ? "未绑定" : currentEmail)
                    Text(verified ? "已验证，可用于登录和找回" : "尚未验证，暂不能用于找回").foregroundStyle(.secondary)
                }
                Section(changing ? "更换恢复邮箱" : "绑定／验证邮箱") {
                    if hasPassword { PasswordInput(title: "当前登录密码", text: $password) }
                    else { PhoneVerification(phone: phone, purpose: "phone_identity", grant: $identity) }
                    TextField("可收信的新邮箱", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    EmailVerification(email: email, purpose: "email_new", password: password, identityGrant: identity, grant: $newGrant)
                }
                if changing {
                    Section("验证原邮箱") {
                        Text(currentEmail)
                        EmailVerification(email: currentEmail, purpose: "email_old", password: password, identityGrant: identity, grant: $oldGrant)
                    }
                }
                Button(busy ? "保存中" : "保存邮箱") { Task { await bind() } }
                    .disabled(busy || newGrant.isEmpty || (hasPassword ? password.isEmpty : identity.isEmpty) || (changing && oldGrant.isEmpty))
                if let message { Text(message).foregroundStyle(.secondary) }
                Section {
                    Link("收不到邮件／旧邮箱无法访问：联系支持", destination: URL(string: "mailto:hi@tianli.cyou")!)
                    Text(T("account.email.bind_note", "绑定和更换只修改登录与恢复邮箱，原账号、积分、项目和流水继续保留。")).font(.footnote)
                }
                if !events.isEmpty { Section("近期账号安全记录") { ForEach(Array(events.enumerated()), id: \.offset) { _, event in Text(event) } } }
            }.navigationTitle("账号安全")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .sheet(isPresented: $changePassword) { PasswordChangeView() }
                .sheet(isPresented: $phoneSecurity, onDismiss: { Task { await load() } }) { PhoneSecurityView() }
                .sheet(isPresented: $setPassword, onDismiss: { Task { await load() } }) { PhonePasswordSetView() }
                .task { await load() }
        }.treasurySheetSize(minHeight: 480)
    }
    private func load() async {
        do {
            let me = try await Api.request("api/me")
            currentEmail = me["email"] as? String ?? ""; email = currentEmail
            verified = me["email_verified"] as? Bool ?? false
            phone = me["phone"] as? String ?? ""; hasPassword = me["has_password"] as? Bool ?? true
            events = (me["security_events"] as? [[String: Any]] ?? []).reversed().map {
                let date = Date(timeIntervalSince1970: ($0["at"] as? NSNumber)?.doubleValue ?? 0)
                return "\(date.formatted(date: .abbreviated, time: .shortened)) · \($0["action"] as? String ?? "账号变更")"
            }
        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
    }
    private func bind() async {
        busy = true; defer { busy = false }
        do {
            let response = try await Api.request("api/email_bind", body: ["email": email, "password": password, "identity_grant": identity, "grant": newGrant, "old_grant": oldGrant])
            message = response["notification_sent"] as? Bool == false ? "邮箱已更新；通知投递失败，请联系支持。" : "邮箱已验证并保存，原账本保持完整。"
            newGrant = ""; oldGrant = ""; password = ""; identity = ""; await load()
        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
    }
}

struct PasswordChangeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var old = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                PasswordInput(title: "当前密码", text: $old)
                PasswordInput(title: "新密码", text: $new, new: true)
                PasswordInput(title: "确认新密码", text: $confirm, new: true)
                Text(T("account.password.rule_note", "15–128 个字符，允许空格和中文。可使用系统生成密码或独特短语。")).font(.footnote)
                if !confirm.isEmpty && new != confirm { Text("两次新密码不一致").foregroundStyle(.red) }
                if let message { Text(message) }
                Button(busy ? "保存中" : "保存新密码") {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            let response = try await Api.request("api/passwd", body: ["old": old, "new": new])
                            WatchLink.shared.publishSession()
                            await store.refresh()
                            message = response["notification_sent"] as? Bool == false ? "密码已修改，其他旧会话已失效；邮件通知投递失败。" : "密码已修改，其他设备的旧会话已失效。"
                            old = ""; new = ""; confirm = ""
                        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
                    }
                }.disabled(busy || old.isEmpty || new.count < 15 || new != confirm)
            }.navigationTitle("修改登录密码")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.treasurySheetSize(minHeight: 360)
    }
}

struct PasswordRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var grant = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var message: String?
    @State private var busy = false
    @State private var complete = false
    @State private var phoneMode = true
    @State private var phone = ""
    @State private var oldPassword = ""
    @State private var emailGrant = ""
    var body: some View {
        NavigationStack {
            Form {
                if complete {
                    Text(T("account.recover.done_note", "密码已重置，原账本保留。所有旧会话已失效，请重新登录。"))
                    Button("返回登录") { dismiss() }
                } else {
                    TreasuryChoice(title: "恢复方式", selection: $phoneMode, options: [("手机号", true), ("邮箱", false)])
                        .onChange(of: phoneMode) { _, _ in grant = ""; emailGrant = "" }
                    if phoneMode {
                        TextField("已验证的 +86 绑定手机号", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).privacySensitive()
                        PhoneVerification(phone: phone, purpose: "phone_recover", grant: $grant)
                        DisclosureGroup("号码风险验证：原密码或独立邮箱") {
                            PasswordInput(title: "原密码（如记得）", text: $oldPassword)
                            TextField("已绑定验证邮箱", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            EmailVerification(email: email, purpose: "recover", grant: $emailGrant)
                        }
                    } else {
                    TextField("已验证的绑定邮箱", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    EmailVerification(email: email, purpose: "recover", grant: $grant)
                    }
                    if !grant.isEmpty {
                        PasswordInput(title: "新密码（15–128 字符）", text: $password, new: true)
                        PasswordInput(title: "确认新密码", text: $confirm, new: true)
                        Button(busy ? "提交中" : "重置密码") {
                            Task {
                                busy = true; defer { busy = false }
                                do { _ = try await Api.request(phoneMode ? "api/phone_recover" : "api/recover", body: ["grant": grant, "new": password, "password": oldPassword, "email_grant": emailGrant]); complete = true }
                                catch { message = error.localizedDescription }
                            }
                        }.disabled(busy || password.count < 15 || password != confirm)
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
                Link("没有已验证邮箱／收不到邮件：联系支持", destination: URL(string: "mailto:hi@tianli.cyou")!)
            }.navigationTitle("忘记密码")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.treasurySheetSize(minHeight: 400)
    }
}

struct AccountPolicyView: View {
    var privacy = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(privacy ? "成长小金库隐私政策" : "成长小金库用户协议").font(.title2.bold())
                    Text("成长小金库由家长管理家庭积分，用于记录表现和兑换家庭自行约定的奖励。积分没有充值、提现或由开发者履约的商品交易功能。")
                    Text("账号保存家长本人手机号或邮箱、已设置密码的安全哈希、可选昵称、积分流水和家庭配置。验证码只用于注册、登录、绑定和恢复；不收集孩子手机号或身份资料。请勿向他人提供密码或验证码。")
                    Text("短信认证由阿里云处理家长手机号与验证请求，目前仅支持中国大陆 +86，其他地区可使用邮箱。邮箱验证与安全通知通过 tianli.cyou 现有邮件服务发送。应用使用登录会话读取自己的账本，联网同步；不出售个人数据，不提供广告追踪。")
                    Text("修改项目与价格不改变已有流水。撤销记录从日常账本移除并在后台保留恢复档案。")
                    Text("可在账户导出账本、退出登录或申请注销。仅有积分数据的账号可直接删除；涉及共享学习服务、扫描档案或旧资料的账号需协调清理，显示真实回执及处理状态，通常30天内处理。")
                    Text("家庭评价标准由家长自行约定。请妥善保管账号，对积分记录和奖励安排负责。")
                    Link("反馈、隐私请求或账号恢复申诉：hi@tianli.cyou", destination: URL(string: "mailto:hi@tianli.cyou")!)
                }.padding(24).frame(maxWidth: 740)
            }.navigationTitle(privacy ? "隐私政策" : "用户协议")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.treasurySheetSize(minHeight: 480)
    }
}
