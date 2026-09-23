import UIKit

/// 選取轉場的插補運算。Consumer 不應依賴此型別（計畫書 §52）。
///
/// 與彈簧換算同樣的處理：抽成純運算，才驗得起來——顏色與縮放曲線
/// 不必真的跑一次動畫再去螢幕上取樣。
internal enum TeroTabSelectionInterpolation {

    internal static func value(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        from + (to - from) * clamped(progress)
    }

    /// 拖曳中透鏡的形變：跟手速愈快壓得愈扁、拉得愈長。
    ///
    /// 轉場有進度可用（`lensStretch` 依 sin 曲線在中途拉到最長），**拖曳沒有**——
    /// 終點由手指決定，隨時會變。所以形變改由速度驅動。
    ///
    /// 兩軸相乘恆為 1（體積守恆）：那是 squash-and-stretch 的做法，也是「果凍」讀起來
    /// 像果凍而不是單純變寬的原因。
    internal static func lensDeformation(
        speed: CGFloat, reference: CGFloat, intensity: CGFloat
    ) -> (horizontal: CGFloat, vertical: CGFloat) {
        guard reference > 0, intensity > 0 else { return (1, 1) }
        let stretch = intensity * clamped(abs(speed) / reference)
        return (1 + stretch, 1 / (1 + stretch))
    }

    /// 顏色插補。
    ///
    /// 兩端都先以 `traits` 解析：`UIColor { traits in ... }` 這種動態顏色
    /// 不解析就取不到分量，會整段退化成其中一端。
    internal static func color(
        from: UIColor,
        to: UIColor,
        progress: CGFloat,
        traits: UITraitCollection
    ) -> UIColor {
        let progress = clamped(progress)
        guard let start = components(of: from.resolvedColor(with: traits)),
              let end = components(of: to.resolvedColor(with: traits)) else {
            // 圖樣色等取不到分量的情況：以中點為界直接換色，不做假的插補。
            return progress < 0.5 ? from : to
        }
        return UIColor(
            red: start.red + (end.red - start.red) * progress,
            green: start.green + (end.green - start.green) * progress,
            blue: start.blue + (end.blue - start.blue) * progress,
            alpha: start.alpha + (end.alpha - start.alpha) * progress
        )
    }

    /// 轉場中的內容縮放。
    ///
    /// `scale(t) = 1 + (rest - 1)·(1 - t) + bump·sin(π·t)`
    ///
    /// 兩端都固定收在 1.0，中途的起伏由 `bump` 決定：
    /// - 接手選取的項目 `rest < 1`、`bump > 0`：由小放大，中途略微過衝。
    /// - 交出選取的項目 `rest == 1`、`bump < 0`：原地略縮再回復。
    internal static func scale(transition t: CGFloat, rest: CGFloat, bump: CGFloat) -> CGFloat {
        let t = clamped(t)
        return 1 + (rest - 1) * (1 - t) + bump * sin(.pi * t)
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private static func components(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return (red, green, blue, alpha)
    }
}
