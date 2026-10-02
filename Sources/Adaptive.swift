import SwiftUI
#if os(macOS)
import AppKit
import Combine
#endif

/// 宽屏与窄屏的**唯一判定入口**，由 RootView 往下传。
///
/// 宽屏 = iPad 全屏 / 宽分屏、Mac、Vision Pro：侧栏 + 看板（RegularHomeView）。
/// 窄屏 = iPhone（含 Pro Max 横屏，那时尺寸类也会变成 regular）和 iPad 窄分屏：
/// 原来的分页 TabView，一个像素都不动 —— App Store 的预览视频就是这套布局录的。
struct WideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }
}

extension View {
    /// 时代底色。iPhone / iPad / Mac 铺整页渐变（与原来逐字相同）；
    /// visionOS 不铺 —— 窗口本身是玻璃，盖一层不透明渐变就把它变成了一块平板，
    /// 时代色在那边只做强调色（tint / accent）。
    @ViewBuilder
    func eraBackdrop(_ era: Era) -> some View {
        #if os(visionOS)
        self
        #else
        self.background(era.background.ignoresSafeArea())
        #endif
    }

    /// 自己画了卡片 / 胶囊底的按钮：Mac 默认按钮样式会在外面再套一层灰色凸边，Vision Pro 会再垫一块玻璃底，
    /// 所以那两处改用 plain（Vision 补上注视高亮）。iPhone / iPad 原样不动。
    @ViewBuilder
    func flatButton() -> some View {
        #if os(macOS)
        self.buttonStyle(.plain)
        #elseif os(visionOS)
        self.buttonStyle(.plain).hoverEffect()
        #else
        self
        #endif
    }

    /// 宽屏时给一个最小高度；窄屏传 nil，原样返回（不留一层空 frame）。
    @ViewBuilder
    func minHeight(_ height: CGFloat?) -> some View {
        if let height {
            self.frame(minHeight: height)
        } else {
            self
        }
    }

    /// 宽屏时把内容收在 `width` 以内并居中；窄屏传 nil，原样返回。
    @ViewBuilder
    func contentWidth(_ width: CGFloat?) -> some View {
        if let width {
            self.frame(maxWidth: width).frame(maxWidth: .infinity)
        } else {
            self
        }
    }
}

#if os(macOS)
/// Mac 上家长会话的「无操作自动上锁」。
///
/// iPhone 靠「切后台超过 10 分钟」上锁（ParentSession.scenePhaseChanged），可 Mac 的窗口
/// 晾在桌面上时 scenePhase 可能一直是 active —— 家长解锁完走开，那把锁就永远不落。
/// 所以 Mac 另数「多久没碰这个 app」：本 app 收到的键盘、鼠标点击与滚动都算一次活动，
/// 每 30 秒看一眼，超过同样的 10 分钟就上锁。别的 app 在前台时本 app 收不到事件，时间照样累计。
struct MacIdleLock: ViewModifier {
    @EnvironmentObject var session: ParentSession
    @State private var monitor: Any?
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                let s = session          // 拿住对象本身，别让闭包去读 @EnvironmentObject 的包装
                monitor = NSEvent.addLocalMonitorForEvents(
                    matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
                ) { event in
                    MainActor.assumeIsolated { s.noteActivity() }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
            .onReceive(tick) { now in session.expireIfIdle(at: now) }
    }
}
#endif
