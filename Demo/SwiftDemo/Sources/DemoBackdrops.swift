import UIKit

/// Demo 用的背景。
///
/// 全部以程式繪製，不夾帶任何圖檔——套件與 Demo 都不得依賴打包資源（ADR-0007）。
/// 這些背景存在的唯一理由是給玻璃取樣：底下沒有內容變化，就看不出 Glass 有沒有在反應。
enum DemoBackdrop: String, CaseIterable {
    /// 深色、近乎純黑。參考影片裡最常見的底。
    case night
    /// 彩度高、明暗落差大，模擬照片。
    case photo
    /// 會持續移動的漸層，模擬影片。
    case motion
    /// 亮色。
    case daylight

    var colors: [UIColor] {
        switch self {
        case .night:
            return [UIColor(white: 0.06, alpha: 1), UIColor(white: 0.12, alpha: 1)]
        case .photo:
            return [
                UIColor(red: 0.96, green: 0.45, blue: 0.20, alpha: 1),
                UIColor(red: 0.55, green: 0.18, blue: 0.55, alpha: 1),
                UIColor(red: 0.09, green: 0.20, blue: 0.45, alpha: 1)
            ]
        case .motion:
            return [
                UIColor(red: 0.10, green: 0.65, blue: 0.75, alpha: 1),
                UIColor(red: 0.05, green: 0.12, blue: 0.35, alpha: 1),
                UIColor(red: 0.75, green: 0.20, blue: 0.45, alpha: 1)
            ]
        case .daylight:
            return [UIColor(white: 0.99, alpha: 1), UIColor(white: 0.90, alpha: 1)]
        }
    }

    var prefersLightContent: Bool {
        self != .daylight
    }
}


/// 畫出 `DemoBackdrop` 的視圖。
final class DemoBackdropView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }
    private var highlights: [CALayer] = []

    private let backdrop: DemoBackdrop

    init(backdrop: DemoBackdrop) {
        self.backdrop = backdrop
        super.init(frame: .zero)
        gradientLayer.colors = backdrop.colors.map(\.cgColor)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        addHighlights()
        if backdrop == .motion { animateGradient() }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 幾顆柔和光斑，讓玻璃的折射有東西可折。純漸層太平滑，看不出差別。
    private func addHighlights() {
        guard backdrop != .daylight else { return }
        for index in 0..<3 {
            let blob = CALayer()
            blob.backgroundColor = UIColor.white.withAlphaComponent(backdrop == .night ? 0.06 : 0.18).cgColor
            blob.cornerRadius = 90
            blob.shadowColor = UIColor.white.cgColor
            blob.shadowOpacity = 0.35
            blob.shadowRadius = 60
            blob.shadowOffset = .zero
            layer.addSublayer(blob)
            highlights.append(blob)
            _ = index
        }
    }

    private func animateGradient() {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.fromValue = backdrop.colors.map(\.cgColor)
        animation.toValue = backdrop.colors.reversed().map(\.cgColor)
        animation.duration = 4
        animation.autoreverses = true
        animation.repeatCount = .infinity
        gradientLayer.add(animation, forKey: "colors")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 180
        for (index, blob) in highlights.enumerated() {
            let fraction = CGFloat(index + 1) / CGFloat(highlights.count + 1)
            blob.frame = CGRect(
                x: bounds.width * fraction - side / 2,
                y: bounds.height * (0.25 + 0.25 * CGFloat(index)) - side / 2,
                width: side,
                height: side
            )
        }
    }
}
