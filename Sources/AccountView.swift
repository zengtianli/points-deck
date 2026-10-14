import SwiftUI
import Security
import UniformTypeIdentifiers

struct AccountView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject private var lifecycle: MobileLifecycleModel
    @State private var emailStatus = ""
    @State private var phoneStatus = ""
    @State private var security = false
    @State private var profile = false
    @State private var tiers = false
    @State private var rules = false
    @State private var rewards = false
    @State private var updates = false
    @State private var privacy = false
    @State private var confirmLogout = false
    @State private var deleting = false
    @State private var exporting = false
    @State private var document = LedgerDocument()
    @State private var message: String?
    var maxWidth: CGFloat? = nil
    var body: some View {
        Form {
            Section {
                HStack {
                    Text(store.state?.avatar ?? "🌱").font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text(store.state?.nick ?? "").font(.title2.bold())
                        Text(emailStatus.isEmpty ? "账号 \(store.state?.user ?? "")" : emailStatus).font(.footnote).foregroundStyle(.secondary)
                        if !phoneStatus.isEmpty { Text(phoneStatus).font(.footnote).foregroundStyle(.secondary).privacySensitive() }
                    }
                }.padding(.vertical, 8)
                Button("修改昵称与头像") { profile = true }
                Button("账号安全", systemImage: "person.badge.key.fill") { security = true }
            }
            Section("成长") {
                LabeledContent("当前积分", value: "\(store.state?.balance ?? 0)")
                Button("等级与待遇：\(store.state?.houseName ?? "")") { tiers = true }
                if let remaining = store.state?.toNext { Text("还差 \(remaining) 分升级到 \(store.state?.nextName ?? "")") }
            }
            Section("家庭设置") {
                Button("记分项目管理", systemImage: "plusminus.circle") { rules = true }
                Button("兑换奖励管理", systemImage: "gift") { rewards = true }
                Button("导出账本", systemImage: "square.and.arrow.up") {
                    Task {
                        do {
                            let state = try await Api.request("api/state?all=1")
                            document = LedgerDocument(data: try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]))
                            exporting = true
                        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
                    }
                }
                Button("设置、iCloud 与检查更新", systemImage: "gearshape") { updates = true }
            }
            Section("帮助") {
                Button("隐私与数据处理") { privacy = true }
                Link("反馈／收不到短信邮件／恢复申诉", destination: URL(string: "mailto:hi@tianli.cyou")!)
                Text("验证码过期可重发；短信仅支持 +86 家长手机号，可改用邮箱。旧账号先登录再绑定；原地址无法访问时联系支持核验所有权。").font(.footnote).foregroundStyle(.secondary)
                Text("\(AppIdentity.displayName) · \(Bundle.main.shortVersion)").font(.caption)
            }
            Section {
                Button("退出登录", role: .destructive) { confirmLogout = true }
                Button("注销账号", role: .destructive) { deleting = true }
            }
            if let message { Text(message).foregroundStyle(.red) }
        }.navigationTitle("账户").scrollContentBackground(.hidden).background(TreasuryTheme.background)
            .task { await updateAccountSummary() }
            .sheet(isPresented: $security, onDismiss: { Task { await updateAccountSummary() } }) { AccountSecurityView() }
            .sheet(isPresented: $profile) { ProfileEditView() }
            .sheet(isPresented: $tiers) { TiersView() }
            .sheet(isPresented: $rules) { CatalogManager(kind: "rules") }
            .sheet(isPresented: $rewards) { CatalogManager(kind: "shop") }
            .sheet(isPresented: $updates) { TreasurySettingsView(preferences: .shared, lifecycle: lifecycle) }
            .sheet(isPresented: $privacy) { AccountPolicyView(privacy: true) }
            .sheet(isPresented: $deleting) { AccountDeletionView() }
            .confirmationDialog("退出当前账号？", isPresented: $confirmLogout) {
                Button("退出登录", role: .destructive) { Task { await store.logout() } }
                Button("取消", role: .cancel) {}
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Growth-Treasury-ledger") { result in
                if case let .failure(error) = result { message = error.localizedDescription }
            }
    }
    private func updateAccountSummary() async {
        do {
            let me = try await Api.request("api/me")
            let email = me["email"] as? String ?? ""
            let mask = email.split(separator: "@").last.map { "***@" + $0 } ?? ""
            emailStatus = email.isEmpty ? "邮箱未绑定" : mask + (me["email_verified"] as? Bool == true ? " · 已验证" : " · 待验证")
            let phone = me["phone"] as? String ?? ""
            phoneStatus = phone.isEmpty ? "手机未绑定" : "\(phone.prefix(6))****\(phone.suffix(4)) · 已验证"
        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
    }
}

struct LedgerDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

enum DeletionReceipt {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Snapshot.serviceName("deletion"),
         kSecAttrAccount as String: "receipt"]
    }
    static func save(_ value: String) {
        let attributes = [kSecValueData as String: Data(value.utf8)]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insert = query; insert.merge(attributes) { _, new in new }
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
    static func load() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct AccountDeletionView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var message: String?
    @State private var busy = false
    @State private var offerRequest = false
    @State private var receipt = DeletionReceipt.load()
    @State private var hasPassword = true
    @State private var phone = ""
    @State private var identity = ""
    var body: some View {
        NavigationStack {
            Form {
                Text("注销会删除当前账号及积分数据。涉及共享学习、扫描档案或旧资料时需协调清理；申请受理不代表已经删除。")
                if store.phase == .loggedIn {
                    if hasPassword { PasswordInput(title: "当前登录密码", text: $password) }
                    else { PhoneVerification(phone: phone, purpose: "phone_identity", grant: $identity) }
                    Button(offerRequest ? "确认申请注销" : "确认注销", role: .destructive) { Task { await remove() } }
                        .disabled(busy || (hasPassword ? password.isEmpty : identity.isEmpty))
                }
                if let message { Text(message) }
                if receipt != nil { Button("查询注销处理状态") { Task { await status() } }.disabled(busy) }
                Link("联系支持", destination: URL(string: "mailto:hi@tianli.cyou")!)
            }.navigationTitle("注销账号")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
                .task {
                    if receipt != nil { await status() }
                    if store.phase == .loggedIn {
                        do { let me = try await Api.request("api/me"); hasPassword = me["has_password"] as? Bool ?? true; phone = me["phone"] as? String ?? "" }
                        catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
                    }
                }
        }.treasurySheetSize(minHeight: 360)
    }
    private func remove() async {
        busy = true; defer { busy = false }
        do {
            if offerRequest {
                let result = try await Api.request("api/account_delete_request", body: ["password": password, "identity_grant": identity])
                receipt = result["receipt_id"] as? String
                if let receipt { DeletionReceipt.save(receipt) }
                message = "申请已受理，尚未完成删除。预计 \(result["expected_by"] as? String ?? "通常30天内")，可在此查询状态。"
                password = ""
            } else {
                _ = try await Api.request("api/account_del", body: ["p": password, "identity_grant": identity])
                store.dropSession(); WatchLink.shared.publishSignedOut(); dismiss()
            }
        } catch {
            await store.confirmSessionFailure(error)
            message = error.localizedDescription
            offerRequest = (error as? Api.Failure)?.status == 409
        }
    }
    private func status() async {
        guard let receipt else { return }
        do {
            let result = try await Api.request("api/account_delete_status", body: ["receipt_id": receipt])
            message = result["status"] as? String == "completed" ? "账号及相关数据清理已完成。" : "注销处理中，尚未完成删除。预计 \(result["expected_by"] as? String ?? "通常30天内")。"
        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
}
