import UIKit

/// 襯在選取項目底下的圓角外框。Consumer 不應依賴此型別（計畫書 §52）。
///
/// 本身就是 `UIVisualEffectView`，而不是「一個容器裡放一層玻璃」：
/// 圓角與位置在轉場中逐幀變化，多一層就要多同步一次，遲早會對不上。
///
/// 玻璃材質時它是**巢狀**在 Tabs 膠囊裡的一層玻璃。
/// `UIGlassEffect.h` 明講 `UIGlassContainerEffect` 會把巢狀的玻璃元素合併渲染，
/// 所以外框不能放進玻璃容器——放進去就會和 Tabs 膠囊融成一塊而看不見；
/// 放在 Tabs 膠囊的 `contentView` 內才會是獨立的一層透鏡（補充規格 §5）。
internal final class TeroTabSelectionIndicatorView: UIVisualEffectView {

    internal enum Material: Equatable {
        case solid(UIColor)
        /// 帶 tint 的玻璃。
        ///
        /// tint 不是裝飾而是**必要**的：實測在 iOS 26 上，未著色的玻璃巢狀在
        /// 同樣是玻璃的 Tabs 膠囊裡會與宿主材質融成一體，畫面上完全看不見。
        /// 著色之後才是一層獨立、且仍有折射與高光的透鏡。
        case glass(UIColor)
        /// 轉場中的透鏡：clear、不著色，靠折射而不是填色被看見。
        ///
        /// 只有在**不巢狀於玻璃容器**時才成立——巢狀的玻璃會被容器合併渲染，
        /// 合併之後就沒有自己的 backdrop 可折射（ADR-0010）。
        case lens
    }

    private var appliedMaterial: Material?

    internal init() {
        super.init(effect: nil)
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    @available(*, unavailable)
    internal required init?(coder: NSCoder) { fatalError() }

    internal func apply(material: Material) {
        // 每次版面都重建一次 effect 會讓玻璃不斷重新取樣背景。
        guard material != appliedMaterial else { return }
        appliedMaterial = material

        switch material {
        case .solid(let color):
            effect = nil
            contentView.backgroundColor = color
        case .glass(let color):
            guard #available(iOS 26, *) else {
                // 理論上不可達：解析材質時已經擋掉 iOS 26 以下。
                TeroDiagnostics.report("玻璃選取外框不應在 iOS 26 以下生效")
                effect = nil
                return
            }
            let glass = UIGlassEffect(style: .regular)
            // 外框不吃觸控，互動效果留給底下的 Tabs 膠囊。
            glass.isInteractive = false
            glass.tintColor = color
            effect = glass
            contentView.backgroundColor = .clear
        case .lens:
            guard #available(iOS 26, *) else {
                TeroDiagnostics.report("透鏡不應在 iOS 26 以下生效")
                effect = nil
                return
            }
            let glass = UIGlassEffect(style: .clear)
            glass.isInteractive = false
            effect = glass
            contentView.backgroundColor = .clear
        }
    }
}
