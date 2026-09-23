import Foundation

/// Tab Bar 的外觀。只決定外觀與版面，不決定支援哪些功能（見 ADR-0003）。
@objc public enum TeroTabBarStyle: Int {
    case classic
    case floatingGlass
}

@objc public enum TeroTabBadgeStyle: Int {
    case dot
    case value
}

/// Tab Bar 目前佔據的版面形態。`minimized` 為 FloatingGlass 專屬。
@objc public enum TeroTabBarPresentationState: Int {
    case expanded
    case minimized
    case hidden
}

@objc public enum TeroTabBarScrollBehavior: Int {
    /// 明確表示「這一頁不要有捲動反應」。
    case none
    case hideOnScrollDown
    case minimizeOnScrollDown
    /// 「沒有偏好」，交回設定決定。
    ///
    /// 與 `none` 的差別是意圖：`none` 是一個偏好（不要反應），`inherit` 是沒有偏好。
    /// 導管型別需要這個值——它必須實作協定成員才能把下層的偏好傳上去，而實作了就等於
    /// 一直在表達偏好；沒有這個 case 的話，唯一的出路是覆寫 `responds(to:)`。
    ///
    /// 排在最後是刻意的：插在前面會改掉既有 case 的 raw value。
    case inherit
}

/// 一次 Tab 切換的來源。讓 Analytics 與 delegate 能區分切換原因。
@objc public enum TeroTabSelectionSource: Int {
    case initial
    case user
    case programmatic
    case overflow
}

@objc public enum TeroTabMorePresentationStyle: Int {
    case automatic
    case menu
    case sheet
    case popover
}

@objc public enum TeroTabGlassTintMode: Int {
    case automatic
    case tinted
}

/// FloatingGlass 最小化時的版面（issue #93）。
@objc public enum TeroTabMinimizedLayout: Int {
    /// 整條 Bar 單一等比縮小，所有格位保留、標題隱藏。1.x 與 2.0 的行為，預設值。
    case uniform
    /// 只留選取中的那一格成一顆小膠囊，其餘淡出；點擊膠囊展開，不改選取。
    /// 這是 iOS 26 原生 `tabBarMinimizeBehavior` 收合之後的形態。
    case selectedOnly
}

/// 滑動選取的操作方式。預設為 `.disabled`，行為與只能點擊時完全相同。
@objc public enum TeroTabSwipeSelectionMode: Int {
    case disabled
    /// 選取外框連續跟隨手指，放開時吸附到最近的 Tab。
    case drag
    /// 左右輕掃，跳到相鄰的 Tab。
    case swipe
}
