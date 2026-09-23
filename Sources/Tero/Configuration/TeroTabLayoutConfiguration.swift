import Foundation

/// 依 `horizontalSizeClass` 選用的版面設定。判準是 size class 而非裝置類型。
@objcMembers
public final class TeroTabLayoutConfiguration: NSObject, NSCopying {

    /// 可見的 Tab 與 More 的總數上限。包含 More，不含 Classic 的中央 Action slot。
    public var maximumVisibleItems: Int = 5 {
        didSet {
            guard maximumVisibleItems < 2 else { return }
            TeroDiagnostics.report("maximumVisibleItems 最小為 2，收到 \(maximumVisibleItems)，已夾到 2。")
            maximumVisibleItems = 2
        }
    }

    public override init() {
        super.init()
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = TeroTabLayoutConfiguration()
        copy.maximumVisibleItems = maximumVisibleItems
        return copy
    }
}
