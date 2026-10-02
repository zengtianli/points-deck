import SwiftUI
import WidgetKit

/// 锁屏 / 主屏 Widget —— 「还差 N 分升级到 X」常驻在眼前。
///
/// 这是整个 app 最有存在理由的一块：那句话现在只在打开页面时可见，
/// 放到锁屏才是真的一直在眼前。
///
/// **Widget 不联网**：它读共享 keychain 仓里主 app 每次刷新时写下的快照。
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
        .configurationDisplayName(AppIdentity.displayName)
        .description("总市值与「还差多少升级」")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])   // accessory* = 锁屏，iOS 独有
        #elseif os(watchOS)
        // 表盘复杂功能：圆形进度、矩形一行字 + 进度、表盘顶上一行字、四角弧形。
        // 数据是手表 app 每次刷新写进手表本机钥匙串的快照（同一份 Snapshot），手表 app 不开时会变旧。
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}
