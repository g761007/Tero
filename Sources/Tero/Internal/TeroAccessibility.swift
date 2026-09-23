import UIKit

/// 輔助功能設定的讀取點。
///
/// 以可替換的閉包表示，讓「降低透明度」與「減少動態效果」的降級行為能被測試——
/// 這兩個設定無法在單元測試中真的開啟。與 `TeroDiagnostics` 同樣的理由。
internal enum TeroAccessibility {

    internal static var isReduceTransparencyEnabled: () -> Bool = {
        UIAccessibility.isReduceTransparencyEnabled
    }

    internal static var isReduceMotionEnabled: () -> Bool = {
        UIAccessibility.isReduceMotionEnabled
    }

    /// 減少動態效果開啟時，一律視為不做動畫。
    internal static func resolvedAnimated(_ animated: Bool) -> Bool {
        animated && !isReduceMotionEnabled()
    }
}
