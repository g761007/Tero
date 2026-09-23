import UIKit

/// 選取膠囊的幾何。Consumer 不應依賴此型別（計畫書 §52）。
///
/// 由兩個 layout engine 共用：選取外框在哪是**版面**的問題，
/// 怎麼從一個位置走到另一個位置才是轉場協調器的問題（補充規格 §26）。
internal enum TeroTabSelectionGeometry {

    /// 單一格位的選取外框。
    ///
    /// `requestedSize` 為 `nil`（或任一邊為零）時退回「格位內縮」的推導；
    /// 指定時以格位中心對齊，並夾在格位內——不同 Tab 因此可以有不同的
    /// 選取尺寸，而不必假設 `width == item.width`（補充規格 §4）。
    internal static func frame(
        inSlot slot: CGRect,
        requestedSize: CGSize?,
        insets: UIEdgeInsets
    ) -> CGRect {
        guard let requestedSize, requestedSize.width > 0, requestedSize.height > 0 else {
            return slot.inset(by: insets)
        }
        let width = min(requestedSize.width, slot.width)
        let height = min(requestedSize.height, slot.height)
        return CGRect(
            x: slot.midX - width / 2,
            y: slot.midY - height / 2,
            width: width,
            height: height
        ).integral
    }

    /// 與 `slots` 等長、逐格對齊的選取外框。
    internal static func frames(
        inSlots slots: [CGRect],
        requestedSizes: [CGSize?],
        insets: UIEdgeInsets
    ) -> [CGRect] {
        slots.enumerated().map { index, slot in
            frame(
                inSlot: slot,
                requestedSize: index < requestedSizes.count ? requestedSizes[index] : nil,
                insets: insets
            )
        }
    }
}
