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
        // 锁屏三种 family（iOS）与表盘复杂功能（watchOS）是同一组 accessory case，Mac / Vision 上不存在。
        // accessory 的底由系统画（锁屏、表盘），这里给透明底 —— 不声明 containerBackground，
        // 系统会用「Please adopt containerBackground API」占位顶掉整块。
        #if os(iOS) || os(watchOS)
        case .accessoryCircular:
            Gauge(value: entry.snap.progress) {
                Text("Points")
            } currentValueLabel: {
                Text(short(entry.snap.balance))
            }
            .gaugeStyle(.accessoryCircular)
            .watchTint(era.accent)
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Text(line)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.snap.houseName).font(.headline)
                Text(line).font(.caption)
                ProgressView(value: entry.snap.progress).tint(.white)
            }
            .containerBackground(for: .widget) { Color.clear }
        #endif
        #if os(watchOS)
        // 表盘四角：弧形的进度 + 角上的余额
        case .accessoryCorner:
            Text(short(entry.snap.balance))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: entry.snap.progress) { Text("Points") }
                        .tint(era.accent)
                }
                .containerBackground(for: .widget) { Color.clear }
        #endif
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Balance").font(.caption).foregroundStyle(.white.opacity(0.7))
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
            return String(localized: "Next tier: \(name) · \(n) to go")
        }
        return entry.snap.houseName
    }

    private func short(_ n: Int) -> String {
        n.formatted(.number.notation(.compactName))
    }
}

private extension View {
    /// 表盘是彩色的，圆形复杂功能的进度环用时代色；iOS 锁屏是单色，保持原样。
    @ViewBuilder
    func watchTint(_ color: Color) -> some View {
        #if os(watchOS)
        self.tint(color)
        #else
        self
        #endif
    }
}
