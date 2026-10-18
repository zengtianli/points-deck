import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var nick = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var grant = ""
    @State private var agreed = false
    @State private var terms = false
    @State private var privacy = false
    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Verify Email")) {
                    TextField(String(localized: "Email"), text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    EmailVerification(email: email, purpose: "register", grant: $grant)
                }
                Section(String(localized: "Set Up Your Account")) {
                    PasswordInput(title: String(localized: "Password (15–128 Characters)"), text: $password, new: true)
                    PasswordInput(title: String(localized: "Confirm Password"), text: $confirm, new: true)
                    TextField(String(localized: "Nickname (Optional)"), text: $nick)
                    if !confirm.isEmpty && password != confirm { Text(String(localized: "Passwords don’t match")).foregroundStyle(.red) }
                    Text(T("account.register.password_note", String(localized: "System-generated passwords, spaces, and Chinese characters are supported. New accounts start with 0 points."))).font(.footnote)
                }
                Section {
                    Button(String(localized: "Read Terms of Use")) { terms = true }
                    Button(String(localized: "Read Privacy Policy")) { privacy = true }
                    Toggle(String(localized: "I have read and agree to the Terms of Use and Privacy Policy"), isOn: $agreed)
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
                Button(store.busy ? String(localized: "Creating Account…") : String(localized: "Create Account and Sign In")) {
                    Task {
                        await store.register(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                             password: password, nick: nick, grant: grant)
                        if store.phase == .loggedIn { dismiss() }
                    }
                }.disabled(store.busy || grant.isEmpty || !agreed || password.count < 15 || password != confirm)
            }.navigationTitle(String(localized: "Create Account"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { store.error = nil; dismiss() } } }
                .sheet(isPresented: $terms) { AccountPolicyView() }
                .sheet(isPresented: $privacy) { AccountPolicyView(privacy: true) }
        }.treasurySheetSize(minHeight: 480)
    }
}
