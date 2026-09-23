import UIKit

/// Bar 上一格的呈現內容。把 `TeroTabItem` 與 `TeroTabMoreItem` 收斂成同一種形狀，
/// 讓版面與視圖不必知道自己畫的是 Tab 還是 More。
internal struct TeroTabItemPresentation {

    /// 穩定鍵，用來在 Item 視圖被重建（例如進出 Overflow）之後仍能對回同一份自訂內容。
    internal var key: String
    internal var contentProvider: TeroTabContentProvider?

    internal var title: String?
    internal var image: UIImage?
    internal var selectedImage: UIImage?
    internal var badge: TeroTabBadge?
    /// 這一格要求的選取外框尺寸。`nil` 代表未指定。
    internal var selectionSize: CGSize?
    internal var isEnabled: Bool
    internal var accessibilityLabel: String?
    internal var accessibilityIdentifier: String?

    internal static let moreKey = "__tero.more__"
    internal static let actionKey = "__tero.action__"

    internal init(key: String, item: TeroTabItem) {
        self.key = key
        contentProvider = item.contentProvider
        title = item.title
        image = item.image
        selectedImage = item.selectedImage ?? item.image
        badge = item.badge
        selectionSize = item.selectionSize == .zero ? nil : item.selectionSize
        isEnabled = item.isEnabled
        accessibilityLabel = item.accessibilityLabel ?? item.title
        accessibilityIdentifier = item.accessibilityIdentifier
    }

    /// More 沒有 `isEnabled`；它的 Badge 由 overflow 的解析結果決定，consumer 不設定。
    internal init(moreItem: TeroTabMoreItem, badge: TeroTabBadge?) {
        key = Self.moreKey
        contentProvider = moreItem.contentProvider
        title = moreItem.title
        // 套件不得夾帶資源，預設圖示一律用系統符號（ADR-0007）。
        image = moreItem.image ?? UIImage(systemName: "ellipsis")
        selectedImage = moreItem.selectedImage ?? moreItem.image ?? UIImage(systemName: "ellipsis")
        self.badge = badge
        selectionSize = nil
        isEnabled = true
        accessibilityLabel = moreItem.accessibilityLabel ?? moreItem.title
        accessibilityIdentifier = moreItem.accessibilityIdentifier
    }
}


extension TeroTabItemPresentation {

    /// Action 沒有標題也沒有 Badge：它是指令，不是 Tab（計畫書 §11）。
    internal init(actionItem: TeroTabActionItem) {
        key = Self.actionKey
        contentProvider = actionItem.contentProvider
        title = nil
        image = actionItem.image
        selectedImage = actionItem.image
        badge = nil
        selectionSize = nil
        isEnabled = actionItem.isEnabled
        accessibilityLabel = actionItem.accessibilityLabel
        accessibilityIdentifier = actionItem.accessibilityIdentifier
    }
}
