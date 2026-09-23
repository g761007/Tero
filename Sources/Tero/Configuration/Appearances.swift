import UIKit

// Appearance 型別為 Swift-only 的值型別（見計畫書 §3、§21）：
// 值語義省去 NSCopying，也不會被別名修改。

/// 選取外框的顯示時機。
///
/// 這個型別只出現在 Swift-only 的 appearance 中，因此不標 `@objc`——
/// 標了也只是在 generated header 裡多一個永遠碰不到的符號。
public enum TeroTabSelectionIndicatorStyle {
    /// FloatingGlass 顯示、Classic 不顯示。原生的貼底 tab bar 沒有這個外框。
    case automatic
    case always
    case never
}

/// 選取外框的材質。
///
/// 與 `TeroTabSelectionIndicatorStyle` 一樣只出現在 Swift-only 的 appearance 中。
public enum TeroTabSelectionIndicatorMaterial {
    /// 靜止時實色；iOS 26 FloatingGlass 移動時另顯示透鏡。
    case automatic
    /// 一律使用系統玻璃。iOS 26 以下、或開啟「降低透明度」時退回實色。
    /// 移動中同樣顯示透鏡。
    case glass
    /// 一律使用 `selectionIndicatorColor` 的實色，**移動中也不顯示透鏡**。
    ///
    /// 這是唯一能表達「這個 App 不要玻璃」的值，所以它連動態的那一片也關掉。
    case solid
}

/// 兩種 Style 共用。
public struct TeroTabItemAppearance {
    public var normalTintColor: UIColor = .secondaryLabel
    public var selectedTintColor: UIColor = .tintColor
    public var titleFont: UIFont = .systemFont(ofSize: 10, weight: .medium)
    public var selectedTitleFont: UIFont = .systemFont(ofSize: 10, weight: .semibold)
    public var contentSize: CGSize = CGSize(width: 28, height: 28)
    public var titleSpacing: CGFloat = 4

    /// 襯在選取項目底下的圓角外框。
    public var selectionIndicatorStyle: TeroTabSelectionIndicatorStyle = .automatic
    /// 選取外框的材質。
    public var selectionIndicatorMaterial: TeroTabSelectionIndicatorMaterial = .automatic
    /// **實色材質**的顏色。玻璃材質的外觀由系統決定，不吃這個值。
    ///
    /// 預設是比玻璃**亮**一階，兩種明暗模式下都成立——
    /// 深色模式下淡白會浮出來，淺色模式下需要更高的不透明度才看得見。
    public var selectionIndicatorColor: UIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.16)
            : UIColor.white.withAlphaComponent(0.55)
    }
    /// **玻璃材質**的 tint。
    ///
    /// 與 `selectionIndicatorColor` 分成兩個值是實測的結果，不是偏好問題：
    /// 玻璃的 tint 會被宿主材質吸收，淺色模式下若底下又是淺色內容，
    /// 白色 tint 不論調到多高的不透明度都浮不出來——白疊白沒有對比可言。
    /// 因此淺色模式改用中性偏暗的 tint，深色模式才用白。
    ///
    /// 想要兩種材質同色的話，把這個值設成與 `selectionIndicatorColor` 相同即可。
    public var selectionIndicatorGlassTint: UIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.22)
            : UIColor.systemGray.withAlphaComponent(0.28)
    }
    public var selectionIndicatorInsets: UIEdgeInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
    /// `nil` 代表膠囊（取高度的一半）。
    public var selectionIndicatorCornerRadius: CGFloat?

    /// 接手選取的內容在轉場起點的縮放。1.0 代表不縮放。
    ///
    /// 交出選取的那一格會以同樣的幅度反向起伏（原地略縮再回復），
    /// 兩端都固定收在 1.0。
    public var selectionIconScale: CGFloat = 0.92
    /// 轉場中途的額外過衝。0 代表不過衝。
    public var selectionIconOvershoot: CGFloat = 0.09

    public init() {}
}

/// 兩種 Style 共用的 Badge 預設值。單一 Badge 已指定的屬性優先於此。
public struct TeroTabBadgeAppearance {
    public var backgroundColor: UIColor = .systemRed
    public var textColor: UIColor = .white
    public var font: UIFont = .systemFont(ofSize: 11, weight: .semibold)
    /// `.value` 樣式的最小尺寸。
    public var minimumSize: CGSize = CGSize(width: 18, height: 18)
    /// `.dot` 樣式的直徑。
    public var dotSize: CGSize = CGSize(width: 8, height: 8)
    public var contentInsets: UIEdgeInsets = UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5)
    public var offset: CGPoint = .zero

    public init() {}
}

public struct TeroClassicTabBarAppearance {
    /// 不含 home indicator 安全區。
    public var barHeight: CGFloat = 49
    public var contentInsets: UIEdgeInsets = .zero
    public var backgroundColor: UIColor = .systemBackground
    public var usesBlurEffect: Bool = true
    public var blurEffectStyle: UIBlurEffect.Style = .systemChromeMaterial
    public var separatorColor: UIColor? = .separator
    /// 中央 Action slot 的尺寸（見 ADR-0003）。
    public var actionSize: CGSize = CGSize(width: 44, height: 44)

    public init() {}
}

public struct TeroFloatingGlassAppearance {
    public var expandedHeight: CGFloat = 56
    public var minimizedHeight: CGFloat = 36
    public var horizontalInset: CGFloat = 16
    /// 膠囊底邊距**螢幕邊緣**的距離，與 `horizontalInset` 同一個基準。
    ///
    /// 不是疊在安全區之上：系統原生的浮動 Tab Bar 刻意讓膠囊落在 home indicator 那條帶子
    /// 裡面，預設的 21 就是照著它量的。
    public var bottomInset: CGFloat = 21
    public var actionSpacing: CGFloat = 8
    public var actionSize: CGSize = CGSize(width: 56, height: 56)
    /// 對應 `UIGlassContainerEffect.spacing`：Tabs Glass 與 Action Glass 開始融合的距離。
    public var glassContainerSpacing: CGFloat = 12
    public var cornerRadius: CGFloat = 28
    public var minimizedCornerRadius: CGFloat = 18
    public var hidesTitlesWhenMinimized: Bool = true
    /// 最小化的版面：整條等比縮小（預設），或只留選取格成一顆小膠囊。
    ///
    /// `.selectedOnly` 的膠囊寬度取選取格等比縮放後的寬，夾在 `minimizedHeight` 的 1…1.6 倍
    /// 之間；非選取格隨進度淡出到摸不到。那顆膠囊上只有一格，點它是展開不是重選，
    /// `.drag` 在這個狀態下也不動。
    public var minimizedLayout: TeroTabMinimizedLayout = .uniform
    public var glassTintMode: TeroTabGlassTintMode = .automatic
    public var glassTintColor: UIColor?

    public init() {}
}

public struct TeroTabScrollConfiguration {
    public var behavior: TeroTabBarScrollBehavior = .none
    public var downwardTranslationThreshold: CGFloat = 40
    public var upwardTranslationThreshold: CGFloat = 24
    /// 方向改變至少累積此距離；負值視為 0，非有限值回退為 8。
    public var directionLockDistance: CGFloat = 8
    public var velocityThreshold: CGFloat = 120

    public init() {}
}
