import SwiftUI

/// 五个视觉时代的配色。
///
/// ⚠ **这里没有、也不许有阈值。** 「多少分算哪一档」的 SSOT 是
/// `~/Edu/points/skins/skins.json` 的 `tiers`，由 server.py 读、随 `/api/state` 的
/// `house.era` 下发。本文件只负责「拿到 era 之后长什么样」——
/// 视觉是端上的事，档位不是。写第二份阈值表就意味着加一档要改两处。
enum Era: String, CaseIterable {
    case slum, cottage, garden, manor, golden

    init(key: String) { self = Era(rawValue: key) ?? .slum }

    /// 金融 App 的高级感 + 儿童奖励的暖 —— 越往上越亮、越贵气，但始终不用高饱和原色
    /// (那是廉价儿童 app 的观感，不是我们要的)。
    var colors: [Color] {
        switch self {
        case .slum:    return [Color(hex: 0x2B2A33), Color(hex: 0x4A4453)]
        case .cottage: return [Color(hex: 0x2E4034), Color(hex: 0x5B7C63)]
        case .garden:  return [Color(hex: 0x1F4B57), Color(hex: 0x3E8E9C)]
        case .manor:   return [Color(hex: 0x2A2A5C), Color(hex: 0x5B4B9E)]
        case .golden:  return [Color(hex: 0x6B4A12), Color(hex: 0xC9962C)]
        }
    }

    var background: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 市值大字与进度条的高亮色 —— 与背景同族但更亮，保证在自家渐变上够对比。
    var accent: Color {
        switch self {
        case .slum:    return Color(hex: 0xB9B3C7)
        case .cottage: return Color(hex: 0xA8D8B0)
        case .garden:  return Color(hex: 0x8FE3F0)
        case .manor:   return Color(hex: 0xC0B2FF)
        case .golden:  return Color(hex: 0xFFE9A8)
        }
    }
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
