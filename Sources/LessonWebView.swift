import SwiftUI
import WebKit

/// 练习引擎的承载层 —— **不重写 practice.js，原样跑它**。
///
/// `~/Edu/engine/practice.js` 1271 行里装着判题 verify()、组卷权重 nextGen()、
/// 错题本两层结构、勋章判定 PRED、上瘾机制五件套；题库是**内联进每个 HTML** 的。
/// 用 SwiftUI 重写 = 第二份判题逻辑，和 bank.db / badges.json 必然漂移，
/// 而 ~/Edu 那些硬约束（「改了 badges.json 必须全量重渲」「页面内联题数必须等于库里的数」）
/// 在 Swift 侧根本继承不了。
///
/// ## 为什么用 loadSimulatedRequest 而不是 loadFileURL
///
/// 页面是**完全自包含**的（JS/CSS/题库全内联，零 CDN —— ~/Edu 的既定设计），
/// 唯一的外部依赖是三个相对请求：`/api/state` `/api/practice` `/api/archive`，
/// 由内联的 `points_client.js` 自己发。
///
/// 用 `file://` 载入的话：① `points_client.js` 第一行就 `return`（它只在 http(s) 下工作）
/// ② 相对 URL 会解析成 `file:///api/state`。于是得分和存档同步全断，
/// **而且不报错** —— 页面照常能做题，只是分永远不涨。
///
/// `loadSimulatedRequest` 把 bundle 里的 HTML 挂在真实的 `https://edu.tianli.cyou/<路径>` 源上：
/// 页面内容离线来自包里，相对请求走真网络。没网时 `points_client.js` 自己 catch 掉
/// （它本来就 fail-soft），做题完全不受影响 —— 这正是想要的降级。
///
/// **所以这里没有「桥」**：得分、存档同步都是网页自己干的，原样。
/// 唯一一条 Swift→JS 之外的消息是 `submitted`（交卷了），只为让原生刷新一次余额。
/// 每加一条消息就是一处「原生和网页各存一份状态」的机会 —— 加之前先问
/// 「这件事能不能在网页里自己完成」，能就不加。
struct LessonWebView: UIViewRepresentable {
    let lesson: Lesson
    /// 交卷后回调（引擎算完这一套的对错之后）。原生借此刷新余额 / 触发庆祝。
    var onSubmitted: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onSubmitted: onSubmitted) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "edu")
        ucc.addUserScript(WKUserScript(source: Self.probe,
                                       injectionTime: .atDocumentEnd,
                                       forMainFrameOnly: true))
        cfg.userContentController = ucc
        // 做题要发声（practice.js 用 WebAudio 合成音效），别要求全屏手势
        cfg.allowsInlineMediaPlayback = true

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.contentInsetAdjustmentBehavior = .always
        context.coordinator.load(into: wv, lesson: lesson)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.onSubmitted = onSubmitted
        context.coordinator.load(into: wv, lesson: lesson)   // 换课才重载，内部按 slug 去重
    }

    /// 注入的探针：只报告「交卷了」，不改引擎任何行为。
    ///
    /// 和 `points_client.js` 同一种接法 —— document 上的**捕获**监听。
    /// 绑在按钮上会失效：引擎重绘题卡时按钮整个被换掉。
    private static let probe = """
    (function () {
      document.addEventListener('click', function (e) {
        var t = e.target;
        if (!t || t.id !== 'submitSet') return;
        setTimeout(function () {
          try {
            var rows = document.querySelectorAll('#review .rrow').length;
            var ok = document.querySelectorAll('#review .mk.ok').length;
            if (!rows) return;
            window.webkit.messageHandlers.edu.postMessage({ k: 'submitted', rows: rows, ok: ok });
          } catch (err) {}
        }, 1200);   // 比 points_client 的 600ms 晚，让它先把这笔分记上去
      }, true);
    })();
    """

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onSubmitted: () -> Void
        private var loadedSlug: String?

        init(onSubmitted: @escaping () -> Void) { self.onSubmitted = onSubmitted }

        func load(into wv: WKWebView, lesson: Lesson) {
            guard loadedSlug != lesson.slug else { return }
            guard let u = lesson.bundleURL,
                  let html = try? String(contentsOf: u, encoding: .utf8) else {
                // 静默白屏是最难查的一种 —— 明说是哪一课、缺在哪
                let msg = "这一课的页面没在包里：\(lesson.file)\n重新构建会自动同步（sync-lessons.sh）"
                wv.loadHTMLString(
                    "<meta name=viewport content='width=device-width,initial-scale=1'>"
                    + "<pre style='padding:24px;font:15px/1.7 -apple-system;white-space:pre-wrap'>"
                    + msg + "</pre>", baseURL: nil)
                loadedSlug = lesson.slug
                return
            }
            loadedSlug = lesson.slug
            // origin 必须是账本那台机器：页面里的 /api/* 是相对路径，靠它解析。
            // Api.base 可被 launch 参数指向本地 server（验证用），这里跟着它走。
            let url = Api.base.appendingPathComponent(lesson.file)
            wv.loadSimulatedRequest(URLRequest(url: url), responseHTML: html)
        }

        func userContentController(_ c: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let d = message.body as? [String: Any],
                  d["k"] as? String == "submitted" else { return }
            onSubmitted()
        }
    }
}

/// 把 URLSession 的登录 cookie 借给 WebView。
///
/// 两边各有一套 cookie 存储：原生请求用 `URLSession.shared`（HttpOnly 会话就在那），
/// WebView 用 `WKWebsiteDataStore`。不搬的话表现是：**app 里已登录，网页里没登录** ——
/// 页面照常能做题，只是积分徽章不出现、分不涨、存档不同步，**一句报错都没有**。
enum WebSession {
    static func handOff() async {
        guard let host = Api.base.host,
              let cookies = HTTPCookieStorage.shared.cookies(for: Api.base) else { return }
        let store = WKWebsiteDataStore.default().httpCookieStore
        for c in cookies where c.domain.contains(host) || host.contains(c.domain.dropFirst(c.domain.hasPrefix(".") ? 1 : 0)) {
            await store.setCookie(c)
        }
    }
}
