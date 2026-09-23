import UIKit

@objc public protocol TeroTabBarControllerDelegate: NSObjectProtocol {

    /// 初始選取（`source == .initial`）不會詢問此方法，因此無法被阻止。
    @objc optional func teroTabBarController(
        _ tabController: TeroTabBarController,
        shouldSelect tab: TeroTab,
        source: TeroTabSelectionSource
    ) -> Bool

    @objc optional func teroTabBarController(
        _ tabController: TeroTabBarController,
        didSelect tab: TeroTab,
        source: TeroTabSelectionSource
    )

    /// 僅由使用者互動觸發。程式呼叫選取已選中的 Tab 不會發出此事件。
    @objc optional func teroTabBarController(
        _ tabController: TeroTabBarController,
        didReselect tab: TeroTab
    )

    /// 使用者在某個 Tab 上按住半秒（Instagram 長按 Profile 切帳號那一類）。
    ///
    /// 只在 delegate 實作了這個方法時才裝辨識器；More 與 Action 不發。辨識成功時 Tab
    /// 自己的點擊被取消，不會順帶選取。
    ///
    /// **與 `swipeSelectionMode == .drag` 互斥**：拖曳由零秒長按驅動、touch-down 當下就
    /// 接手，半秒的長按永遠等不到，所以那個模式下不會收到這個事件。
    @objc optional func teroTabBarController(
        _ tabController: TeroTabBarController,
        didLongPress tab: TeroTab
    )

    @objc optional func teroTabBarController(
        _ tabController: TeroTabBarController,
        didTrigger actionItem: TeroTabActionItem
    )

    @objc optional func teroTabBarController(
        _ tabController: TeroTabBarController,
        willChangeTabBarPresentationState state: TeroTabBarPresentationState
    )

    @objc optional func teroTabBarController(
        _ tabController: TeroTabBarController,
        didChangeTabBarPresentationState state: TeroTabBarPresentationState
    )
}
