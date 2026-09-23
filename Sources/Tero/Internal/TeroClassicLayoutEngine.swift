import UIKit

/// Classic 版面的位置計算。Consumer 不應依賴此型別（計畫書 §52）。
internal struct TeroClassicLayoutEngine {

    internal struct Layout {
        internal var itemFrames: [CGRect] = []
        /// 與 `itemFrames` 等長、逐格對齊的選取外框。
        internal var selectionFrames: [CGRect] = []
        internal var actionFrame: CGRect?
    }

    /// `itemCount` 是 Tab 加 More 的格數，不含 Action。
    ///
    /// 有 Action 時 Bar 實際格數為 `itemCount + 1`，Action 置於正中；
    /// `itemCount` 為奇數時左側多一格（計畫書 §14）。
    internal func layout(
        itemCount: Int,
        hasCenterAction: Bool,
        in bounds: CGRect,
        contentInsets: UIEdgeInsets,
        selectionInsets: UIEdgeInsets,
        selectionSizes: [CGSize?],
        layoutDirection: UIUserInterfaceLayoutDirection
    ) -> Layout {
        guard itemCount > 0 || hasCenterAction else { return Layout() }

        let area = bounds.inset(by: contentInsets)
        let columnCount = itemCount + (hasCenterAction ? 1 : 0)
        guard columnCount > 0 else { return Layout() }
        let width = area.width / CGFloat(columnCount)

        func frame(forColumn column: Int) -> CGRect {
            // RTL 時整列鏡像，第一格落在最右側。
            let slot = layoutDirection == .rightToLeft ? (columnCount - 1 - column) : column
            return CGRect(
                x: area.minX + CGFloat(slot) * width,
                y: area.minY,
                width: width,
                height: area.height
            ).integral
        }

        func selectionFrames(for itemFrames: [CGRect]) -> [CGRect] {
            TeroTabSelectionGeometry.frames(
                inSlots: itemFrames,
                requestedSizes: selectionSizes,
                insets: selectionInsets
            )
        }

        guard hasCenterAction else {
            let itemFrames = (0..<itemCount).map(frame(forColumn:))
            return Layout(
                itemFrames: itemFrames,
                selectionFrames: selectionFrames(for: itemFrames),
                actionFrame: nil
            )
        }

        let leftCount = Int((Double(itemCount) / 2).rounded(.up))
        var itemFrames: [CGRect] = []
        for index in 0..<itemCount {
            // 左半段照序，Action 佔中間那一欄，右半段順移一格
            let column = index < leftCount ? index : index + 1
            itemFrames.append(frame(forColumn: column))
        }
        return Layout(
            itemFrames: itemFrames,
            selectionFrames: selectionFrames(for: itemFrames),
            actionFrame: frame(forColumn: leftCount)
        )
    }
}
