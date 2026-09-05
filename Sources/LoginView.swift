import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: Store
    @State private var user = ""
    @State private var password = ""
    @State private var showRegister = false
    @FocusState private var focus: Field?

    private enum Field { case user, password }

    var body: some View {
        ZStack {
            Era.garden.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Text("京宝积分")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("挣的每一分都在这本账上")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }

                VStack(spacing: 12) {
                    field("用户名或邮箱", text: $user, secure: false, focus: .user)
                    field("密码", text: $password, secure: true, focus: .password)
                }

                if let e = store.error {
                    Text(e)
                        .font(.footnote)
                        .foregroundStyle(Color(hex: 0xFFB4B4))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                Button {
                    Task { await store.login(user: user, password: password) }
                } label: {
                    HStack {
                        if store.busy { ProgressView().tint(.black) }
                        Text(store.busy ? "登录中" : "进入账本").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Era.garden.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.black)
                }
                .disabled(store.busy || user.isEmpty || password.isEmpty)
                .opacity(user.isEmpty || password.isEmpty ? 0.5 : 1)

                Button("没有账号？邮箱注册") { showRegister = true }
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))

                Spacer()
                Text("账本在 edu.tianli.cyou，这里只是它的随身版")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 28)
        }
        .animation(.easeInOut(duration: 0.2), value: store.error)
        .sheet(isPresented: $showRegister) { RegisterView() }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool, focus f: Field) -> some View {
        Group {
            if secure {
                SecureField("", text: text).textContentType(.password)
            } else {
                TextField("", text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
            }
        }
        .focused($focus, equals: f)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(title).foregroundStyle(.white.opacity(0.5)).padding(.leading, 16).allowsHitTesting(false)
            }
        }
    }
}
