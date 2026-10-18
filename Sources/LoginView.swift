import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: Store
    @State private var user = ""
    @State private var password = ""
    @State private var showRecovery = false
    @State private var showDeletion = false
    @State private var showRegister = false
    @State private var privacy = false
    @State private var passwordMode = false
    @State private var phone = ""
    @State private var phoneGrant = ""
    @State private var riskPassword = ""
    @State private var riskEmail = ""
    @State private var emailGrant = ""
    @State private var phoneBusy = false
    @State private var phoneError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "leaf.circle.fill").font(.system(size: 64)).foregroundStyle(TreasuryTheme.accent)
                Text(AppIdentity.displayName).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(String(localized: "Recognize Every Effort. Earn Family Rewards.")).foregroundStyle(.secondary)
                TreasuryChoice(title: String(localized: "Sign-In Method"), selection: $passwordMode,
                               options: [(String(localized: "Phone"), false), (String(localized: "Password"), true)]).frame(minHeight: 48)
                if passwordMode {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "Phone, Email, or Existing Username")).font(.subheadline)
                    TextField(String(localized: "Phone, Email, or Existing Username"), text: $user)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(14).frame(minHeight: 48).background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    PasswordInput(title: String(localized: "Sign-In Password"), text: $password)
                        .padding(.horizontal, 14).background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                if let error = store.error { Text(error).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                Button {
                    Task { await store.login(user: user.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
                } label: {
                    HStack {
                        if store.busy { ProgressView().tint(.white) }
                        Text(store.busy ? String(localized: "Signing In…") : String(localized: "Open Ledger")).fontWeight(.semibold)
                    }.frame(maxWidth: .infinity, minHeight: 52)
                        .background(TreasuryTheme.accent, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                }.disabled(store.busy || user.isEmpty || password.isEmpty)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(String(localized: "Parent’s +86 Phone Number"), text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .privacySensitive().padding(14).frame(minHeight: 48).background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        PhoneVerification(phone: phone, purpose: "login", grant: $phoneGrant)
                        DisclosureGroup(String(localized: "Extra Verification for an Inactive Number or New Sign-In")) {
                            PasswordInput(title: String(localized: "Existing Sign-In Password, if Set"), text: $riskPassword)
                            TextField(String(localized: "Or Your Linked and Verified Email"), text: $riskEmail).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            EmailVerification(email: riskEmail, purpose: "recover", grant: $emailGrant)
                        }
                    }
                    Button(phoneBusy ? String(localized: "Signing In…") : String(localized: "Open Ledger")) {
                        Task {
                            phoneBusy = true; defer { phoneBusy = false }
                            do {
                                _ = try await Api.request("api/phone_login", body: ["grant": phoneGrant, "password": riskPassword, "email_grant": emailGrant])
                                try await store.acceptSession()
                            } catch { phoneError = error.localizedDescription }
                        }
                    }.buttonStyle(.borderedProminent).frame(minHeight: 52).disabled(phoneBusy || phoneGrant.isEmpty)
                    if let phoneError { Text(phoneError).foregroundStyle(.red) }
                }
                Button(String(localized: "New Here? Create an Account")) { showRegister = true }.frame(minHeight: 48)
                Button(String(localized: "Forgot Password")) { showRecovery = true }.frame(minHeight: 48)
                if DeletionReceipt.load() != nil { Button(String(localized: "Check Deletion Status")) { showDeletion = true }.frame(minHeight: 48) }
                Button(String(localized: "Privacy Policy and Terms of Use")) { privacy = true }.frame(minHeight: 48)
                Text(T("account.login.note", String(localized: "Your existing account and password still work. If SMS is unavailable or you are outside mainland China, register with email and sign in with a password."))).font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity).padding(.vertical, 28)
        }.background(TreasuryTheme.background).tint(TreasuryTheme.accent).preferredColorScheme(.light)
            .sheet(isPresented: $showRegister) { PhoneRegisterView() }
            .sheet(isPresented: $showRecovery) { PasswordRecoveryView() }
            .sheet(isPresented: $showDeletion) { AccountDeletionView() }
            .sheet(isPresented: $privacy) { AccountPolicyView(privacy: true) }
    }
}
