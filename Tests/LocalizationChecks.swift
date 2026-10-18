import Foundation

/// Compile with the production Api/RemoteUI/Skin sources inside a localized, LSUIElement bundle.
/// Run twice with -AppleLanguages '(en)' / '(zh-Hans)' and --expect-language en / zh-Hans.
/// No network, UI, keychain, simulator, or production account is used.
@main
struct LocalizationChecks {
    enum Failure: Error, CustomStringConvertible {
        case assertion(String)
        var description: String { switch self { case .assertion(let name): return "Localization check failed: \(name)" } }
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--expect-language"), arguments.indices.contains(index + 1),
              ["en", "zh-Hans"].contains(arguments[index + 1]) else {
            throw Failure.assertion("Supply --expect-language en or zh-Hans")
        }
        let language = arguments[index + 1]
        let english = language == "en"
        var checks: [String] = []
        func check(_ name: String, _ passed: @autoclosure () -> Bool) throws {
            guard passed() else { throw Failure.assertion(name) }
            checks.append(name)
        }
        try check("bundle_language", Bundle.main.preferredLocalizations.first == language)
        try check("api_language", Api.usesEnglish == english)
        try check("catalog_runtime", String(localized: "Settings") == (english ? "Settings" : "设置"))

        let bilingual: [String: Any] = ["label": ["en": "Ready", "zh-Hans": "就绪"]]
        try check("map_language", Api.localizedText(bilingual, "label") == (english ? "Ready" : "就绪"))
        try check("flat_language", Api.localizedText(["label": "就绪", "label_en": "Ready"], "label") == (english ? "Ready" : "就绪"))
        try check("legacy_chinese_fallback", Api.localizedText(["label": "旧提示"], "label") == "旧提示")
        try check("map_missing_english_fallback", Api.localizedText(["label": ["zh-Hans": "旧提示"]], "label") == "旧提示")
        try check("map_empty_english_fallback", Api.localizedText(["label": ["en": "", "zh-Hans": "旧提示"]], "label") == "旧提示")
        try check("flat_empty_english_fallback", Api.localizedText(["label": "旧提示", "label_en": ""], "label") == "旧提示")
        try check("english_only_fallback", Api.localizedText(["label": ["en": "Ready"]], "label") == "Ready")
        try check("flat_english_only_fallback", Api.localizedText(["label_en": "Ready"], "label") == "Ready")
        try check("missing_text", Api.localizedText([:], "label") == nil)
        try check("invalid_number", Api.localizedText(["label": 27], "label") == nil)
        try check("invalid_array", Api.localizedText(["label": ["Ready"]], "label") == nil)
        try check("invalid_map_fallback", Api.localizedText(["label": ["en": 27, "zh-Hans": "旧提示"]], "label") == "旧提示")
        try check("invalid_map_no_text", Api.localizedText(["label": ["en": NSNull(), "zh-Hans": false]], "label") == nil)
        try check("chinese_alias", Api.localizedText(["label": ["zh-CN": "旧提示"]], "label") == "旧提示")
        var suffixOnly: [String: Any] = ["label_en": "Old"]
        Api.setLocalizedText(&suffixOnly, "label", "New")
        try check("suffix_only_edit_readback", Api.localizedText(suffixOnly, "label") == "New")

        let editedText = english ? "Updated label" : "更新后的名称"
        var mapEdit: [String: Any] = [
            "label": ["en": "Ready", "zh-Hans": "就绪", "fr": "Prêt", "future": 17],
            "id": "stable-id", "opaque": ["keep": "unrelated value"]
        ]
        Api.setLocalizedText(&mapEdit, "label", editedText)
        let editedMap = mapEdit["label"] as? [String: Any]
        try check("edit_map_current_language", editedMap?[english ? "en" : "zh-Hans"] as? String == editedText)
        try check("edit_map_other_language", editedMap?[english ? "zh-Hans" : "en"] as? String == (english ? "就绪" : "Ready"))
        try check("edit_map_unknown_language", editedMap?["fr"] as? String == "Prêt")
        try check("edit_map_unknown_value", editedMap?["future"] as? Int == 17)
        try check("edit_preserves_unrelated_fields", mapEdit["id"] as? String == "stable-id" && (mapEdit["opaque"] as? [String: String])?["keep"] == "unrelated value")
        try check("edit_map_readback", Api.localizedText(mapEdit, "label") == editedText)

        var legacyEdit: [String: Any] = ["label": "原名称", "label_en": "Original label", "revision": "keep-revision"]
        Api.setLocalizedText(&legacyEdit, "label", editedText)
        try check("edit_legacy_base_preserved_or_updated", legacyEdit["label"] as? String == (english ? "原名称" : editedText))
        try check("edit_legacy_english_updated_or_preserved", legacyEdit["label_en"] as? String == (english ? editedText : "Original label"))
        try check("edit_legacy_revision_preserved", legacyEdit["revision"] as? String == "keep-revision")
        try check("edit_legacy_readback", Api.localizedText(legacyEdit, "label") == editedText)

        var newEdit: [String: Any] = ["id": "new-item"]
        Api.setLocalizedText(&newEdit, "label", editedText)
        try check("edit_new_value_is_scalar", newEdit["label"] as? String == editedText && newEdit["label_en"] == nil)
        try check("edit_new_value_readback", Api.localizedText(newEdit, "label") == editedText)
        var emptyEdit: [String: Any] = ["label": ""]
        Api.setLocalizedText(&emptyEdit, "label", editedText)
        try check("edit_empty_value_is_scalar", emptyEdit["label"] as? String == editedText && emptyEdit["label_en"] == nil)

        let defaults = UserDefaults.standard
        let oldCache = defaults.data(forKey: "account_hints")
        let oldRemote = Remote.ui
        defer {
            if let oldCache {
                defaults.set(oldCache, forKey: "account_hints")
                AccountHints.restore()
            } else {
                AccountHints.adopt([:])
                defaults.removeObject(forKey: "account_hints")
            }
            Remote.ui = oldRemote
        }
        let payload: [String: Any] = [
            "resend_seconds": 90,
            "code_ttl_seconds": 420,
            "ui": [
                "copy": [
                    "probe.map": ["en": "Code expires in {minutes} minutes.", "zh-Hans": "验证码 {minutes} 分钟内有效。"],
                    "probe.flat": "中文提示", "probe.flat_en": "English hint",
                    "probe.legacy": "旧提示", "probe.bad": 17, "probe.only_en": "English-only copy"
                ],
                "vocab": ["ready": ["label": ["en": "Ready", "zh-Hans": "就绪"], "icon": "checkmark", "tone": "good"]],
                "order": ["ready"],
                "limits": ["poll": 120.0, "attempts": 3.6]
            ]
        ]
        AccountHints.adopt(payload)
        try check("hints_resend", AccountHints.resendSeconds() == 90)
        try check("hints_code_minutes", AccountHints.codeMinutes() == 7)
        try check("hints_receipt_resend", AccountHints.resendSeconds(receipt: 15) == 15)
        try check("hints_receipt_code", AccountHints.codeMinutes(receipt: 180) == 3)
        try check("hints_receipt_bool_ignored", AccountHints.resendSeconds(receipt: true) == 90)
        try check("remote_map_language", T("probe.map", "fallback", ["minutes": "7"]) == (english ? "Code expires in 7 minutes." : "验证码 7 分钟内有效。"))
        try check("remote_flat_language", T("probe.flat", "fallback") == (english ? "English hint" : "中文提示"))
        try check("remote_legacy_fallback", T("probe.legacy", "fallback") == "旧提示")
        try check("remote_english_only_fallback", T("probe.only", "fallback") == "English-only copy")
        try check("remote_bad_copy_fallback", T("probe.bad", "fallback") == "fallback")
        try check("vocab_label_language", Remote.label("ready", "fallback") == (english ? "Ready" : "就绪"))
        try check("vocab_icon_preserved", Remote.icon("ready", "fallback") == "checkmark")
        try check("vocab_tone_preserved", Remote.tone("ready") == "good")
        try check("remote_order_preserved", Remote.order(["fallback"]) == ["ready"])
        try check("remote_seconds_clamped", Remote.seconds("poll", 5, in: 10...60) == 60)
        try check("remote_count_rounded", Remote.count("attempts", 1, in: 1...10) == 4)
        Remote.ui = nil
        AccountHints.restore()
        try check("offline_cache_language", T("probe.flat", "fallback") == (english ? "English hint" : "中文提示"))
        try check("offline_cache_template", T("probe.map", "fallback", ["minutes": "7"]) == (english ? "Code expires in 7 minutes." : "验证码 7 分钟内有效。"))

        AccountHints.adopt(["resend_seconds": 99999, "code_ttl_seconds": 1, "ui": "invalid"])
        try check("hints_upper_bound", AccountHints.resendSeconds() == 600)
        try check("hints_lower_bound", AccountHints.codeMinutes() == 1)
        try check("bad_ui_falls_back", T("probe.flat", "fallback") == "fallback")
        try check("bad_vocab_falls_back", Remote.label("ready", "fallback") == "fallback")
        try check("bad_limits_fall_back", Remote.seconds("poll", 15, in: 10...60) == 15)
        AccountHints.adopt(["resend_seconds": "invalid", "code_ttl_seconds": false, "ui": NSNull()])
        try check("bad_resend_default", AccountHints.resendSeconds() == 60)
        try check("bad_code_default", AccountHints.codeMinutes() == 5)
        AccountHints.adopt([:])
        try check("old_payload_default", AccountHints.resendSeconds() == 60 && AccountHints.codeMinutes() == 5 && Remote.ui == nil)

        let report: [String: Any] = ["passed": true, "language": language, "checks": checks, "network_requests": 0, "ui_windows": 0]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
