import UIKit

/// 由目前顯示的畫面交出它的捲動輸入。
///
/// 套件**不會**設定或替換 `scrollView.delegate`（計畫書 §39）：它以 `contentOffset` 觀察
/// 與捲動視圖自己的手勢辨識器取得樣本，因此 consumer 既有的捲動邏輯完全不受影響。
///
/// 這是**共用**的輸入：頂部 chrome 與底部 Tab Bar 讀同一份樣本，各自決定怎麼反應。
/// 名字因此是中性的；某一側專屬的偏好住在自己的協定裡（見 `TeroTabBarScrollBehaviorProviding`）。
@objc public protocol TeroScrollProviding: NSObjectProtocol {

    /// 回傳 nil 表示這個畫面不參與捲動追蹤。
    var teroTrackingScrollView: UIScrollView? { get }

}

/// 畫面對 **Tab Bar** 捲動反應方式的偏好。
///
/// 與 `TeroScrollProviding` 分開，因為這一項是 Tab Bar 專屬的：頂部 chrome 的反應方式是
/// 另一組值。這也是本專案已驗證的形狀——`TeroTabVisibilityProviding` 同樣是單成員協定，
/// 在採用點與其他協定組合
/// （見 `docs/plans/2026-09-15-navigation-tab-interaction.md` 的「不要複製已有的 scroll behavior 屬性」）。
///
/// ## 導管
///
/// 在 Swift 裡，`@objc optional` 的成員只要宣告了就永遠「有回應」——沒有「這次不表態」
/// 這回事。把下層的偏好往上傳的容器因此要回 `.inherit` 表示沒有偏好：
///
/// ```swift
/// extension MyContainer: TeroTabBarScrollBehaviorProviding {
///     var preferredTeroTabBarScrollBehavior: TeroTabBarScrollBehavior {
///         (topViewController as? TeroTabBarScrollBehaviorProviding)?
///             .preferredTeroTabBarScrollBehavior ?? .inherit
///     }
/// }
/// ```
@objc public protocol TeroTabBarScrollBehaviorProviding: NSObjectProtocol {

    /// 未實作時沿用設定中的行為；實作並回 `.inherit` 的效果相同。
    @objc optional var preferredTeroTabBarScrollBehavior: TeroTabBarScrollBehavior { get }
}
