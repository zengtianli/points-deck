import SwiftUI

struct PhoneVerification: View {
    @EnvironmentObject private var store: Store
    let phone: String
    let purpose: String
    var password = ""
    var identityGrant = ""
    @Binding var grant: String
    @State private var epoch = UUID()
    private var context: [String] { [phone, purpose, password, identityGrant] }
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
            Button(challenge.isEmpty ? String(localized: "Send SMS Code") : canResend ? String(localized: "Resend SMS Code") : AccountHints.resendWaitLabel(resendSeconds)) {
                Task {
                    let generation = epoch; let target = context
                    busy = true; defer { busy = false }
                    canResend = false; cooldown = UUID()
                    do {
                        let response = try await Api.request("api/phone_send", body: ["phone": phone, "purpose": purpose,
                            "password": password, "identity_grant": identityGrant, "request_id": requestID])
                        guard generation == epoch && target == context else { return }
                        requestID = UUID().uuidString // 下一次明确重发才使用新标识；失败保留原标识
                        challenge = response["challenge"] as? String ?? ""
                        grant = ""; code = ""
                        message = Api.localizedText(response, "message")
                        signName = Api.localizedText(response, "sign_name") ?? signName
                        codeMinutes = AccountHints.codeMinutes(receipt: response["expires_in"])
                        // 回执里的间隔和正在倒数的不一样（后台改过）才重新倒数；一样时与原先完全相同
                        let fresh = AccountHints.resendSeconds(receipt: response["resend_after"])
                        if fresh != resendSeconds { resendSeconds = fresh; cooldown = UUID() }
                    } catch { if generation == epoch && target == context { await store.confirmSessionFailure(error); message = error.localizedDescription } }
                }
            }.frame(minHeight: 48).disabled(busy || !canResend || phone.isEmpty)
            if !challenge.isEmpty && grant.isEmpty {
                TextField(String(localized: "6-Digit SMS Code"), text: $code).keyboardType(.numberPad)
                    .textContentType(.oneTimeCode).privacySensitive().frame(minHeight: 48)
                Button(String(localized: "Verify Phone Number")) {
                    Task {
                        let generation = epoch; let target = context; let checked = challenge
                        busy = true; defer { busy = false }
                        do {
                            let response = try await Api.request("api/phone_verify", body: ["challenge": challenge, "code": code])
                            guard generation == epoch && target == context && checked == challenge else { return }
                            grant = response["grant"] as? String ?? ""; code = ""; message = String(localized: "Phone Verified")
                        } catch { if generation == epoch && target == context { await store.confirmSessionFailure(error); message = error.localizedDescription } }
                    }
                }.frame(minHeight: 48).disabled(busy || code.count != 6)
            }
            if !grant.isEmpty { Label(String(localized: "Phone Verified"), systemImage: "checkmark.circle.fill").foregroundStyle(TreasuryTheme.accent) }
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
            if !Task.isCancelled { canResend = true }
        }
    }
    private func reset() { epoch = UUID(); cooldown = UUID(); challenge = ""; code = ""; grant = ""; requestID = UUID().uuidString; message = nil; canResend = true }
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
                Section(String(localized: "Parent’s Phone Number")) {
                    TextField(String(localized: "+86 Phone Number"), text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).privacySensitive()
                    PhoneVerification(phone: phone, purpose: "register", grant: $grant)
                    Text(T("account.phone.register_note", String(localized: "If you already have an account, sign in before linking your phone number to keep your ledger. New accounts start with 0 points. You can add a nickname, password, and email later."))).font(.footnote)
                }
                Section {
                    Button(String(localized: "Read Terms of Use")) { terms = true }
                    Button(String(localized: "Read Privacy Policy")) { privacy = true }
                    Toggle(String(localized: "I have read and agree to the Terms of Use and Privacy Policy"), isOn: $agreed)
                }
                Button(busy ? String(localized: "Creating Account…") : String(localized: "Create Account and Sign In")) {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            _ = try await Api.request("api/phone_register", body: ["grant": grant, "agreed": agreed])
                            try await store.acceptSession()
                            dismiss()
                        } catch { message = error.localizedDescription }
                    }
                }.frame(minHeight: 48).disabled(busy || grant.isEmpty || !agreed)
                Button(String(localized: "Outside Mainland China? Register with Email")) { email = true }.frame(minHeight: 48)
                if let message { Text(message).foregroundStyle(.red) }
            }.navigationTitle(String(localized: "Register with Phone"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } } }
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
                Section(String(localized: "Current Phone Number")) { Text(current.isEmpty ? String(localized: "Not Linked") : current).privacySensitive() }
                Section(String(localized: "Verify Your Identity")) {
                    if hasPassword { PasswordInput(title: String(localized: "Current Sign-In Password"), text: $password) }
                    else { PhoneVerification(phone: current, purpose: "phone_identity", grant: $identity) }
                }
                Section(current.isEmpty ? String(localized: "Link Phone Number") : String(localized: "Verify New Phone Number")) {
                    TextField(String(localized: "Parent’s +86 Phone Number"), text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).privacySensitive()
                    PhoneVerification(phone: phone, purpose: current.isEmpty ? "phone_new" : "phone_change_new",
                        password: password, identityGrant: identity, grant: $newGrant)
                }
                if !current.isEmpty {
                    Section(String(localized: "Verify Current Phone Number")) {
                        PhoneVerification(phone: current, purpose: "phone_old", password: password, identityGrant: identity, grant: $oldGrant)
                    }
                }
                Button(busy ? String(localized: "Saving…") : String(localized: "Save Phone Number")) {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            let response = try await Api.request("api/phone_bind", body: ["phone": phone, "password": password,
                                "identity_grant": identity, "grant": newGrant, "old_grant": oldGrant])
                            message = Api.localizedText(response, "message")
                            password = ""; identity = ""; newGrant = ""; oldGrant = ""; await load()
                            WatchLink.shared.publishSession(); await store.refresh()
                        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
                    }
                }.frame(minHeight: 48).disabled(busy || newGrant.isEmpty || (!current.isEmpty && oldGrant.isEmpty))
                if let message { Text(message) }
                Text(T("account.phone.bind_note", String(localized: "Linking or changing your phone number keeps your account, points, and settings. Changing it signs out other sessions. If the number is already in use, the accounts will not be merged."))).font(.footnote)
                Link(String(localized: "Old Number Unavailable? Contact Account Recovery"), destination: URL(string: "mailto:hi@tianli.cyou")!)
            }.navigationTitle(String(localized: "Manage Phone Number"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } } }
                .task { await load() }
        }
    }
    private func load() async {
        do { let me = try await Api.request("api/me"); current = me["phone"] as? String ?? ""; hasPassword = me["has_password"] as? Bool ?? true }
        catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
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
                Text(T("account.phone.password_set_note", String(localized: "Verify your linked phone number to set a sign-in password. If you already have a password, use Change Password or Forgot Password."))).font(.footnote)
                PhoneVerification(phone: phone, purpose: "phone_identity", grant: $grant)
                PasswordInput(title: String(localized: "New Password (15–128 Characters)"), text: $password, new: true)
                PasswordInput(title: String(localized: "Confirm Password"), text: $confirm, new: true)
                Button(busy ? String(localized: "Saving…") : String(localized: "Set Sign-In Password")) {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            _ = try await Api.request("api/password_set", body: ["identity_grant": grant, "new": password])
                            WatchLink.shared.publishSession(); await store.refresh(); dismiss()
                        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
                    }
                }.frame(minHeight: 48).disabled(busy || grant.isEmpty || password.count < 15 || password != confirm)
                if let message { Text(message).foregroundStyle(.red) }
            }.navigationTitle(String(localized: "Set Sign-In Password"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } } }
                .task { do { phone = try await Api.request("api/me")["phone"] as? String ?? "" } catch { await store.confirmSessionFailure(error); message = error.localizedDescription } }
        }
    }
}
