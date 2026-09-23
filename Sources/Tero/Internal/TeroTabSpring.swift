import UIKit

/// 彈簧參數的換算。Consumer 不應依賴此型別（計畫書 §52）。
///
/// 與捲動狀態機同樣的處理：把換算抽成純運算，讓它能被單獨驗證，
/// 不必真的跑一次動畫再去量結果。
internal enum TeroTabSpring {

    /// 質量、勁度與阻尼。對應 `UISpringTimingParameters` 的物理參數。
    internal struct Description: Equatable {
        internal var mass: CGFloat
        internal var stiffness: CGFloat
        internal var damping: CGFloat
    }

    /// 允許的回應時間下限。0 會讓角頻率發散。
    internal static let minimumResponse: TimeInterval = 0.01
    /// 阻尼比的合理範圍。上界留給過阻尼（完全不回彈但仍平滑）。
    internal static let dampingRatioRange: ClosedRange<CGFloat> = 0.1...2.0

    /// 以 SwiftUI `.spring(response:dampingFraction:)` 的參數化換算物理參數。
    ///
    /// 角頻率 `ω = 2π / response`，質量固定為 1：
    /// `stiffness = m·ω²`、`damping = 2·ζ·m·ω`。
    internal static func description(
        response: TimeInterval,
        dampingRatio: CGFloat,
        mass: CGFloat = 1
    ) -> Description {
        let response = max(response, minimumResponse)
        let ratio = min(max(dampingRatio, dampingRatioRange.lowerBound), dampingRatioRange.upperBound)
        let omega = 2 * CGFloat.pi / CGFloat(response)
        return Description(
            mass: mass,
            stiffness: mass * omega * omega,
            damping: 2 * ratio * mass * omega
        )
    }

    /// 依設定產生動畫器的 timing。`selectionResponse` 為 nil 時退回固定時長的彈簧。
    internal static func timingParameters(
        for motion: TeroTabMotionConfiguration,
        initialVelocity: CGVector = .zero
    ) -> UISpringTimingParameters {
        guard let response = motion.selectionResponse else {
            let ratio = min(
                max(motion.selectionDampingRatio, dampingRatioRange.lowerBound),
                dampingRatioRange.upperBound
            )
            return UISpringTimingParameters(dampingRatio: ratio, initialVelocity: initialVelocity)
        }
        let spring = description(response: response, dampingRatio: motion.selectionDampingRatio)
        return UISpringTimingParameters(
            mass: spring.mass,
            stiffness: spring.stiffness,
            damping: spring.damping,
            initialVelocity: initialVelocity
        )
    }

    /// 動畫器的名目時長。用了物理參數時它會被 UIKit 忽略，但仍需給一個合理值。
    internal static func nominalDuration(for motion: TeroTabMotionConfiguration) -> TimeInterval {
        motion.selectionResponse ?? motion.selectionDuration
    }
}
