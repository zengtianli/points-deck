import SwiftUI
import WidgetKit

/// 只在传了 `-widgetpreview 1` 时出现的验证页 —— 把 Widget 的**同一份 View 代码**
/// 按各尺寸画出来看一眼。
///
/// 为什么需要它：把 widget 加到模拟器主屏要人手拖拽，headless 跑不了。
/// 而「装上了」和「画得出来」是两件事 —— 上一版这个 app 的第一屏就是装上了、
/// 起来了、截出来是白的。
///
/// ⚠ 它验的是视图代码，**不是**系统 widget 宿主的真实布局与刷新预算 ——
/// 那部分只能上真机看。别把这里的绿当成 widget 在锁屏上一定没问题。
struct WidgetPreviewView: View {
    private var entry: Entry { Entry(date: .now, snap: Snapshot.load()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("Widget 视图预览").font(.headline).foregroundStyle(.white)
                Text("数据来自共享 keychain 仓里的真实快照")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))

                block("systemSmall", w: 170, h: 170, family: .systemSmall)
                block("systemMedium", w: 360, h: 170, family: .systemMedium)
                #if os(iOS)   // 锁屏三种样式 iOS 独有，Mac 桌面小组件只有 system*
                block("accessoryRectangular（锁屏）", w: 340, h: 90, family: .accessoryRectangular)
                block("accessoryCircular（锁屏）", w: 90, h: 90, family: .accessoryCircular)
                block("accessoryInline（锁屏）", w: 340, h: 36, family: .accessoryInline)
                #endif
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func block(_ title: String, w: CGFloat, h: CGFloat, family: WidgetFamily) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.55))
            PointsWidgetView(entry: entry, familyOverride: family)
                .frame(width: w, height: h)
                .background(family == .systemSmall || family == .systemMedium
                            ? AnyView(Era(key: entry.snap.era).background)
                            : AnyView(Color.gray.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}
