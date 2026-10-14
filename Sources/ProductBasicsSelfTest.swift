#if os(iOS)
import SwiftUI
import UIKit

/// Runs in the actual simulator App. No input events, real accounts or production cloud access.
struct ProductBasicsSelfTestView: View {
    var body: some View { Color.clear.task { await ProductBasicsSelfTest.run() } }
}

@MainActor
enum ProductBasicsSelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--ui-self-test") || CommandLine.arguments.contains("--basics-readback") }
    static var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("product-basics", isDirectory: true) }
    static func prepareIsolation() {
        setenv("APP_LIFECYCLE_SUPPORT_DIR", directory.appendingPathComponent("support").path, 1)
        setenv("APP_LIFECYCLE_CLOUD_DIR", directory.appendingPathComponent("cloud").path, 1)
    }
    static func write(_ name: String, _ value: Any) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    static func sync(_ configuration: AppConfiguration) async -> Error? {
        await withCheckedContinuation { continuation in configuration.reconcile { continuation.resume(returning: $0) } }
    }
    static func checkUpdate(_ model: MobileLifecycleModel) async -> Bool {
        model.checkForUpdates()
        for _ in 0..<250 {
            if !model.checking { return model.release != nil }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
    static func storeFixture(_ url: URL) async -> Result<AppRelease, Error> {
        // A real HTTPS test server supplies the store response to the very transport and parser used by the App.
        await withCheckedContinuation { continuation in
            AppUpdateChecker.fetch(url) { result in
                continuation.resume(returning: result.flatMap { data in Result { try AppUpdateChecker.appStore(data, id: "6806799638", bundleID: "cyou.tianli.pointsdeck") } })
            }
        }
    }
    static func hiddenPanel<V: View>(_ view: V, name: String, size: CGSize) async throws -> Bool {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return false }
        let host = UIHostingController(rootView: view)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: -10000, y: -10000, width: size.width, height: size.height)
        window.alpha = 0; window.isUserInteractionEnabled = false; window.rootViewController = host
        // Realize SwiftUI's form without a key window or any visible surface; never makeKeyAndVisible.
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        for _ in 0..<5 { host.view.setNeedsLayout(); host.view.layoutIfNeeded(); try? await Task.sleep(for: .milliseconds(100)) }
        // UIKit constrains scene windows to the display. Preserve the realized safe-area geometry in a hidden,
        // transparent, non-key window and render its content layer in process, rather than reading screen pixels.
        window.isHidden = true
        let rendered = try capture(host.view, name: name, size: size, requireDetached: false)
        return rendered && !window.isKeyWindow && window.isHidden && window.alpha == 0 && !window.isUserInteractionEnabled
    }
    static func capture(_ view: UIView, name: String, size: CGSize, requireDetached: Bool = true) throws -> Bool {
        view.frame = CGRect(origin: .zero, size: size)
        view.setNeedsLayout(); view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.systemBackground.setFill(); context.fill(CGRect(origin: .zero, size: size))
            view.layer.render(in: context.cgContext)
        }
        guard let png = image.pngData() else { return false }
        try png.write(to: directory.appendingPathComponent(name))
        return png.count > 3000 && (!requireDetached || view.window == nil)
    }
    static func run() async {
        prepareIsolation()
        let defaults = UserDefaults(suiteName: "test.points.product-basics")!
        let preferences = TreasuryPreferences(defaults: defaults)
        if CommandLine.arguments.contains("--basics-readback") {
            do { try write("readback.json", preferences.readback); exit(0) }
            catch { exit(1) }
        }
        var checks: [String: Bool] = [:]
        var observations: [String: Any] = [:]
        func record(_ name: String, _ passed: Bool) { checks[name] = passed }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defaults.removePersistentDomain(forName: "test.points.product-basics")
            preferences.reload()
            let controls = TreasuryPreferenceControls(preferences: preferences)
            controls.tabs.selectedSegmentIndex = 1; controls.tabs.sendActions(for: .valueChanged)
            controls.celebrations.isOn = false; controls.celebrations.sendActions(for: .valueChanged)
            record("settings.controls_changed_model", preferences.startTab == 1 && !preferences.celebrations)
            record("settings.controls_rendered_offscreen", try capture(controls, name: "settings-controls.png", size: CGSize(width: 370, height: 200)))
            let model = MobileLifecycleModel(productID: "points-deck", channel: MobileProductLifecycle.channel, configuration: preferences.configuration)
            record("settings.real_panel_offscreen", try await hiddenPanel(TreasurySettingsView(preferences: preferences, lifecycle: model), name: "settings-panel.png", size: CGSize(width: 402, height: 874)))
            record("settings.shared_sync_update_panel_offscreen", try await hiddenPanel(AppLifecycleMobilePanel(model: model), name: "sync-update-panel.png", size: CGSize(width: 402, height: 874)))
            let exported = try preferences.configuration.exportData()
            try exported.write(to: directory.appendingPathComponent("export.json"))
            let object = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
            let keys = Set((object["values"] as! [String: Any]).keys)
            record("settings.privacy_allowlist", keys.isSubset(of: Set(TreasuryPreferences.keys.map { "defaults." + $0 })))
            preferences.setTab(4)
            try preferences.configuration.importData(exported); preferences.reload(); controls.reload()
            record("settings.valid_import", preferences.startTab == 1 && controls.tabs.selectedSegmentIndex == 1)
            let before = try preferences.configuration.exportData()
            let invalid: [String: Any] = ["version": 1, "product": "points-deck", "values": ["defaults." + TreasuryPreferences.tabKey: 9]]
            var rejected = false
            do { try preferences.configuration.importData(JSONSerialization.data(withJSONObject: invalid)) } catch { rejected = true }
            let afterInvalid = try preferences.configuration.exportData()
            record("settings.error_preserves_data", rejected && afterInvalid == before)
            record("settings.interaction", checks["settings.controls_changed_model"] == true && checks["settings.controls_rendered_offscreen"] == true && checks["settings.real_panel_offscreen"] == true)

            let store = Store()
            let env = ProcessInfo.processInfo.environment
            guard let base = env["POINTS_BASICS_API"], let user = env["POINTS_BASICS_USER"], let password = env["POINTS_BASICS_PASSWORD"] else { throw AppUpdateError("缺少隔离演示账本输入") }
            UserDefaults.standard.set(base, forKey: "api_base")
            await store.login(user: user, password: password)
            let oldBalance = store.state?.balance
            store.state = nil
            var refresh: Task<Void, Never>?
            let dispatched = preferences.performShortcut(key: "r", command: true) { refresh = Task { await TreasuryActions.refresh(store) } }
            await refresh?.value
            record("shortcuts.action_path", dispatched && oldBalance != nil && store.state?.balance == oldBalance)
            controls.shortcut.isOn = false; controls.shortcut.sendActions(for: .valueChanged)
            var count = 0
            let disabled = !preferences.performShortcut(key: "r", command: true) { count += 1 }
            controls.shortcut.isOn = true; controls.shortcut.sendActions(for: .valueChanged)
            let restored = preferences.performShortcut(key: "r", command: true) { count += 1 }
            record("shortcuts.disable_restore", disabled && restored && count == 1 && preferences.shortcutEnabled)
            record("shortcuts.conflict_or_reserved_keys", !preferences.performShortcut(key: "q", command: true) { count += 1 } && !preferences.performShortcut(key: "r", command: false) { count += 1 } && count == 1)
            store.dropSession()

            // Use the shared transport with a private cloud directory, never NSUbiquitousKeyValueStore.
            let config = preferences.configuration
            config.setEnabled(true)
            let pushed = await sync(config)
            let cloud = directory.appendingPathComponent("cloud/points-deck.json")
            let remoteDefaults = UserDefaults(suiteName: "test.points.product-basics.receiver")!
            remoteDefaults.removePersistentDomain(forName: "test.points.product-basics.receiver")
            setenv("APP_LIFECYCLE_SUPPORT_DIR", directory.appendingPathComponent("receiver").path, 1)
            let receiver = TreasuryPreferences(defaults: remoteDefaults)
            receiver.configuration.setEnabled(true)
            let pulled = await sync(receiver.configuration); receiver.reload()
            let received = receiver.startTab == 1 && !receiver.celebrations
            receiver.setTab(3)
            let remotePushed = await sync(receiver.configuration)
            let changed = await sync(config); preferences.reload()
            record("icloud.push_pull", pushed == nil && pulled == nil && remotePushed == nil && changed == nil && cloud.isFileURL && received && preferences.startTab == 3)
            receiver.configuration.setEnabled(false)
            let remoteBefore = try Data(contentsOf: cloud)
            unsetenv("APP_LIFECYCLE_CLOUD_DIR")
            let unavailable = await sync(config)
            preferences.setCelebrations(true)
            record("icloud.unavailable_local_fallback", unavailable != nil && preferences.celebrations && preferences.startTab == 3)
            setenv("APP_LIFECYCLE_CLOUD_DIR", directory.appendingPathComponent("cloud").path, 1)
            try Data("{broken".utf8).write(to: cloud)
            let corrupt = await sync(config)
            record("icloud.corrupt_keeps_local", corrupt != nil && preferences.startTab == 3 && preferences.celebrations)
            // Concurrent changes: local start column wins, independent remote shortcut switch is merged.
            var remote = try JSONSerialization.jsonObject(with: remoteBefore) as! [String: Any]
            var values = remote["values"] as! [String: Any]
            values["defaults." + TreasuryPreferences.tabKey] = 2
            values["defaults." + TreasuryPreferences.shortcutKey] = false
            remote["values"] = values
            try JSONSerialization.data(withJSONObject: remote).write(to: cloud)
            defaults.set(4, forKey: TreasuryPreferences.tabKey); preferences.reload()
            let recovered = await sync(config); preferences.reload()
            record("icloud.conflict_or_corrupt_recovery", checks["icloud.corrupt_keeps_local"] == true && recovered == nil && preferences.startTab == 4 && !preferences.shortcutEnabled)
            let localBeforeOff = try config.exportData(), cloudBeforeOff = try Data(contentsOf: cloud)
            model.setCloudEnabled(false)
            let disabledSyncError = await sync(config)
            let localAfterOff = try config.exportData(), cloudAfterOff = try Data(contentsOf: cloud)
            record("icloud.disable_preserves_data", disabledSyncError == nil && !config.enabled && config.status.contains("已关闭") && localAfterOff == localBeforeOff && cloudAfterOff == cloudBeforeOff)

            let configurationBeforeUpdate = try config.exportData()
            guard let feed = env["POINTS_BASICS_UPDATE_URL"], let feedURL = URL(string: feed) else { throw AppUpdateError("缺少隔离HTTPS商店测试源") }
            let valid = await storeFixture(feedURL.appendingPathComponent("valid"))
            let unavailableFeed = await storeFixture(feedURL.appendingPathComponent("unavailable"))
            let malformed = await storeFixture(feedURL.appendingPathComponent("broken"))
            let recoveredFeed = await storeFixture(feedURL.appendingPathComponent("valid"))
            var fixturePassed = false, unavailableFailed = false, malformedFailed = false, recoveredFeedPassed = false
            if case .success(let release) = valid { fixturePassed = release.version == "9.0.0" && release.isNewer(than: model.version, build: model.build) }
            if case .failure(let error) = unavailableFeed { unavailableFailed = true; observations["update_unavailable_error"] = error.localizedDescription }
            if case .failure(let error) = malformed { malformedFailed = true; observations["update_malformed_error"] = error.localizedDescription }
            if case .success(let release) = recoveredFeed { recoveredFeedPassed = release.version == "9.0.0" }
            let official = await checkUpdate(model)
            observations["official_store_status"] = model.updateStatus
            observations["official_store_version"] = model.release?.version ?? ""
            record("updates.check_result", official && fixturePassed)
            record("updates.failure_recovery", unavailableFailed && malformedFailed && recoveredFeedPassed)
            record("updates.options_or_store_entry", model.updateURL?.host == "apps.apple.com" && model.updateURL?.path.contains("id6806799638") == true && model.channel.name == "App Store")
            record("updates.data_preservation", (try config.exportData()) == configurationBeforeUpdate)
            preferences.setTab(4); preferences.setCelebrations(false); preferences.setShortcut(true)
            try write("expected-readback.json", preferences.readback)
            observations["preferences"] = preferences.readback
            observations["ui"] = ["control_window_attached": controls.window != nil, "hidden_panel_passed": checks["settings.real_panel_offscreen"] == true]
        } catch { observations["error"] = error.localizedDescription }
        do {
            try write("raw.json", ["schema_version": 1, "checks": checks, "observations": observations,
                "environment": "actual iOS simulator app, offscreen controls and panel, isolated shared configuration transport",
                "apple_cross_device_delivery": "not tested", "version": Bundle.main.shortVersion,
                "bundle_id": Bundle.main.bundleIdentifier ?? ""])
            exit(checks.values.allSatisfy { $0 } && observations["error"] == nil ? 0 : 1)
        } catch { exit(1) }
    }
}
#endif
