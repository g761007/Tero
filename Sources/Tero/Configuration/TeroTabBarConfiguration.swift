import UIKit

/// Tab Bar 的完整設定。
///
/// Controller 於初始化與套用時各做一次深拷貝，因此建立 controller 之後修改這份物件不會影響它。
///
/// 標註策略依型別分類，不是全套件一致：**有非公開實作面、或公開方法需要釘 selector 的型別**
/// （本類、`TeroTabBarController`、`TeroTabBar`）逐一標註 `@objc`；**純資料型別**
/// （`TeroTab`、`TeroTabItem`、`TeroTabBadge`、`TeroTabActionItem`、`TeroTabMoreItem`、
/// `TeroTabLayoutConfiguration`）維持 `@objcMembers`。
///
/// 逐一標註付出樣板，換到的是「不可表示的成員會編譯失敗」而不是被靜默略過
/// （見 `docs/spikes/0001-objc-interop.md`）；資料型別沒有不可表示的成員，也不需要釘 selector，
/// 所以不付這個代價。`@objcMembers` 也不產生 `@objc(...)` 的自訂 selector。
public final class TeroTabBarConfiguration: NSObject, NSCopying {

    @objc public var style: TeroTabBarStyle = .classic

    @objc public let compact: TeroTabLayoutConfiguration
    @objc public let regular: TeroTabLayoutConfiguration

    // Swift-only
    public var itemAppearance = TeroTabItemAppearance()
    public var badgeAppearance = TeroTabBadgeAppearance()
    public var classicAppearance = TeroClassicTabBarAppearance()
    public var floatingGlassAppearance = TeroFloatingGlassAppearance()
    public var scrollConfiguration = TeroTabScrollConfiguration()
    /// 選取轉場的動態參數。
    public var motion = TeroTabMotionConfiguration()

    /// 滑動選取的操作方式。預設關閉。
    @objc public var swipeSelectionMode: TeroTabSwipeSelectionMode = .disabled

    @objc public var morePresentationStyle: TeroTabMorePresentationStyle = .automatic
    @objc public var moreItem: TeroTabMoreItem

    /// Objective-C 便捷代理，轉發至 `itemAppearance`。
    @objc public var normalTintColor: UIColor {
        get { itemAppearance.normalTintColor }
        set { itemAppearance.normalTintColor = newValue }
    }

    /// Objective-C 便捷代理，轉發至 `itemAppearance`。
    @objc public var selectedTintColor: UIColor {
        get { itemAppearance.selectedTintColor }
        set { itemAppearance.selectedTintColor = newValue }
    }

    // MARK: - Objective-C 便捷代理：motion
    //
    // `motion` 是 Swift-only 值型別，Objective-C 拿不到它（見 ADR 與計畫書 §34）。
    // 以下十個轉發屬性讓兩邊的旋鈕對等，而不必把六個 appearance 值型別全改成 class。
    // 名稱一律帶 `motion` 前綴：讓「facade 只覆蓋 motion」這條範圍規則在產生的
    // Objective-C 介面上自我說明，也避開日後與 appearance 同名成員相撞。

    /// 轉發至 `motion.selectionResponse`。`0` 代表未指定，改用 duration + damping
    /// （與 `TeroTabItem` 以 `.zero` 表示「未指定」是同一種處理）。
    @objc public var motionSelectionResponse: TimeInterval {
        get { motion.selectionResponse ?? 0 }
        set { motion.selectionResponse = newValue == 0 ? nil : newValue }
    }

    /// 轉發至 `motion.selectionDuration`。
    @objc public var motionSelectionDuration: TimeInterval {
        get { motion.selectionDuration }
        set { motion.selectionDuration = newValue }
    }

    /// 轉發至 `motion.selectionDampingRatio`。
    @objc public var motionSelectionDampingRatio: CGFloat {
        get { motion.selectionDampingRatio }
        set { motion.selectionDampingRatio = newValue }
    }

    /// 轉發至 `motion.selectionStretch`。
    @objc public var motionSelectionStretch: CGFloat {
        get { motion.selectionStretch }
        set { motion.selectionStretch = newValue }
    }

    /// 轉發至 `motion.minimizeDuration`。
    @objc public var motionMinimizeDuration: TimeInterval {
        get { motion.minimizeDuration }
        set { motion.minimizeDuration = newValue }
    }

    /// 轉發至 `motion.restoreDuration`。
    @objc public var motionRestoreDuration: TimeInterval {
        get { motion.restoreDuration }
        set { motion.restoreDuration = newValue }
    }

    /// 轉發至 `motion.reselectDuration`。
    @objc public var motionReselectDuration: TimeInterval {
        get { motion.reselectDuration }
        set { motion.reselectDuration = newValue }
    }

    /// 轉發至 `motion.contentTransitionDuration`。
    @objc public var motionContentTransitionDuration: TimeInterval {
        get { motion.contentTransitionDuration }
        set { motion.contentTransitionDuration = newValue }
    }

    /// 轉發至 `motion.allowsInterruptibleTransition`。
    @objc public var motionAllowsInterruptibleTransition: Bool {
        get { motion.allowsInterruptibleTransition }
        set { motion.allowsInterruptibleTransition = newValue }
    }

    /// 轉發至 `motion.reduceMotionBehavior`。
    @objc public var motionReduceMotionBehavior: TeroTabReduceMotionBehavior {
        get { motion.reduceMotionBehavior }
        set { motion.reduceMotionBehavior = newValue }
    }

    // MARK: - Objective-C 便捷代理：scrollConfiguration
    //
    // 與 motion 同一個做法、同一個理由：值型別不改成 class，改加逐欄位的轉發屬性。
    // 沒有這一組的話 Objective-C App 設不了捲動的預設行為與任何門檻，只能每一頁各自
    // 實作 `TeroTabBarScrollBehaviorProviding`。名稱一律帶 `scroll` 前綴。

    /// 轉發至 `scrollConfiguration.behavior`。
    @objc public var scrollBehavior: TeroTabBarScrollBehavior {
        get { scrollConfiguration.behavior }
        set { scrollConfiguration.behavior = newValue }
    }

    /// 轉發至 `scrollConfiguration.downwardTranslationThreshold`。
    @objc public var scrollDownwardTranslationThreshold: CGFloat {
        get { scrollConfiguration.downwardTranslationThreshold }
        set { scrollConfiguration.downwardTranslationThreshold = newValue }
    }

    /// 轉發至 `scrollConfiguration.upwardTranslationThreshold`。
    @objc public var scrollUpwardTranslationThreshold: CGFloat {
        get { scrollConfiguration.upwardTranslationThreshold }
        set { scrollConfiguration.upwardTranslationThreshold = newValue }
    }

    /// 轉發至 `scrollConfiguration.directionLockDistance`。
    @objc public var scrollDirectionLockDistance: CGFloat {
        get { scrollConfiguration.directionLockDistance }
        set { scrollConfiguration.directionLockDistance = newValue }
    }

    /// 轉發至 `scrollConfiguration.velocityThreshold`。
    @objc public var scrollVelocityThreshold: CGFloat {
        get { scrollConfiguration.velocityThreshold }
        set { scrollConfiguration.velocityThreshold = newValue }
    }

    // MARK: - Objective-C 便捷代理：classicAppearance
    //
    // 名稱一律帶 `classic` 前綴。

    /// 轉發至 `classicAppearance.barHeight`。
    @objc public var classicBarHeight: CGFloat {
        get { classicAppearance.barHeight }
        set { classicAppearance.barHeight = newValue }
    }

    /// 轉發至 `classicAppearance.contentInsets`。
    @objc public var classicContentInsets: UIEdgeInsets {
        get { classicAppearance.contentInsets }
        set { classicAppearance.contentInsets = newValue }
    }

    /// 轉發至 `classicAppearance.backgroundColor`。
    @objc public var classicBackgroundColor: UIColor {
        get { classicAppearance.backgroundColor }
        set { classicAppearance.backgroundColor = newValue }
    }

    /// 轉發至 `classicAppearance.usesBlurEffect`。
    @objc public var classicUsesBlurEffect: Bool {
        get { classicAppearance.usesBlurEffect }
        set { classicAppearance.usesBlurEffect = newValue }
    }

    /// 轉發至 `classicAppearance.blurEffectStyle`。
    @objc public var classicBlurEffectStyle: UIBlurEffect.Style {
        get { classicAppearance.blurEffectStyle }
        set { classicAppearance.blurEffectStyle = newValue }
    }

    /// 轉發至 `classicAppearance.separatorColor`。`nil` 代表不畫分隔線。
    @objc public var classicSeparatorColor: UIColor? {
        get { classicAppearance.separatorColor }
        set { classicAppearance.separatorColor = newValue }
    }

    /// 轉發至 `classicAppearance.actionSize`。
    @objc public var classicActionSize: CGSize {
        get { classicAppearance.actionSize }
        set { classicAppearance.actionSize = newValue }
    }

    // MARK: - Objective-C 便捷代理：floatingGlassAppearance
    //
    // 名稱一律帶 `floatingGlass` 前綴；`glassTintMode`／`glassTintColor`／
    // `glassContainerSpacing` 的 `glass` 併進前綴，不重複。

    /// 轉發至 `floatingGlassAppearance.expandedHeight`。
    @objc public var floatingGlassExpandedHeight: CGFloat {
        get { floatingGlassAppearance.expandedHeight }
        set { floatingGlassAppearance.expandedHeight = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.minimizedHeight`。
    @objc public var floatingGlassMinimizedHeight: CGFloat {
        get { floatingGlassAppearance.minimizedHeight }
        set { floatingGlassAppearance.minimizedHeight = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.horizontalInset`。
    @objc public var floatingGlassHorizontalInset: CGFloat {
        get { floatingGlassAppearance.horizontalInset }
        set { floatingGlassAppearance.horizontalInset = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.bottomInset`。從螢幕邊緣量起。
    @objc public var floatingGlassBottomInset: CGFloat {
        get { floatingGlassAppearance.bottomInset }
        set { floatingGlassAppearance.bottomInset = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.actionSpacing`。
    @objc public var floatingGlassActionSpacing: CGFloat {
        get { floatingGlassAppearance.actionSpacing }
        set { floatingGlassAppearance.actionSpacing = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.actionSize`。
    @objc public var floatingGlassActionSize: CGSize {
        get { floatingGlassAppearance.actionSize }
        set { floatingGlassAppearance.actionSize = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.glassContainerSpacing`。
    @objc public var floatingGlassContainerSpacing: CGFloat {
        get { floatingGlassAppearance.glassContainerSpacing }
        set { floatingGlassAppearance.glassContainerSpacing = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.cornerRadius`。
    @objc public var floatingGlassCornerRadius: CGFloat {
        get { floatingGlassAppearance.cornerRadius }
        set { floatingGlassAppearance.cornerRadius = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.minimizedCornerRadius`。
    @objc public var floatingGlassMinimizedCornerRadius: CGFloat {
        get { floatingGlassAppearance.minimizedCornerRadius }
        set { floatingGlassAppearance.minimizedCornerRadius = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.hidesTitlesWhenMinimized`。
    @objc public var floatingGlassHidesTitlesWhenMinimized: Bool {
        get { floatingGlassAppearance.hidesTitlesWhenMinimized }
        set { floatingGlassAppearance.hidesTitlesWhenMinimized = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.minimizedLayout`。
    @objc public var floatingGlassMinimizedLayout: TeroTabMinimizedLayout {
        get { floatingGlassAppearance.minimizedLayout }
        set { floatingGlassAppearance.minimizedLayout = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.glassTintMode`。
    @objc public var floatingGlassTintMode: TeroTabGlassTintMode {
        get { floatingGlassAppearance.glassTintMode }
        set { floatingGlassAppearance.glassTintMode = newValue }
    }

    /// 轉發至 `floatingGlassAppearance.glassTintColor`。
    @objc public var floatingGlassTintColor: UIColor? {
        get { floatingGlassAppearance.glassTintColor }
        set { floatingGlassAppearance.glassTintColor = newValue }
    }

    @objc public override init() {
        self.compact = TeroTabLayoutConfiguration()
        self.regular = TeroTabLayoutConfiguration()
        self.moreItem = TeroTabMoreItem()
        super.init()
        self.regular.maximumVisibleItems = 6
    }

    /// 每次呼叫回傳全新實例。
    @objc public static func defaultConfiguration() -> TeroTabBarConfiguration {
        TeroTabBarConfiguration()
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = TeroTabBarConfiguration()
        copy.style = style
        copy.compact.maximumVisibleItems = compact.maximumVisibleItems
        copy.regular.maximumVisibleItems = regular.maximumVisibleItems
        copy.itemAppearance = itemAppearance
        copy.badgeAppearance = badgeAppearance
        copy.classicAppearance = classicAppearance
        copy.floatingGlassAppearance = floatingGlassAppearance
        copy.scrollConfiguration = scrollConfiguration
        copy.motion = motion
        copy.swipeSelectionMode = swipeSelectionMode
        copy.morePresentationStyle = morePresentationStyle
        copy.moreItem = moreItem.copy() as! TeroTabMoreItem
        return copy
    }
}
