import UIKit

/// 頁面對 Tab Bar **介面風格**的偏好。
///
/// Instagram 切到 Reels 時 Tab Bar 變成黑底白圖示，其餘 Tab 是淺色——那是同一條 Bar
/// 在不同頁面下用不同的介面風格，不是換一份設定。可見的頁面在這裡宣告它想要哪一種，
/// Bar 的 `overrideUserInterfaceStyle` 跟著走：`systemBackground`、`label` 一類的動態色
/// 自動翻轉，Classic 的模糊材質與 FloatingGlass 的玻璃也各自對應到深淺色版本。
///
/// 與 `TeroTabVisibilityProviding` 同一個形狀：單成員、`@objc optional`，在採用點與其他
/// 協定組合。解析時點也相同——切 Tab、導覽轉場結算之後、`refreshScrollTracking()`。
/// 容器型別（例如 `TeroNavigationContainer`）原封轉發 top 的宣告，沒有宣告時回 `.unspecified`。
///
/// 切換不帶動畫：Bar 的材質與顏色直接換。
@objc public protocol TeroTabBarAppearanceProviding: NSObjectProtocol {

    /// `.unspecified` 表示跟隨系統，也是未實作時的值。
    @objc optional var preferredTeroTabBarUserInterfaceStyle: UIUserInterfaceStyle { get }
}
