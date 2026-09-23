import UIKit

/// 由畫面自己提供頂部 chrome。
///
/// Tero 對 chrome 的契約只有兩件事：**一個 `UIView`**，以及**一條 0…1 的收合進度**。
/// 裡面有沒有標題、有幾個區域、怎麼排版，Tero 一律不認得——那是這個 view 自己的事。
///
/// ## 半透明是被鼓勵的
///
/// chrome view **可以**半透明，而且多數情況下應該是。內容從它底下捲過去，實色底會把那層
/// 關係整個蓋掉——看不到模糊，也就看不出內容還在後面。
///
/// iOS 26 上容器會在 chrome 的容器 view 裝一個 `.top` 的
/// `UIScrollEdgeElementContainerInteraction`，追蹤對象取自這一頁的 `teroTrackingScrollView`
/// （底部 Tab Bar 裝的是對稱的 `.bottom` 版本）。
///
/// **它確實會生效，但生效的方式與想像的不同。** 2026-09-18 在 iPhone 17／iOS 26 模擬器實測：
/// 互動一裝上，chrome 區裡的動態系統色會解析成 bar 的變體——`systemBackground` 畫出來是
/// (245, 245, 245) 而不是白，固定色（`.white`）不受影響；另一個專案回報半透明 chrome 下
/// 捲動時看不到邊緣的模糊。所以：不透明、要與內容同色的 chrome 把容器的
/// `isScrollEdgeEffectEnabled` 關掉或用固定色；需要邊緣有視覺處理的話自己在 chrome view 上做。
/// 半透明 chrome 上的邊緣效果本身還需要真機確認。
///
/// 需要不透明時（「降低透明度」開啟，或設計本來就要實色）自己換掉底。`TeroNavigationBar`
/// 的做法可以照抄：預設 `UIBlurEffect`，`UIAccessibility.isReduceTransparencyEnabled`
/// 為真時換成實色。
///
/// 這個邊界是刻意的（計畫書 §57：提供足夠自由的 navigation primitives，而不是把某一種
/// App 的版面凍進公開 API）。要做 Primary／Secondary 兩段式的 chrome，用
/// `TeroNavigationBar`，它在自己內部實作那個結構。
///
/// 高度是**設定值不是量測值**：Tero 不呼叫 `systemLayoutSizeFitting`，也不讀
/// `intrinsicContentSize`。你給兩個端點，中間由 Tero 內插。
@objc public protocol TeroNavigationChromeProviding: NSObjectProtocol {

    /// 建立這一頁的 chrome view。
    ///
    /// 只在這個 View Controller 進入容器階層時呼叫一次，回傳的 view 由 Tero 安裝與移除。
    /// 生命週期比照 Content Provider（ADR-0005，細節在 ADR-0013）：容器 strong 持有，
    /// 離開階層時釋放，頁面存活期間不重建。
    ///
    /// **chrome view 不得強引用容器。** 容器持有畫面、畫面持有這個 view，再由它強引用
    /// 容器就是一個循環——`UIAction { _ in container.pop... }` 這種最自然的寫法會把整個
    /// stack 洩到 App 結束。要在 chrome 上做 push／pop，用 `weak var container`。
    func makeTeroNavigationChromeView() -> UIView

    /// 完全展開時的高度。
    var teroNavigationChromeHeight: CGFloat { get }

    /// 完全收合時的高度。未實作時等於展開高度，也就是這個 chrome 不收合。
    @objc optional var teroNavigationChromeCollapsedHeight: CGFloat { get }

    /// 收合進度改變時呼叫。0 為完全展開，1 為完全收合。
    ///
    /// 未實作表示這個 chrome 不需要逐幀更新——Tero 仍然會依兩個端點內插它的高度。
    @objc optional func updateTeroNavigationChrome(_ chromeView: UIView, collapseProgress: CGFloat)
}
