import UIKit

/// 觀察 stack 變更。
///
/// 兩個事件的時點對應容器的兩個時刻（ADR-0014）：
///
/// - `willShow` 在 **commit** 那一刻——`viewControllers` 與 `topViewController` 已經是新值，
///   動畫還沒跑完。方法 return 之前就會收到。
/// - `didShow` 在 **settle** 那一刻——畫面追上了 stack，containment 的後半也做完了。
///
/// 互動式返回在 finish 判定成立之前不提交，所以**取消的手勢兩個事件都不發**：stack 一個字
/// 都沒變過，發事件就是在報告一次沒有發生的切換（issue #19 的 User Story 21）。
///
/// 轉場被新的 stack 變更打斷時，正在跑的那一段會結算到自己的終點，因此它的 `didShow`
/// 仍然會送出——只是緊接著就是下一段的 `willShow`。
@objc public protocol TeroNavigationContainerDelegate: NSObjectProtocol {

    @objc optional func teroNavigationContainer(
        _ container: TeroNavigationContainer,
        willShow viewController: UIViewController,
        animated: Bool
    )

    @objc optional func teroNavigationContainer(
        _ container: TeroNavigationContainer,
        didShow viewController: UIViewController,
        animated: Bool
    )
}
