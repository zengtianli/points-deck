import SwiftUI

/// `-palette 1` 的验证页：把五个时代的**插画 + 从它派生出来的整页配色**并排画出来。
///
/// 为什么要有：配色现在是从图里采样算出来的，不是写死的 —— 算法对不对，
/// 只能看五张一起看。一档一档跑要编译五次，而且没法比较。
struct PalettePreview: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("五个时代的派生配色")
                    .font(.headline).foregroundStyle(.white)
                ForEach(Era.allCases, id: \.self) { era in
                    VStack(spacing: 0) {
                        if let img = era.banner {
                            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
                                .frame(height: 62).clipped()
                        }
                        ZStack {
                            era.background
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name(era)).font(.headline).foregroundStyle(.white)
                                    Text("2,500 分").font(.subheadline.weight(.bold))
                                        .monospacedDigit().foregroundStyle(era.accent)
                                }
                                Spacer()
                                Capsule().fill(era.accent).frame(width: 60, height: 8)
                            }
                            .padding(.horizontal, 16)
                        }
                        .frame(height: 58)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
    }

    /// 时代中文名 —— 与 skins.json 的 eras[].name 一致
    private func name(_ e: Era) -> String {
        switch e {
        case .slum: return "贫民窟"
        case .cottage: return "普通人家"
        case .garden: return "小康之家"
        case .manor: return "豪宅"
        case .golden: return "金碧辉煌"
        }
    }
}
