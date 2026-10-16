import SwiftUI

/// 三点脉冲：等待解析 / 等待生成时的进度指示。
///
/// 用相位错开的三个点，而不是扫光或流光 —— 后者是装饰，而且每秒要重绘整块区域。
/// 相位由时间直接算出而不是靠 `Timer` + `withAnimation`：后者在没有视图时也会继续跑。
struct PulsingDots: View {

    /// nil 时继承按钮前景，禁用/加载状态不再固定使用白色。
    var tint: Color? = Theme.tertiaryLabel
    var dotSize: CGFloat = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: Double = 0.35
    private static let count = 3

    var body: some View {
        if reduceMotion {
            // 减弱动态效果：三个点常亮，不再轮转
            dots(active: -1)
        } else {
            TimelineView(.periodic(from: .now, by: Self.period)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / Self.period)
                dots(active: step % Self.count)
            }
        }
    }

    private func dots(active: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<Self.count, id: \.self) { index in
                Circle()
                    .fill(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground))
                    .frame(width: dotSize, height: dotSize)
                    .opacity(active == -1 || active == index ? 1 : 0.3)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        PulsingDots()
        HStack(spacing: 8) {
            PulsingDots()
            Text("正在理解…").font(Theme.Font.footnote).foregroundStyle(Theme.secondaryLabel)
        }
    }
    .padding()
}
