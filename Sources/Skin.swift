import SwiftUI
import UIKit

/// 五个视觉时代的配色。
///
/// ⚠ **这里没有、也不许有阈值。** 「多少分算哪一档」的 SSOT 是
/// `~/Edu/points/skins/skins.json` 的 `tiers`，由 server.py 读、随 `/api/state` 的
/// `house.era` 下发。本文件只负责「拿到 era 之后长什么样」——
/// 视觉是端上的事，档位不是。写第二份阈值表就意味着加一档要改两处。
enum Era: String, CaseIterable {
    case slum, cottage, garden, manor, golden

    init(key: String) { self = Era(rawValue: key) ?? .slum }

    /// 兜底配色 —— **只在底图读不到时用**（fail-soft）。
    /// 正常路径下整页配色是从 `banner` 那张插画里采样派生的，见 `palette`：
    /// 「背景要跟着木屋的背景变」（2026-08-28 用户钦定），写死一套绿的等于图白配了。
    var fallbackColors: [Color] {
        switch self {
        case .slum:    return [Color(hex: 0x2B2A33), Color(hex: 0x4A4453)]
        case .cottage: return [Color(hex: 0x3A2E22), Color(hex: 0x5C4630)]
        case .garden:  return [Color(hex: 0x1F4B57), Color(hex: 0x3E8E9C)]
        case .manor:   return [Color(hex: 0x2A2A5C), Color(hex: 0x5B4B9E)]
        case .golden:  return [Color(hex: 0x6B4A12), Color(hex: 0xC9962C)]
        }
    }

    var colors: [Color] { [palette.top, palette.bottom] }

    var background: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 整页配色 —— **从这个时代的插画里采样派生**，不是写死的。
    ///
    /// 天空色取图的上三分之一、地面色取下三分之一，各自压暗到能压住白字为止
    /// （原图天空是米白，直接拿来当背景，白字就没了）。
    /// accent 取地面色的色相再提亮，保证它跟背景同族但够跳。
    ///
    /// 算一次缓存一次：一张图缩到 24×24 再平均，开销可忽略，但没必要每帧都做。
    var palette: Palette {
        if let hit = Era.cache[rawValue] { return hit }
        let p = Era.derive(from: banner) ?? Palette(top: fallbackColors[0],
                                                    bottom: fallbackColors[1],
                                                    accent: fallbackAccent)
        Era.cache[rawValue] = p
        return p
    }

    struct Palette {
        let top: Color, bottom: Color, accent: Color
    }

    private static var cache: [String: Palette] = [:]

    private static func derive(from image: UIImage?) -> Palette? {
        guard let cg = image?.cgImage else { return nil }
        let w = 24, h = 24
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        func avg(rows: Range<Int>) -> (Double, Double, Double) {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for y in rows {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    r += Double(buf[i]); g += Double(buf[i + 1]); b += Double(buf[i + 2]); n += 1
                }
            }
            return n == 0 ? (0, 0, 0) : (r / n / 255, g / n / 255, b / n / 255)
        }

        let sky = avg(rows: 0..<(h / 3))
        let ground = avg(rows: (h * 2 / 3)..<h)
        return Palette(top: shade(sky, brightness: 0.20, saturation: 0.55),
                       bottom: shade(ground, brightness: 0.34, saturation: 0.60),
                       accent: shade(ground, brightness: 0.88, saturation: 0.45))
    }

    /// 把采样色钳到指定明度/饱和 —— 保住「白字读得清」这条底线，
    /// 同时留住原图的色相（那才是「跟着木屋变」的那部分）。
    private static func shade(_ rgb: (Double, Double, Double),
                              brightness: Double, saturation: Double) -> Color {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
            .getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        // 原图接近灰(如贫民窟的阴天)时别硬加饱和，那会凭空造出一个颜色
        let s = min(saturation, max(0.10, Double(sat) * 1.4))
        return Color(hue: Double(hue), saturation: s, brightness: brightness)
    }

    private var fallbackAccent: Color {
        switch self {
        case .slum:    return Color(hex: 0xB9B3C7)
        case .cottage: return Color(hex: 0xE8C79A)
        case .garden:  return Color(hex: 0x8FE3F0)
        case .manor:   return Color(hex: 0xC0B2FF)
        case .golden:  return Color(hex: 0xFFE9A8)
        }
    }

    /// 这个时代的天际线底图（`Resources/Skins/<era>.jpg`，由 sync-skins.sh 从
    /// ~/Edu/points/skins/ 同步而来，是 Seedream 离线生成的资产、不是运行时生图）。
    ///
    /// 取不到就返回 nil，界面退回纯色主题 —— **fail-soft 是有意的**：
    /// 底图是锦上添花，缺一张不该让整个账本打不开。
    var banner: UIImage? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "jpg",
                                        subdirectory: "Skins")
                ?? Bundle.main.url(forResource: rawValue, withExtension: "jpg") else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// 市值大字与进度条的高亮色 —— 同样从插画派生。
    var accent: Color { palette.accent }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// 数字滚动 —— 市值不是「刷新一下换个数」，是滚上去的。
struct RollingNumber: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(Self.grouped(Int(value.rounded())))
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
