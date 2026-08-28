import Foundation

/// 练习页清单 —— 由 `~/Edu/engine/app_pack.py` 在构建前写进 bundle 的 manifest.json 派生。
///
/// **这个文件里没有任何一课的名字、日期、学科。** 全都从 manifest 读。
/// 写死一份的下场：~/Edu 那边加了课(走 /course)，app 这边要改代码才跟得上，
/// 而漏改不报错 —— 只是那一课不出现在列表里。对账门在 `app_pack.py --check`。
struct Lesson: Identifiable, Hashable {
    let slug: String
    let title: String
    let desc: String
    let file: String            // 相对 bundle 的路径，如 primary-math/remainder-basics.html
    let subject: String         // domains.yaml 的 key，如 math / chinese
    let subjectName: String
    let unit: String
    let date: String
    let source: String
    let tag: String
    let sha256: String

    var id: String { slug }

    /// bundle 里的真实文件位置。folder 引用进包后保持 Lessons/primary-*/ 结构。
    var bundleURL: URL? {
        Bundle.main.url(forResource: "Lessons/" + file, withExtension: nil)
    }
}

/// bundle 里那一包练习页。**只读**，不做下载、不做缓存 —— 页面随包发（离线是这个 app 存在的理由）。
struct LessonPack {
    let lessons: [Lesson]
    let dailyGoal: Int
    /// 组装器缺席 / manifest 读不动时的原因，给界面显示 —— 不是静默空列表。
    let problem: String?

    static let empty = LessonPack(lessons: [], dailyGoal: 12,
                                  problem: "bundle 里没有练习页（构建时 sync-lessons.sh 没跑？）")

    /// 按学科分组，保持 manifest 里的顺序（那就是 curriculum.yaml 的顺序）。
    var bySubject: [(key: String, name: String, lessons: [Lesson])] {
        var order: [String] = []
        var bucket: [String: [Lesson]] = [:]
        for l in lessons {
            if bucket[l.subject] == nil { order.append(l.subject) }
            bucket[l.subject, default: []].append(l)
        }
        return order.map { k in
            (key: k, name: bucket[k]?.first?.subjectName ?? k, lessons: bucket[k] ?? [])
        }
    }

    static func load() -> LessonPack {
        guard let u = Bundle.main.url(forResource: "Lessons/manifest", withExtension: "json"),
              let d = try? Data(contentsOf: u),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            return .empty
        }
        let raw = (o["lessons"] as? [[String: Any]]) ?? []
        let list = raw.map { j in
            Lesson(slug: j["slug"] as? String ?? "",
                   title: j["title"] as? String ?? "",
                   desc: j["desc"] as? String ?? "",
                   file: j["file"] as? String ?? "",
                   subject: j["subject"] as? String ?? "",
                   subjectName: j["subject_name"] as? String ?? "",
                   unit: j["unit"] as? String ?? "",
                   date: j["date"] as? String ?? "",
                   source: j["source"] as? String ?? "",
                   tag: j["tag"] as? String ?? "",
                   sha256: j["sha256"] as? String ?? "")
        }
        // 空集不静默：manifest 在但一课都没有，是组装出了问题，不是「就这样」
        if list.isEmpty {
            return LessonPack(lessons: [], dailyGoal: o["daily_goal"] as? Int ?? 12,
                              problem: "manifest 里一课都没有")
        }
        // bundle 里真有那个文件吗 —— manifest 说有而文件没进包，表现是「点进去白屏」
        let missing = list.filter { $0.bundleURL == nil }
        return LessonPack(
            lessons: list,
            dailyGoal: o["daily_goal"] as? Int ?? 12,
            problem: missing.isEmpty ? nil
                : "有 \(missing.count) 课的页面没进包：" + missing.prefix(3).map(\.slug).joined(separator: "、"))
    }
}
