import UIKit

/// Badge 的視圖。Consumer 不應依賴此型別（計畫書 §52）。
internal final class TeroTabBadgeView: UIView {

    /// 單一 Badge 已指定的屬性優先於預設外觀（計畫書 §24）。
    ///
    /// `minimumSize` 與 `offset` 在 Objective-C 相容的模型上無法表示「未指定」，
    /// 因此以 `.zero` 作為「沿用預設」的哨符。
    internal struct Resolved {
        internal var backgroundColor: UIColor
        internal var textColor: UIColor
        internal var font: UIFont
        internal var size: CGSize
        internal var offset: CGPoint
        internal var text: String?
        internal var spokenValue: String?

        internal init(badge: TeroTabBadge, defaults: TeroTabBadgeAppearance) {
            backgroundColor = badge.backgroundColor ?? defaults.backgroundColor
            textColor = badge.textColor ?? defaults.textColor
            font = badge.font ?? defaults.font
            offset = badge.offset == .zero ? defaults.offset : badge.offset

            spokenValue = badge.accessibilityValue
            switch badge.style {
            case .dot:
                // `.dot` 忽略 value（計畫書 §10）。
                text = nil
                size = badge.minimumSize == .zero ? defaults.dotSize : badge.minimumSize
            case .value:
                let value = badge.value ?? ""
                text = value
                if spokenValue == nil, !value.isEmpty { spokenValue = value }
                let minimumSize = badge.minimumSize == .zero ? defaults.minimumSize : badge.minimumSize
                let textSize = (value as NSString).size(withAttributes: [.font: font])
                let insets = defaults.contentInsets
                size = CGSize(
                    width: max(minimumSize.width, ceil(textSize.width) + insets.left + insets.right),
                    height: max(minimumSize.height, ceil(textSize.height) + insets.top + insets.bottom)
                )
            }
        }
    }

    private let label = UILabel()
    private(set) var resolved: Resolved?

    internal override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        label.textAlignment = .center
        addSubview(label)
    }

    internal required init?(coder: NSCoder) { fatalError() }

    internal func configure(with badge: TeroTabBadge, defaults: TeroTabBadgeAppearance) {
        let resolved = Resolved(badge: badge, defaults: defaults)
        self.resolved = resolved
        backgroundColor = resolved.backgroundColor
        label.text = resolved.text
        label.textColor = resolved.textColor
        label.font = resolved.font
        label.isHidden = (resolved.text?.isEmpty ?? true)
        bounds.size = resolved.size
        setNeedsLayout()
    }

    internal override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        layer.masksToBounds = true
    }
}
