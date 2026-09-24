import UIKit

/// 一個 Tab 在 Tab Bar 上的呈現形式。只描述外觀，不持有導覽目的地。
@objcMembers
public final class TeroTabItem: NSObject {

    public var title: String?
    public var image: UIImage?
    public var selectedImage: UIImage?

    /// Overflow 選單專用圖示。選單不 render 自訂內容，圖示依序退回 `overflowImage` → `image` → 無。
    public var overflowImage: UIImage?

    /// 由 Item 強持有（見 ADR-0005）。Provider 不得強引用 `TeroTabBarController`。
    public var contentProvider: TeroTabContentProvider?

    public var badge: TeroTabBadge?

    /// 這一格專屬的選取外框尺寸。
    ///
    /// `.zero` 代表未指定，沿用 `TeroTabItemAppearance.selectionIndicatorInsets`
    /// 從格位推導。指定時以格位中心對齊，並夾在格位內。
    /// 以 `.zero` 當哨符是為了在 Objective-C 上表示「未指定」，與 Badge 的
    /// `minimumSize` 同一種處理。
    public var selectionSize: CGSize = .zero

    /// Objective-C 是 `enabled`，getter 是 `isEnabled`，比照 UIKit。
    @objc(enabled)
    public var isEnabled: Bool {
        @objc(isEnabled) get { storedIsEnabled }
        set { storedIsEnabled = newValue }
    }
    private var storedIsEnabled = true

    /// `accessibilityLabel` 繼承自 `NSObject` 的 UIAccessibility 成員，不重新宣告
    /// （NSObject 已提供，以 stored property 覆寫會編譯失敗）。
    public var accessibilityIdentifier: String?

    @objc(initWithTitle:image:selectedImage:)
    public init(title: String?, image: UIImage?, selectedImage: UIImage?) {
        self.title = title
        self.image = image
        self.selectedImage = selectedImage
        super.init()
    }
}
