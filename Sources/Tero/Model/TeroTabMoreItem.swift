import UIKit

/// Tab Bar 上代表「其餘 Tabs」的入口。不是 Tab，沒有 index，也不會成為 selected Tab。
@objcMembers
public final class TeroTabMoreItem: NSObject, NSCopying {

    /// 為 `nil` 時只顯示圖示。套件不提供預設字串（見 ADR-0007）。
    public var title: String?

    public var image: UIImage?
    public var selectedImage: UIImage?

    /// 由 More Item 強持有（見 ADR-0005）。Provider 不得強引用 `TeroTabBarController`。
    public var contentProvider: TeroTabContentProvider?

    /// `accessibilityLabel` 繼承自 `NSObject` 的 UIAccessibility 成員，不重新宣告
    /// （NSObject 已提供，以 stored property 覆寫會編譯失敗）。
    public var accessibilityIdentifier: String?

    public override init() {
        super.init()
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = TeroTabMoreItem()
        copy.title = title
        copy.image = image
        copy.selectedImage = selectedImage
        copy.contentProvider = contentProvider
        copy.accessibilityLabel = accessibilityLabel
        copy.accessibilityIdentifier = accessibilityIdentifier
        return copy
    }
}
