import SwiftUI
import CoreFoundation
#if os(iOS)
import UIKit
#endif

/// Only presentation preferences travel. Sessions, account data, ledger and lane arguments never do.
@MainActor
final class TreasuryPreferences: ObservableObject {
    nonisolated static let tabKey = "treasury.startTab"
    nonisolated static let celebrationKey = "treasury.celebrations"
    nonisolated static let shortcutKey = "treasury.refreshShortcut"
    nonisolated static let keys = [tabKey, celebrationKey, shortcutKey]
    static let shared = TreasuryPreferences(defaults: .standard)
    let defaults: UserDefaults
    let configuration: AppConfiguration
    @Published private(set) var startTab = 0
    @Published private(set) var celebrations = true
    @Published private(set) var shortcutEnabled = true
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        configuration = AppConfiguration(productID: "points-deck", defaultsKeys: Self.keys,
            defaults: defaults, validateDefault: Self.validate)
        reload()
        configuration.onChange = { [weak self] in self?.reload() }
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: defaults, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
    }
    nonisolated static func validate(_ key: String, _ value: Any) throws {
        guard let number = value as? NSNumber else { throw AppUpdateError(String(localized: "Invalid preference type. Your settings have been kept.")) }
        if key == tabKey {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), (0...4).contains(number.intValue),
                  number.doubleValue == Double(number.intValue) else { throw AppUpdateError(String(localized: "Choose Ledger, Trends, Add Points, Rewards, or Account as the start tab.")) }
        } else {
            guard CFGetTypeID(number) == CFBooleanGetTypeID() else { throw AppUpdateError(String(localized: "Switch values must be true or false. Your settings have been kept.")) }
        }
    }
    func reload() {
        let tab = defaults.integer(forKey: Self.tabKey)
        startTab = (0...4).contains(tab) ? tab : 0
        celebrations = defaults.object(forKey: Self.celebrationKey) == nil || defaults.bool(forKey: Self.celebrationKey)
        shortcutEnabled = defaults.object(forKey: Self.shortcutKey) == nil || defaults.bool(forKey: Self.shortcutKey)
    }
    func setTab(_ tab: Int) { guard (0...4).contains(tab) else { return }; defaults.set(tab, forKey: Self.tabKey); save() }
    func setCelebrations(_ enabled: Bool) { defaults.set(enabled, forKey: Self.celebrationKey); save() }
    func setShortcut(_ enabled: Bool) { defaults.set(enabled, forKey: Self.shortcutKey); save() }
    private func save() { defaults.synchronize(); reload(); if configuration.enabled { configuration.reconcile() } }
    var refreshBinding: KeyboardShortcut? { shortcutEnabled ? KeyboardShortcut("r", modifiers: .command) : nil }
    func performShortcut(key: String, command: Bool, action: () -> Void) -> Bool {
        guard key.count == 1, let binding = refreshBinding, command, binding.key == KeyEquivalent(Character(key.lowercased())),
              binding.modifiers == .command else { return false }
        action(); return true
    }
    var readback: [String: Any] {
        ["start_tab": startTab, "celebrations": celebrations, "shortcut_enabled": shortcutEnabled,
         "shortcut": "⌘R", "sync_enabled": configuration.enabled, "sync_status": configuration.status]
    }
}

@MainActor
enum TreasuryActions {
    static func refresh(_ store: Store) async { await store.refresh() }
}

struct TreasurySettingsView: View {
    @ObservedObject var preferences: TreasuryPreferences
    @ObservedObject var lifecycle: MobileLifecycleModel
    @Environment(\.dismiss) private var dismiss
    @State private var transfer = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Display & Controls") {
                    #if os(iOS)
                    TreasuryNativePreferences(preferences: preferences).frame(height: 188)
                    #else
                    Picker("Start Tab", selection: Binding(get: { preferences.startTab }, set: preferences.setTab)) {
                        ForEach(Array([String(localized: "Ledger"), String(localized: "Trends"), String(localized: "Add Points"), String(localized: "Rewards"), String(localized: "Account")].enumerated()), id: \.offset) { index, title in Text(title).tag(index) }
                    }
                    Toggle("Celebrate Tier Upgrades", isOn: Binding(get: { preferences.celebrations }, set: preferences.setCelebrations))
                    Toggle("Refresh Shortcut ⌘R", isOn: Binding(get: { preferences.shortcutEnabled }, set: preferences.setShortcut))
                    #endif
                    Text("⌘R refreshes this app's ledger. A keyboard is required on iPhone and iPad. Turning this off keeps your preferences and touch controls available. System editing shortcuts are unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Sync & Version") {
                    LabeledContent("iCloud", value: lifecycle.cloudEnabled ? String(localized: "On") : String(localized: "Off"))
                    Text(lifecycle.configurationStatus).font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Current Version", value: "\(lifecycle.version) (\(lifecycle.build))")
                    Button("Sync, Backup & Updates", systemImage: "arrow.triangle.2.circlepath") { transfer = true }
                    Text("Only start tab, celebration, and refresh shortcut preferences are synced. Your account and ledger stay on the server. Install iOS updates from the App Store.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(TreasuryTheme.accent)
            .sheet(isPresented: $transfer) { AppLifecycleMobilePanel(model: lifecycle) }
            .onAppear { lifecycle.start(); lifecycle.refreshConfiguration() }
    }
}

#if os(iOS)
/// The settings controls are also constructed offscreen by the in-process acceptance path.
struct TreasuryNativePreferences: UIViewRepresentable {
    var preferences: TreasuryPreferences
    func makeUIView(context: Context) -> TreasuryPreferenceControls { TreasuryPreferenceControls(preferences: preferences) }
    func updateUIView(_ view: TreasuryPreferenceControls, context: Context) { view.reload() }
}

@MainActor
final class TreasuryPreferenceControls: UIStackView {
    let preferences: TreasuryPreferences
    let tabs = UISegmentedControl(items: [String(localized: "Ledger"), String(localized: "Trends"), String(localized: "Add"), String(localized: "Rewards"), String(localized: "Account")])
    let celebrations = UISwitch()
    let shortcut = UISwitch()
    init(preferences: TreasuryPreferences) {
        self.preferences = preferences
        super.init(frame: .zero)
        axis = .vertical; spacing = 14; distribution = .fill
        tabs.apportionsSegmentWidthsByContent = true
        let title = UILabel(); title.text = String(localized: "Start Tab"); addArrangedSubview(title); addArrangedSubview(tabs)
        for (text, control) in [(String(localized: "Celebrate Tier Upgrades"), celebrations), (String(localized: "Refresh Shortcut ⌘R"), shortcut)] {
            let row = UIStackView(); row.axis = .horizontal
            let label = UILabel(); label.text = text; label.numberOfLines = 0; row.addArrangedSubview(label); row.addArrangedSubview(control)
            addArrangedSubview(row)
        }
        tabs.accessibilityIdentifier = "settings.startTab"
        celebrations.accessibilityIdentifier = "settings.celebrations"
        shortcut.accessibilityIdentifier = "settings.refreshShortcut"
        tabs.addTarget(self, action: #selector(changeTab), for: .valueChanged)
        celebrations.addTarget(self, action: #selector(changeCelebrations), for: .valueChanged)
        shortcut.addTarget(self, action: #selector(changeShortcut), for: .valueChanged)
        reload()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    func reload() { tabs.selectedSegmentIndex = preferences.startTab; celebrations.isOn = preferences.celebrations; shortcut.isOn = preferences.shortcutEnabled }
    @objc private func changeTab() { preferences.setTab(tabs.selectedSegmentIndex) }
    @objc private func changeCelebrations() { preferences.setCelebrations(celebrations.isOn) }
    @objc private func changeShortcut() { preferences.setShortcut(shortcut.isOn) }
}
#endif
