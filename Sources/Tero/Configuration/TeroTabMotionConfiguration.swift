import UIKit

/// 開啟「減少動態效果」時，選取轉場的降級方式。
///
/// 兩種都保留選取狀態本身——降級的是位移，不是「看不看得出哪個 Tab 被選取」。
@objc public enum TeroTabReduceMotionBehavior: Int {
    /// 選取膠囊直接出現在目標位置，並以短距離的淡入淡出交棒。
    case crossFade
    /// 完全不做動畫，直接換狀態。
    case instant
}

/// 選取轉場的動態參數。
///
/// 與其他 appearance 一樣是 Swift-only 的值型別（計畫書 §3）：值語義省去 NSCopying，
/// 也不會被別名修改。
public struct TeroTabMotionConfiguration {

    /// 彈簧的回應時間，對應 SwiftUI `.spring(response:dampingFraction:)` 的 `response`。
    ///
    /// 設為 `nil` 時改用 `selectionDuration` + `selectionDampingRatio` 的固定時長彈簧。
    /// 兩者不能同時生效：`UISpringTimingParameters` 只要給了 mass/stiffness/damping
    /// 就會自行推導時長，`duration` 會被忽略。
    public var selectionResponse: TimeInterval? = 0.4

    /// `selectionResponse` 為 `nil` 時才生效的固定時長。
    public var selectionDuration: TimeInterval = 0.4

    /// 阻尼比。1.0 為臨界阻尼（不回彈），越小回彈越明顯。
    public var selectionDampingRatio: CGFloat = 0.84

    /// 選取膠囊移動時的橫向拉伸量，以**位移距離**的比例表示。0 代表不拉伸。
    ///
    /// 起點與終點都不拉伸，中途最寬。這不只是裝飾：透鏡的變形集中在鏡緣，
    /// 膠囊只有一格寬時 Icon 會整個落在變形帶裡而糊掉，拉長之後才落在平坦的中央。
    public var selectionStretch: CGFloat = 0.5

    /// 收合與恢復的時長；負值視為 0，非有限值回退為 0.28 秒。
    public var minimizeDuration: TimeInterval = 0.28
    public var restoreDuration: TimeInterval = 0.22

    /// 點擊已選取的 Tab 時，回饋動畫的長度。
    public var reselectDuration: TimeInterval = 0.28

    /// Icon 與自訂內容交棒的長度。
    public var contentTransitionDuration: TimeInterval = 0.3

    /// 轉場進行中收到新的選取請求時，是否從目前位置直接轉向。
    ///
    /// 設為 `false` 會退回「先讓目前這段跑完」的行為。
    public var allowsInterruptibleTransition: Bool = true

    public var reduceMotionBehavior: TeroTabReduceMotionBehavior = .crossFade

    public init() {}
}
