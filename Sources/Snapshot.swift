import Foundation
import Security

/// 主 app 与 Widget **共用的一份**快照定义。
///
/// 放在这里而不是各写一份结构体：字段一改就得两处同步，那是必然会漂的写法。
/// 两个 target 在 project.yml 里都引用这个文件。
struct Snapshot: Codable {
    var balance: Int
    var houseName: String
    var nextName: String?
    var toNext: Int?
    var progress: Double
    var era: String
    var updated: Date

    static let empty = Snapshot(balance: 0, houseName: "—", nextName: nil, toNext: nil,
                                progress: 0, era: "slum", updated: .distantPast)
}

// MARK: - 跨进程共享：走 keychain access group，**不是** App Group
//
// 为什么换掉 App Group（2026-08-28 实测）：
//   App Group 的组标识必须先在 Apple 开发者门户登记，而登记只能在 Xcode 图形界面
//   或网页上做。`xcodebuild -allowProvisioningUpdates` 建得了 App ID、**建不了
//   App Group** —— 表现是拉回来的描述文件里
//   `com.apple.security.application-groups` 是个**空数组**（能力开着、组是空的），
//   于是编译期报 "profile doesn't match the entitlements file's value"。
//   加入付费计划也不解决这一条，它跟收不收费无关。
//
//   keychain access group 不一样：开发描述文件**默认**就带 `<TeamID>.*` 通配
//   （实测本机 profile 里 keychain-access-groups = ["B9LJH93LA4.*", "com.apple.token"]），
//   任何以 team 前缀开头的组名都直接可用，零登记、纯命令行跑得通。
//
// ⚠ 故意**不传** `kSecAttrAccessGroup`：不传时 keychain 用 entitlement 里的
//   **第一个**组。两个 target 的 `keychain-access-groups` 第一项写成同一个，
//   就是同一个仓 —— 这样 TeamID 一个字都不进源码（它随账号变，写进来就是第二份真相；
//   今天这个账号刚从 8ZUVJNUK29 换到 B9LJH93LA4，正是会漂的证据）。
//   这条契约由 `check_shared_group.py` 在**构建产物**上对账，两边不一致即红。
extension Snapshot {
    private static let service = "cyou.tianli.pointsdeck.snapshot"
    private static let account = "current"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> Snapshot {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data,
              let s = try? JSONDecoder().decode(Snapshot.self, from: d) else { return .empty }
        return s
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        let q = Snapshot.baseQuery
        // AfterFirstUnlock 而不是默认的 WhenUnlocked —— 锁屏小组件要画的时候
        // 设备是锁着的，用默认值它会读不到，表现是「锁屏上永远是空的」。
        let attrs: [String: Any] = [
            kSecValueData as String: d,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if SecItemUpdate(q as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            var add = q
            add.merge(attrs) { a, _ in a }
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
