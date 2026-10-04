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
                Text("记录每一份努力，积攒家庭约定的奖励").foregroundStyle(.secondary)
                Picker("登录方式", selection: $passwordMode) {
                    Text("手机号登录").tag(false); Text("密码登录").tag(true)
                }.pickerStyle(.segmented).frame(minHeight: 48)
                if passwordMode {
                VStack(alignment: .leading, spacing: 14) {
                    Text("手机号、邮箱或原用户名").font(.subheadline)
                    TextField("手机号、邮箱或原用户名", text: $user)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(14).frame(minHeight: 48).background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    PasswordInput(title: "登录密码", text: $password)
                        .padding(.horizontal, 14).background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 12))
                }
                if let error = store.error { Text(error).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
                Button {
                    Task { await store.login(user: user.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
                } label: {
                    HStack {
                        if store.busy { ProgressView().tint(.white) }
                        Text(store.busy ? "登录中" : "进入账本").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity, minHeight: 52)
                        .background(TreasuryTheme.accent, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                }.disabled(store.busy || user.isEmpty || password.isEmpty)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("+86 家长手机号", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                            .privacySensitive().padding(14).frame(minHeight: 48).background(TreasuryTheme.card, in: RoundedRectangle(cornerRadius: 12))
                        PhoneVerification(phone: phone, purpose: "login", grant: $phoneGrant)
                        DisclosureGroup("号码长期未用／登录环境变化时补充验证") {
                            PasswordInput(title: "原登录密码（如已设置）", text: $riskPassword)
                            TextField("或已绑定验证的邮箱", text: $riskEmail).textContentType(.emailAddress).keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            EmailVerification(email: riskEmail, purpose: "recover", grant: $emailGrant)
                        }
                    }
                    Button(phoneBusy ? "登录中" : "进入账本") {
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
                Button("没有账号？注册账号") { showRegister = true }.frame(minHeight: 48)
                Button("忘记密码") { showRecovery = true }.frame(minHeight: 48)
                if DeletionReceipt.load() != nil { Button("查询注销状态") { showDeletion = true }.frame(minHeight: 48) }
                Button("隐私政策与使用约定") { privacy = true }.frame(minHeight: 48)
                Text("原账号和原密码可继续登录。短信暂不可用或其他地区可使用邮箱注册与密码登录。").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity).padding(.vertical, 28)
        }.background(TreasuryTheme.background).tint(TreasuryTheme.accent).preferredColorScheme(.light)
            .sheet(isPresented: $showRegister) { PhoneRegisterView() }
            .sheet(isPresented: $showRecovery) { PasswordRecoveryView() }
            .sheet(isPresented: $showDeletion) { AccountDeletionView() }
            .sheet(isPresented: $privacy) { AccountPolicyView(privacy: true) }
    }
}
