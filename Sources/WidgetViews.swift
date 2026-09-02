import SwiftUI
import WidgetKit

/// Widget 的**视图与时间线条目**，两个 target 共用一份。
///
/// 放这里而不是留在 widget target 里，是为了主 app 能把它渲染出来验证
/// （见 WidgetPreview.swift）—— 把 widget 拖到模拟器主屏这件事 headless 做不到，
/// 而「装上了」和「画得出来」是两件事。

struct Entry: TimelineEntry {
    let date: Date
    let snap: Snapshot
}

struct PointsWidgetView: View {
    // 系统给的尺寸(只读)。预览时用 familyOverride 顶掉 —— environment 改不了它。
    @Environment(\.widgetFamily) private var envFamily
    var entry: Entry
    var familyOverride: WidgetFamily?

    private var family: WidgetFamily { familyOverride ?? envFamily }

    private var era: Era { Era(key: entry.snap.era) }

    var body: some View {
        switch family {
        #if os(iOS)   // 锁屏三种 family 是 iOS 独有的 enum case，Mac 上不存在
        case .accessoryCircular:
            Gauge(value: entry.snap.progress) {
                Text("分")
            } currentValueLabel: {
                Text(short(entry.snap.balance))
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryInline:
            Text(line)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.snap.houseName).font(.headline)
                Text(line).font(.caption)
                ProgressView(value: entry.snap.progress).tint(.white)
            }
        #endif
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("总市值").font(.caption).foregroundStyle(.white.opacity(0.7))
                Text(RollingNumber.grouped(entry.snap.balance))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(line).font(.caption).foregroundStyle(era.accent)
                ProgressView(value: entry.snap.progress).tint(era.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { era.background }
        }
    }

    private var line: String {
        if let n = entry.snap.toNext, let name = entry.snap.nextName {
            return "还差 \(n) 分升「\(name)」"
        }
        return entry.snap.houseName
    }

    private func short(_ n: Int) -> String {
        n >= 10000 ? String(format: "%.1fw", Double(n) / 10000) : "\(n)"
    }
}
