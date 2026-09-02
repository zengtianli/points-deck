import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 「乔迁新居」—— 升档时的庆祝。
///
/// 这是原生相对网页真正拿得到的东西之一：CSS 换个 class 和一次带触感的转场，
/// 观感差一个量级。**只庆不罚** —— 回落不弹（~/Edu 的规矩）。
struct CelebrationView: View {
    let houseName: String
    let era: Era
    var onDone: () -> Void

    @State private var shown = false
    @State private var confetti: [Confetto] = []

    struct Confetto: Identifiable {
        let id = UUID()
        let x: Double, delay: Double, size: Double, hue: Double, spin: Double
    }

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.55 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }

            GeometryReader { geo in
                ForEach(confetti) { c in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hue: c.hue, saturation: 0.55, brightness: 0.95))
                        .frame(width: c.size, height: c.size * 1.6)
                        .rotationEffect(.degrees(shown ? c.spin : 0))
                        .position(x: c.x * geo.size.width,
                                  y: shown ? geo.size.height + 40 : -40)
                        .animation(.easeIn(duration: 2.2).delay(c.delay), value: shown)
                }
            }
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                Text("🏠").font(.system(size: 64))
                Text("乔迁新居").font(.title2.weight(.bold)).foregroundStyle(.white)
                Text("搬进「\(houseName)」了")
                    .font(.headline).foregroundStyle(era.accent)
                Button("知道啦") { close() }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(era.accent, in: Capsule())
                    .foregroundStyle(.black)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 36).padding(.vertical, 34)
            .background(era.background, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(era.accent.opacity(0.6), lineWidth: 1))
            .scaleEffect(shown ? 1 : 0.7)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            confetti = (0..<26).map { _ in
                Confetto(x: .random(in: 0.05...0.95), delay: .random(in: 0...0.5),
                         size: .random(in: 6...12), hue: .random(in: 0...1),
                         spin: .random(in: 180...900))
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { shown = true }
            // 升档是这个 app 里最值得让人感觉到的一下 —— 用 success 而不是普通 impact
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.25)) { shown = false }
        Task {
            try? await Task.sleep(for: .seconds(0.25))
            onDone()
        }
    }
}
