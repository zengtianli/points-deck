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
                        Text(emailStatus.isEmpty ? String(localized: "Account \(store.state?.user ?? "")") : emailStatus).font(.footnote).foregroundStyle(.secondary)
                        if !phoneStatus.isEmpty { Text(phoneStatus).font(.footnote).foregroundStyle(.secondary).privacySensitive() }
                    }
                }.padding(.vertical, 8)
                Button(String(localized: "Edit Name and Avatar")) { profile = true }
                Button(String(localized: "Account Security"), systemImage: "person.badge.key.fill") { security = true }
            }
            Section(String(localized: "Growth")) {
                LabeledContent(String(localized: "Current Points"), value: "\(store.state?.balance ?? 0)")
                Button(String(localized: "Tiers and Benefits: \(store.state?.houseName ?? "")")) { tiers = true }
                if let remaining = store.state?.toNext { Text(String(localized: "\(remaining) points to \(store.state?.nextName ?? "")")) }
            }
            Section(String(localized: "Family Settings")) {
                Button(String(localized: "Manage Point Rules"), systemImage: "plusminus.circle") { rules = true }
                Button(String(localized: "Manage Rewards"), systemImage: "gift") { rewards = true }
                Button(String(localized: "Export Ledger"), systemImage: "square.and.arrow.up") {
                    Task {
                        do {
                            let state = try await Api.request("api/state?all=1")
                            document = LedgerDocument(data: try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]))
                            exporting = true
                        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
                    }
                }
                Button(String(localized: "Settings, iCloud, and Updates"), systemImage: "gearshape") { updates = true }
            }
            Section(String(localized: "Help")) {
                Button(String(localized: "Privacy and Data")) { privacy = true }
                Link(String(localized: "Feedback, Delivery Issues, and Account Recovery"), destination: URL(string: "mailto:hi@tianli.cyou")!)
                Text(String(localized: "Request a new code if yours expires. SMS supports parents’ +86 numbers; you can also use email. Sign in to an existing account before linking a number or email. Contact support to verify ownership if you can no longer access your old contact details.")).font(.footnote).foregroundStyle(.secondary)
                Text("\(AppIdentity.displayName) · \(Bundle.main.shortVersion)").font(.caption)
            }
            Section {
                Button(String(localized: "Sign Out"), role: .destructive) { confirmLogout = true }
                Button(String(localized: "Delete Account"), role: .destructive) { deleting = true }
            }
            if let message { Text(message).foregroundStyle(.red) }
        }.navigationTitle(String(localized: "Account")).scrollContentBackground(.hidden).background(TreasuryTheme.background)
            .task { await updateAccountSummary() }
            .sheet(isPresented: $security, onDismiss: { Task { await updateAccountSummary() } }) { AccountSecurityView() }
            .sheet(isPresented: $profile) { ProfileEditView() }
            .sheet(isPresented: $tiers) { TiersView() }
            .sheet(isPresented: $rules) { CatalogManager(kind: "rules") }
            .sheet(isPresented: $rewards) { CatalogManager(kind: "shop") }
            .sheet(isPresented: $updates) { TreasurySettingsView(preferences: .shared, lifecycle: lifecycle) }
            .sheet(isPresented: $privacy) { AccountPolicyView(privacy: true) }
            .sheet(isPresented: $deleting) { AccountDeletionView() }
            .confirmationDialog(String(localized: "Sign out of this account?"), isPresented: $confirmLogout) {
                Button(String(localized: "Sign Out"), role: .destructive) { Task { await store.logout() } }
                Button(String(localized: "Cancel"), role: .cancel) {}
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
            emailStatus = email.isEmpty ? String(localized: "No Email Linked") : mask + (me["email_verified"] as? Bool == true ? String(localized: " · Verified") : String(localized: " · Verification Pending"))
            let phone = me["phone"] as? String ?? ""
            phoneStatus = phone.isEmpty ? String(localized: "No Phone Linked") : String(localized: "\(String(phone.prefix(6)))****\(String(phone.suffix(4))) · Verified")
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
                Text(String(localized: "Deleting your account removes the account and its points data. Shared learning records, scanned files, or older data may require coordinated cleanup. An accepted request does not mean deletion is complete."))
                if store.phase == .loggedIn {
                    if hasPassword { PasswordInput(title: String(localized: "Current Sign-In Password"), text: $password) }
                    else { PhoneVerification(phone: phone, purpose: "phone_identity", grant: $identity) }
                    Button(offerRequest ? String(localized: "Request Account Deletion") : String(localized: "Confirm Account Deletion"), role: .destructive) { Task { await remove() } }
                        .disabled(busy || (hasPassword ? password.isEmpty : identity.isEmpty))
                }
                if let message { Text(message) }
                if receipt != nil { Button(String(localized: "Check Deletion Status")) { Task { await status() } }.disabled(busy) }
                Link(String(localized: "Contact Support"), destination: URL(string: "mailto:hi@tianli.cyou")!)
            }.navigationTitle(String(localized: "Delete Account"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Close")) { dismiss() } } }
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
                let expected = Api.localizedText(result, "expected_by") ?? String(localized: "usually within 30 days")
                message = String(localized: "Your request was accepted. Deletion is not complete. Expected: \(expected). Check its status here.")
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
            let expected = Api.localizedText(result, "expected_by") ?? String(localized: "usually within 30 days")
            message = result["status"] as? String == "completed" ? String(localized: "Your account and related data have been deleted.") : String(localized: "Deletion is in progress. Your data has not been fully deleted. Expected: \(expected).")
        } catch { await store.confirmSessionFailure(error); message = error.localizedDescription }
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
}
