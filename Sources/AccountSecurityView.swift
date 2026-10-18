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
                .accessibilityLabel(visible ? String(localized: "Hide Password") : String(localized: "Show Password"))
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
            Button(challenge.isEmpty ? String(localized: "Send Code") : canResend ? String(localized: "Resend Code") : String(localized: "Resend in 60 Seconds")) {
                Task {
                    let generation = epoch; let target = context
                    busy = true; defer { busy = false }
                    do {
                        let fresh = try await Api.sendCode(email: email, purpose: purpose, password: password, identityGrant: identityGrant)
                        guard generation == epoch && target == context else { return }
                        challenge = fresh
                        grant = ""; code = ""; canResend = false
                        message = purpose == "recover" ? T("account.email.recover_sent", String(localized: "If this email is linked and verified, you’ll receive a recovery email. Please check your spam folder.")) : T("account.email.sent", String(localized: "Your email has been queued for delivery. Please check your inbox and spam folder."))
                    } catch { if generation == epoch && target == context { await store.confirmSessionFailure(error); message = error.localizedDescription } }
                }
            }.disabled(busy || !canResend || email.isEmpty)
            if !challenge.isEmpty && grant.isEmpty {
                TextField(String(localized: "6-Digit Code"), text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).privacySensitive()
                Button(String(localized: "Verify Email")) {
                    Task {
                        let generation = epoch; let target = context; let checked = challenge
                        busy = true; defer { busy = false }
                        do {
                            let fresh = try await Api.verifyCode(challenge: challenge, code: code)
                            guard generation == epoch && target == context && checked == challenge else { return }
                            grant = fresh; message = String(localized: "Email Verified")
                        } catch { if generation == epoch && target == context { await store.confirmSessionFailure(error); message = error.localizedDescription } }
                    }
                }.disabled(busy || code.count != 6)
            }
            if !grant.isEmpty { Label(String(localized: "Verified"), systemImage: "checkmark.circle.fill").foregroundStyle(TreasuryTheme.accent) }
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
                Section(String(localized: "Phone and Password")) {
                    Text(phone.isEmpty ? String(localized: "No Phone Linked") : String(localized: "Phone \(String(phone.prefix(6)))****\(String(phone.suffix(4)))")).privacySensitive()
                    Button(String(localized: "Link or Change Phone Number")) { phoneSecurity = true }
                    Button(hasPassword ? String(localized: "Change Sign-In Password") : String(localized: "Set Sign-In Password")) { if hasPassword { changePassword = true } else { setPassword = true } }
                }
                Section(String(localized: "Current Email")) {
                    Text(currentEmail.isEmpty ? String(localized: "Not Linked") : currentEmail)
                    Text(verified ? String(localized: "Verified for Sign-In and Recovery") : String(localized: "Not Verified for Recovery Yet")).foregroundStyle(.secondary)
                }
                Section(changing ? String(localized: "Change Recovery Email") : String(localized: "Link or Verify Email")) {
                    if hasPassword { PasswordInput(title: String(localized: "Current Sign-In Password"), text: $password) }
                    else { PhoneVerification(phone: phone, purpose: "phone_identity", grant: $identity) }
                    TextField(String(localized: "New Email Address"), text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    EmailVerification(email: email, purpose: "email_new", password: password, identityGrant: identity, grant: $newGrant)
                }
                if changing {
                    Section(String(localized: "Verify Current Email")) {
                        Text(currentEmail)
                        EmailVerification(email: currentEmail, purpose: "email_old", password: password, identityGrant: identity, grant: $oldGrant)
                    }
                }
                Button(busy ? String(localized: "Saving…") : String(localized: "Save Email")) { Task { await bind() } }
                    .disabled(busy || newGrant.isEmpty || (hasPassword ? password.isEmpty : identity.isEmpty) || (changing && oldGrant.isEmpty))
                if let message { Text(message).foregroundStyle(.secondary) }
                Section {
                    Link(String(localized: "Email missing or inaccessible? Contact support"), destination: URL(string: "mailto:hi@tianli.cyou")!)
                    Text(T("account.email.bind_note", String(localized: "Linking or changing your email only updates your sign-in and recovery address. Your account, points, rules, and ledger stay intact."))).font(.footnote)
                }
                if !events.isEmpty { Section(String(localized: "Recent Account Activity")) { ForEach(Array(events.enumerated()), id: \.offset) { _, event in Text(event) } } }
            }.navigationTitle(String(localized: "Account Security"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } } }
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
                return "\(date.formatted(date: .abbreviated, time: .shortened)) · \(Api.localizedText($0, "action") ?? String(localized: "Account Updated"))"
            }
        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
    }
    private func bind() async {
        busy = true; defer { busy = false }
        do {
            let response = try await Api.request("api/email_bind", body: ["email": email, "password": password, "identity_grant": identity, "grant": newGrant, "old_grant": oldGrant])
            message = response["notification_sent"] as? Bool == false ? String(localized: "Your email was updated, but the notification could not be delivered. Please contact support.") : String(localized: "Your email is verified and saved. Your ledger is unchanged.")
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
                PasswordInput(title: String(localized: "Current Password"), text: $old)
                PasswordInput(title: String(localized: "New Password"), text: $new, new: true)
                PasswordInput(title: String(localized: "Confirm New Password"), text: $confirm, new: true)
                Text(T("account.password.rule_note", String(localized: "Use 15–128 characters, including spaces and Chinese characters. Choose a system-generated password or a unique passphrase."))).font(.footnote)
                if !confirm.isEmpty && new != confirm { Text(String(localized: "New passwords don’t match")).foregroundStyle(.red) }
                if let message { Text(message) }
                Button(busy ? String(localized: "Saving…") : String(localized: "Save New Password")) {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            let response = try await Api.request("api/passwd", body: ["old": old, "new": new])
                            WatchLink.shared.publishSession()
                            await store.refresh()
                            message = response["notification_sent"] as? Bool == false ? String(localized: "Your password was changed and other sessions were signed out, but the email notification could not be delivered.") : String(localized: "Your password was changed. Other devices have been signed out.")
                            old = ""; new = ""; confirm = ""
                        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
                    }
                }.disabled(busy || old.isEmpty || new.count < 15 || new != confirm)
            }.navigationTitle(String(localized: "Change Sign-In Password"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } } }
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
                    Text(T("account.recover.done_note", String(localized: "Your password was reset and your ledger is intact. All previous sessions have ended. Please sign in again.")))
                    Button(String(localized: "Back to Sign In")) { dismiss() }
                } else {
                    TreasuryChoice(title: String(localized: "Recovery Method"), selection: $phoneMode, options: [(String(localized: "Phone"), true), (String(localized: "Email"), false)])
                        .onChange(of: phoneMode) { _, _ in grant = ""; emailGrant = "" }
                    if phoneMode {
                        TextField(String(localized: "Linked and Verified +86 Phone Number"), text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber).privacySensitive()
                        PhoneVerification(phone: phone, purpose: "phone_recover", grant: $grant)
                        DisclosureGroup(String(localized: "Additional Verification: Password or Email")) {
                            PasswordInput(title: String(localized: "Previous Password, if Remembered"), text: $oldPassword)
                            TextField(String(localized: "Linked and Verified Email"), text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            EmailVerification(email: email, purpose: "recover", grant: $emailGrant)
                        }
                    } else {
                    TextField(String(localized: "Linked and Verified Email"), text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    EmailVerification(email: email, purpose: "recover", grant: $grant)
                    }
                    if !grant.isEmpty {
                        PasswordInput(title: String(localized: "New Password (15–128 Characters)"), text: $password, new: true)
                        PasswordInput(title: String(localized: "Confirm New Password"), text: $confirm, new: true)
                        Button(busy ? String(localized: "Submitting…") : String(localized: "Reset Password")) {
                            Task {
                                busy = true; defer { busy = false }
                                do { _ = try await Api.request(phoneMode ? "api/phone_recover" : "api/recover", body: ["grant": grant, "new": password, "password": oldPassword, "email_grant": emailGrant]); complete = true }
                                catch { message = error.localizedDescription }
                            }
                        }.disabled(busy || password.count < 15 || password != confirm)
                    }
                }
                if let message { Text(message).foregroundStyle(.red) }
                Link(String(localized: "No verified email or missing messages? Contact support"), destination: URL(string: "mailto:hi@tianli.cyou")!)
            }.navigationTitle(String(localized: "Forgot Password"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } } }
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
                    Text(privacy ? String(localized: "Growth Treasury Privacy Policy") : String(localized: "Growth Treasury Terms of Use")).font(.title2.bold())
                    Text(String(localized: "Growth Treasury lets parents manage family points, record progress, and redeem rewards agreed on within the family. Points cannot be purchased, cashed out, or used to buy goods supplied by the developer."))
                    Text(String(localized: "Your account stores the parent’s phone number or email, a secure hash of any password you set, an optional nickname, point transactions, and family settings. Verification codes are used only for registration, sign-in, linking contact details, and recovery. We do not collect children’s phone numbers or identity documents. Never share your password or verification codes."))
                    Text(String(localized: "Alibaba Cloud processes the parent’s phone number and SMS verification requests. SMS currently supports mainland China (+86); email is available in other regions. Email verification and security notices use the existing tianli.cyou mail service. The app uses your signed-in session to read and sync your own ledger. We do not sell personal data or use advertising tracking."))
                    Text(String(localized: "Changing rules or prices does not alter past transactions. Undone entries are removed from the active ledger, with a recovery record retained on the server."))
                    Text(String(localized: "From Account, you can export your ledger, sign out, or request account deletion. Accounts containing only points data can be deleted immediately. Shared learning services, scanned files, or older records may require coordinated cleanup. You will receive a receipt and status updates, usually within 30 days."))
                    Text(String(localized: "Parents decide their family’s rules. Keep your account secure and take responsibility for point records and reward arrangements."))
                    Link(String(localized: "Feedback, privacy requests, or account recovery: hi@tianli.cyou"), destination: URL(string: "mailto:hi@tianli.cyou")!)
                }.padding(24).frame(maxWidth: 740)
            }.navigationTitle(privacy ? String(localized: "Privacy Policy") : String(localized: "Terms of Use"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } } }
        }.treasurySheetSize(minHeight: 480)
    }
}
