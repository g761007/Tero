import UIKit

/// 位於 Tab Bar 上、但不是 Tab 的獨立指令。觸發時不改變 selection。
@objcMembers
public final class TeroTabActionItem: NSObject {

    public let identifier: String

    public var image: UIImage?

    /// 由 Action Item 強持有（見 ADR-0005）。Provider 不得強引用 `TeroTabBarController`。
    public var contentProvider: TeroTabContentProvider?

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

    @objc(initWithIdentifier:image:)
    public init(identifier: String, image: UIImage?) {
        self.identifier = identifier
        self.image = image
        super.init()
    }
}
