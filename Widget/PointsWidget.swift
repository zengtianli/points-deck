import SwiftUI
import WidgetKit

/// 锁屏 / 主屏 Widget —— 「还差 N 分升级到 X」常驻在眼前。
///
/// 这是整个 app 最有存在理由的一块：那句话现在只在打开页面时可见，
/// 放到锁屏才是真的一直在眼前。
///
/// **Widget 不联网**：它读 App Group 里主 app 每次刷新时写下的快照。
/// 让 Widget 自己去打账本要处理登录态/超时/重试，而它的刷新预算由系统说了算 ——
/// 拿不到数据时宁可显示上一次的快照，也不显示一个转圈。
struct Provider: TimelineProvider {
    func placeholder(in: Context) -> Entry { Entry(date: .now, snap: .empty) }
    func getSnapshot(in: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, snap: Snapshot.load()))
    }
    func getTimeline(in: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // 数据只有主 app 打开时才会变，所以不必频繁刷 —— 一小时一次，
        // 主 app 刷新后会主动 reloadAllTimelines，那才是真正的更新时机。
        let e = Entry(date: .now, snap: Snapshot.load())
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(3600))))
    }
}

@main
struct PointsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PointsWidget", provider: Provider()) { entry in
            PointsWidgetView(entry: entry)
        }
        .configurationDisplayName("京宝积分")
        .description("总市值与「还差多少升级」")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
