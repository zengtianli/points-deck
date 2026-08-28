import Foundation

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

    static let group = "group.cyou.tianli.pointsdeck"
    private static let key = "snapshot"

    static func load() -> Snapshot {
        guard let d = UserDefaults(suiteName: group)?.data(forKey: key),
              let s = try? JSONDecoder().decode(Snapshot.self, from: d) else { return .empty }
        return s
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(d, forKey: Self.key)
    }
}
