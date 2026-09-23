import UIKit

/// 附加在 Tab Item 上的通知標記。屬於呈現狀態，不影響導覽。
///
/// VoiceOver 的播報文字用繼承自 `NSObject` 的 `accessibilityValue`：
/// 未設定時 `.value` 播報原始值，`.dot` 不播報——圓點沒有原始值可播，
/// 而套件不得夾帶任何字串（ADR-0007），因此圓點的語意需由 consumer 自行提供。
@objcMembers
public final class TeroTabBadge: NSObject, NSCopying {

    public var style: TeroTabBadgeStyle = .dot

    /// `style == .dot` 時忽略此值。
    public var value: String?

    public var backgroundColor: UIColor?
    public var textColor: UIColor?
    public var font: UIFont?
    public var minimumSize: CGSize = .zero
    public var offset: CGPoint = .zero

    public override init() {
        super.init()
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = TeroTabBadge()
        copy.style = style
        copy.value = value
        copy.backgroundColor = backgroundColor
        copy.textColor = textColor
        copy.font = font
        copy.minimumSize = minimumSize
        copy.offset = offset
        copy.accessibilityValue = accessibilityValue
        return copy
    }
}

extension TeroTabBadge {

    /// 圓點標記。以此建構時拿不到「dot 帶著 value」這種非法組合。
    @nonobjc public static func dot() -> TeroTabBadge {
        let badge = TeroTabBadge()
        badge.style = .dot
        return badge
    }

    /// 文字標記。接受任意字串。
    @nonobjc public static func value(_ text: String) -> TeroTabBadge {
        let badge = TeroTabBadge()
        badge.style = .value
        badge.value = text
        return badge
    }

    // 上面兩個 factory 在 Swift 是 `@nonobjc`（`value` 與實例屬性同名，直接 `@objc` 會撞
    // selector）。Objective-C 於是只能 `[TeroTabBadge new]` 再逐一設 `style` 與 `value`，
    // 而「dot 帶著 value」這種非法組合就擋不住了。以下兩個是 Objective-C 專用的對應物，
    // 對 Swift 隱藏——那邊已經有同義的 API，不必看到第二組名字。

    /// Objective-C 的 `+dotBadge`。
    @available(swift, obsoleted: 1.0)
    @objc(dotBadge)
    public static func dotBadgeForObjectiveC() -> TeroTabBadge { dot() }

    /// Objective-C 的 `+badgeWithValue:`。
    @available(swift, obsoleted: 1.0)
    @objc(badgeWithValue:)
    public static func badgeForObjectiveC(withValue text: String) -> TeroTabBadge { value(text) }
}
