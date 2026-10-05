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
                Section("验证邮箱") {
                    TextField("邮箱", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    EmailVerification(email: email, purpose: "register", grant: $grant)
                }
                Section("设置账号") {
                    PasswordInput(title: "密码（15–128 字符）", text: $password, new: true)
                    PasswordInput(title: "确认密码", text: $confirm, new: true)
                    TextField("昵称（可选）", text: $nick)
                    if !confirm.isEmpty && password != confirm { Text("两次密码不一致").foregroundStyle(.red) }
                    Text(T("account.register.password_note", "支持系统生成密码、空格与中文。新账号从0分起步。")).font(.footnote)
                }
                Section {
                    Button("阅读用户协议") { terms = true }
                    Button("阅读隐私政策") { privacy = true }
                    Toggle("我已阅读并同意用户协议与隐私政策", isOn: $agreed)
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
                Button(store.busy ? "注册中" : "注册并登录") {
                    Task {
                        await store.register(email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                             password: password, nick: nick, grant: grant)
                        if store.phase == .loggedIn { dismiss() }
                    }
                }.disabled(store.busy || grant.isEmpty || !agreed || password.count < 15 || password != confirm)
            }.navigationTitle("注册账号")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { store.error = nil; dismiss() } } }
                .sheet(isPresented: $terms) { AccountPolicyView() }
                .sheet(isPresented: $privacy) { AccountPolicyView(privacy: true) }
        }.treasurySheetSize(minHeight: 480)
    }
}
