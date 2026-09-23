import UIKit

/// 能接收捲動樣本的子容器。
///
/// Tab Bar 用這個協定把樣本往下轉，因此不必認得 `TeroNavigationContainer` 這個型別
/// ——任何 conform 的容器都接得上（§38／B20，與 chrome 那幾條導管同一個做法）。
internal protocol TeroScrollSampleReceiving: AnyObject {
    func consumeScrollSample(_ sample: TeroTabScrollSample)
}
