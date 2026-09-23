import UIKit

/// 為單一 Tab Item 或 Action Item 提供自訂內容。
///
/// Provider 負責內容本身與動畫；容器的位置與大小由 `TeroTabBarController` 決定。
/// 所有回呼都在 main thread。
@objc public protocol TeroTabContentProvider: NSObjectProtocol {

    /// 每個 Item 各自呼叫一次，取得屬於它的 view 實例。
    func makeContentView() -> UIView

    /// `animated` 為 `false` 時可能代表使用者開啟了「減少動態效果」，此時應停止播放。
    @objc optional func updateContentView(
        _ contentView: UIView,
        selected: Bool,
        presentationState: TeroTabBarPresentationState,
        animated: Bool
    )
}


/// 需要**連續**選取進度的自訂內容。
///
/// `TeroTabContentProvider` 只說得出「選取／未選取」，做不出選取膠囊滑動途中
/// 同步變化的動畫（補充規格 §6、§8）。採用這個協定的 provider 會額外收到
/// 0.0…1.0 的進度，可以直接當成 Lottie 的播放進度用。
///
/// **進度有兩個來源**：選取轉場的每一幀，以及 `swipeSelectionMode = .drag` 拖曳
/// 進行中的每一次跟手。後者的 `animated` 一律是 `false`——每一次回呼都是手指的當下
/// 位置，不是一段動畫，provider 應該直接把進度套上去。
///
/// 這是**可選的進階協定**，不是 breaking change：只實作
/// `TeroTabContentProvider` 的 provider 行為完全不變；兩者都實作時，
/// 轉場與拖曳途中收到連續進度，狀態落定時仍照舊收到 Bool 版本的回呼。
@objc public protocol TeroTabInteractiveContentProvider: TeroTabContentProvider {

    /// - Parameters:
    ///   - selectionProgress: 這一格的選取程度。0.0 為完全未選取，1.0 為完全選取。
    ///     一段轉場結束時保證以精確的 0.0 或 1.0 收尾；拖曳被放棄時同樣送出端點值。
    ///   - animated: 與 `TeroTabContentProvider` 的同名參數同義——
    ///     為 `false` 時可能代表使用者開啟了「減少動態效果」，此時應停止播放。
    @objc optional func updateContentView(
        _ contentView: UIView,
        selectionProgress: CGFloat,
        animated: Bool
    )

    /// expanded = 0、minimized = 1。Hidden 使用既有離散 state，不占用此進度。
    /// Reduce Motion／無動畫直接送端點；Action 也可接收此回呼。
    @objc optional func updateContentView(
        _ contentView: UIView,
        presentationProgress: CGFloat,
        animated: Bool
    )

}
