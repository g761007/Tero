import UIKit

/// 一個導覽目的地：不可變的 identity、要呈現的 view controller，以及它在 Tab Bar 上的呈現。
@objcMembers
public final class TeroTab: NSObject {

    /// 必須唯一，建立後不可修改。
    public let identifier: String

    public let viewController: UIViewController

    public let item: TeroTabItem

    @objc(initWithIdentifier:viewController:item:)
    public init(identifier: String, viewController: UIViewController, item: TeroTabItem) {
        self.identifier = identifier
        self.viewController = viewController
        self.item = item
        super.init()
    }
}
