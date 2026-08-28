import Foundation
import LocalAuthentication
import Security

/// 管理密码的保管处 —— **Face ID 包住它，但不替代它**。
///
/// `~/Edu` 的设计是「家长密码每次现输，不发 cookie」，理由是：孩子拿到已登录的平板
/// 也加不了分。能自己给自己加分的积分系统，第二天就变成刷分游戏。
///
/// 这条不能破，所以这里不是「记住登录状态」，而是：密码存进 Keychain 并要求
/// **生物识别才读得出来**，每次记账仍然是「取出密码 → 随请求发一次 → 用完丢掉」。
/// 孩子拿着解锁的手机也读不出这个密码（Face ID 是家长的脸）。
enum AdminGate {
    private static let service = "cyou.tianli.pointsdeck.admin"
    private static let account = "parent"

    enum Failure: LocalizedError {
        case notSaved
        case denied(String)
        var errorDescription: String? {
            switch self {
            case .notSaved: return "还没保存过家长密码"
            case .denied(let m): return m
            }
        }
    }

    static var hasSaved: Bool {
        // 只问「在不在」，不取值 —— 取值会弹 Face ID，而这里只是要决定界面显示什么
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let st = SecItemCopyMatching(q as CFDictionary, nil)
        // errSecInteractionNotAllowed = 存在但需要验证才能读 —— 这正是我们要的状态
        return st == errSecSuccess || st == errSecInteractionNotAllowed
    }

    static func save(_ password: String) throws {
        var err: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,   // 不进 iCloud 钥匙串，不跟着换机走
            .userPresence,                                  // 读取时必须 Face ID / 密码
            &err) else {
            throw Failure.denied("建不了 Keychain 访问控制：\(err?.takeRetainedValue().localizedDescription ?? "")")
        }
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessControl as String: access,
        ]
        let st = SecItemAdd(add as CFDictionary, nil)
        guard st == errSecSuccess else { throw Failure.denied("存不进 Keychain(\(st))") }
    }

    static func forget() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    /// 取密码 —— 会弹 Face ID。**取出来只用于这一次请求，别往任何地方缓存。**
    static func password(reason: String) async throws -> String {
        let ctx = LAContext()
        ctx.localizedReason = reason
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: ctx,
        ]
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        if st == errSecItemNotFound { throw Failure.notSaved }
        guard st == errSecSuccess, let d = out as? Data, let s = String(data: d, encoding: .utf8) else {
            throw Failure.denied(st == errSecUserCanceled ? "取消了验证" : "读不出家长密码(\(st))")
        }
        return s
    }
}
