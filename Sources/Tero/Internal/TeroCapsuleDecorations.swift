import UIKit

/// FloatingGlass 膠囊內緣的一圈亮邊（issue #13）。
///
/// 漸層塗滿整顆膠囊，再用一個只有邊框的 view 當遮罩，只留下邊緣那一圈。遮罩用
/// `borderWidth` 與 `cornerRadius` 而不是 `CAShapeLayer` 的 path：獨立的 path 不在
/// UIView 的動畫裡，第一次排版就會從左上角長出來。
///
/// 顏色在 `layoutSubviews` 裡依當下的 trait 解析。iOS 17 起 UIKit 會記下 layout 讀過的
/// trait，深淺色一變就重新排版，動態顏色因此跟得上。亮邊只有 FloatingGlass 有，
/// 而它只在 iOS 26 以上生效。
internal final class TeroCapsuleRimView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    internal var gradientLayer: CAGradientLayer {
        // layerClass 保證了型別。
        layer as! CAGradientLayer
    }

    private let edgeMask = UIView()
    private var colors: [UIColor] = []

    internal var edgeWidth: CGFloat { edgeMask.layer.borderWidth }
    internal var edgeCornerRadius: CGFloat { edgeMask.layer.cornerRadius }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        isHidden = true
        // 疊在 contentView 裡所有東西之上，包括之後才加進來的 Action。
        layer.zPosition = 1
        edgeMask.backgroundColor = .clear
        edgeMask.layer.borderColor = UIColor.black.cgColor
        mask = edgeMask
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TeroCapsuleRimView 不支援 init(coder:)")
    }

    /// 寬度 0 或沒有顏色就不畫。
    internal func apply(width: CGFloat, colors: [UIColor], startPoint: CGPoint, endPoint: CGPoint) {
        isHidden = !(width > 0 && !colors.isEmpty)
        // CAGradientLayer 只有一個顏色時什麼都不畫。
        self.colors = colors.count == 1 ? [colors[0], colors[0]] : colors
        gradientLayer.startPoint = startPoint
        gradientLayer.endPoint = endPoint
        edgeMask.layer.borderWidth = max(0, width)
        setNeedsLayout()
    }

    internal func fit(cornerRadius: CGFloat, cornerCurve: CALayerCornerCurve) {
        edgeMask.layer.cornerRadius = cornerRadius
        edgeMask.layer.cornerCurve = cornerCurve
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        edgeMask.frame = bounds
        let traits = traitCollection
        gradientLayer.colors = colors.map { $0.resolvedColor(with: traits).cgColor }
    }
}

/// FloatingGlass 膠囊的外陰影（issue #13）。
///
/// 一個鋪滿 Bar、排在玻璃容器後面的 view，用 `shadowPath` 畫出兩顆膠囊的陰影，再用
/// even-odd 的遮罩挖掉膠囊本身：膠囊是半透明的，底下的陰影會透出來把它染灰。
/// 設計工具的外陰影也是這樣只畫在形狀外面。
internal final class TeroCapsuleShadowView: UIView {

    private let cutout = CAShapeLayer()
    private var color: UIColor = .black

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        isHidden = true
        cutout.fillRule = .evenOdd
        layer.mask = cutout
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TeroCapsuleShadowView 不支援 init(coder:)")
    }

    /// 不透明度 0 就不畫。
    internal func apply(opacity: Float, color: UIColor, offset: CGSize, radius: CGFloat) {
        isHidden = !(opacity > 0)
        self.color = color
        layer.shadowOpacity = max(0, opacity)
        layer.shadowOffset = offset
        layer.shadowRadius = max(0, radius)
        setNeedsLayout()
    }

    /// 由這些膠囊投下陰影。`frame` 用這個 view 的座標，圓角與膠囊的 layer 相同。
    internal func cast(from capsules: [(frame: CGRect, cornerRadius: CGFloat)]) {
        let shapes = CGMutablePath()
        for capsule in capsules where !capsule.frame.isEmpty {
            let radius = min(max(0, capsule.cornerRadius), capsule.frame.width / 2, capsule.frame.height / 2)
            shapes.addPath(CGPath(roundedRect: capsule.frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        }
        // 陰影可能到的範圍：模糊大約延伸三倍半徑，再加上位移。
        let reach = layer.shadowRadius * 3 + max(abs(layer.shadowOffset.width), abs(layer.shadowOffset.height)) + 2
        let visible = CGMutablePath()
        visible.addRect(bounds.union(shapes.boundingBoxOfPath).insetBy(dx: -reach, dy: -reach))
        visible.addPath(shapes)

        // 兩個 path 都不屬於 UIView 的動畫，不關掉隱含動畫就會在每一幀補間。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowPath = shapes
        cutout.frame = bounds
        cutout.path = visible
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowColor = color.resolvedColor(with: traitCollection).cgColor
    }
}
