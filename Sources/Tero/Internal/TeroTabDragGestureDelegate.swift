import UIKit

/// `.drag` 的 long press 專用的手勢代理。
///
/// 為什麼不讓 `TeroTabBar` 自己當代理：`TeroTabBar` 是公開型別，對
/// `UIGestureRecognizerDelegate` 的 conformance 會把
/// `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` 一起推上公開介面
/// ——公開 API 守門在凍結前抓到了這一條。代理搬到內部型別之後公開介面不變。
internal final class TeroTabDragGestureDelegate: NSObject, UIGestureRecognizerDelegate {

    /// 弱參考：辨識器由 Bar 持有，Bar 持有這個代理。
    internal weak var dragRecognizer: UIGestureRecognizer?

    /// long press 掛在整個 items 容器上、零秒就 `.began`，所以不讓它同時辨識的話
    /// 會吃掉 Tab 自己的點擊——使用者點一下就變成一次零位移的拖曳。
    internal func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === dragRecognizer || other === dragRecognizer
    }
}
