import UIKit

/// 頁面 presentation 偏好。inherit 才允許 Scroll 決定狀態。
@objc public enum TeroTabVisibilityPolicy: Int {
    case inherit
    case expanded
    case hidden
}

/// 由頁面提供，不持有或替換 Navigation／Scroll delegate。
@objc public protocol TeroTabVisibilityProviding: NSObjectProtocol {
    @objc optional var preferredTeroTabVisibilityPolicy: TeroTabVisibilityPolicy { get }
}
