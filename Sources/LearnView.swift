import SwiftUI

/// 学习路径 —— 学科 → 课，从 bundle 里的 manifest 派生（manifest 又从 curriculum.yaml 派生）。
///
/// **这一屏不判断哪一课该不该出现。** curriculum.yaml 说有几课就是几课，
/// 组装器 `app_pack.py` 已经把「筹备中的学科」「精讲页」筛掉了。
/// 在这里再筛一遍就是第二份判据，而两份判据迟早说不同的话。
struct LearnView: View {
    @EnvironmentObject var store: Store
    private let pack = LessonPack.load()
    @State private var open: Lesson?

    private var era: Era { store.state?.era ?? .slum }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let p = pack.problem {
                    // 空列表不静默:说清是包的问题，不是「今天没课」
                    Label(p, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                }
                ForEach(pack.bySubject, id: \.key) { g in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(g.name)
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(.white)
                        ForEach(g.lessons) { l in
                            Button { open = l } label: { card(l) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
        .fullScreenCover(item: $open) { l in
            LessonScreen(lesson: l).environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("学习路径").font(.largeTitle.weight(.black)).foregroundStyle(.white)
            Text("\(pack.lessons.count) 课 · 每天目标 \(pack.dailyGoal) 题 · 离线也能做")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func card(_ l: Lesson) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(l.title).font(.headline).foregroundStyle(.white)
                if !l.desc.isEmpty {
                    Text(l.desc).font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                HStack(spacing: 8) {
                    if !l.unit.isEmpty { tagChip(l.unit) }
                    if !l.date.isEmpty { tagChip(l.date) }   // 日期 SSOT 在 .practice.md
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private func tagChip(_ s: String) -> some View {
        Text(s)
            .font(.caption2)
            .foregroundStyle(era.accent)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.white.opacity(0.14), in: Capsule())
    }
}

/// 做题屏 —— 一整屏交给引擎，原生只留一条顶栏（退出 + 课名）。
///
/// 顶栏做得薄是有意的：练习页自己有题号条、任务条、等级条，
/// 原生再叠一层导航就会把它们挤下去 —— 那正是 fitcoach-ios 踩过的
/// 「.bottomBar 被 TabView 压住」同一类错。
struct LessonScreen: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let lesson: Lesson

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline)
                }
                Text(lesson.title).font(.headline).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial)

            LessonWebView(lesson: lesson) {
                // 交卷了 —— 分是网页自己记的(points_client.js)，这里只把余额拉新
                Task { await store.refresh() }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .task { await WebSession.handOff() }     // 把登录 cookie 借给 WebView
    }
}


/// `-lesson <slug>` 的落点 —— 只为验证「离线 / 未登录也能做题」。
struct LessonPreview: View {
    @EnvironmentObject var store: Store
    let slug: String
    private let pack = LessonPack.load()

    var body: some View {
        if let l = pack.lessons.first(where: { $0.slug == slug }) {
            LessonScreen(lesson: l).environmentObject(store)
        } else {
            // 找不到就说清有哪些 —— 静默白屏会让人以为是 WebView 挂了
            ScrollView {
                Text("包里没有 \(slug)\n\n现有 \(pack.lessons.count) 课：\n"
                     + pack.lessons.map(\.slug).joined(separator: "\n"))
                    .font(.footnote.monospaced()).padding(20)
            }
        }
    }
}
