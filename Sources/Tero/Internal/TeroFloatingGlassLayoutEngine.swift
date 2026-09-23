import UIKit

/// FloatingGlass 版面的位置計算。Consumer 不應依賴此型別（計畫書 §52）。
///
/// Bar 本身是一塊全寬的區域，裡面放兩個膠囊：Tabs 與 Action。
/// Action 因此位於 Tabs 之外（ADR-0003），而兩者同屬一個容器——
/// 這正是 iOS 26 玻璃容器需要的階層。
internal struct TeroFloatingGlassLayoutEngine {

    internal struct Layout {
        internal var tabsCapsule: CGRect = .zero
        internal var actionCapsule: CGRect?
        internal var itemFrames: [CGRect] = []
        /// 與 `itemFrames` 等長、逐格對齊的選取外框。
        internal var selectionFrames: [CGRect] = []
        internal var capsuleHeight: CGFloat = 0
        internal var cornerRadius: CGFloat = 0
    }

    internal func layout(
        itemCount: Int,
        hasAction: Bool,
        state: TeroTabBarPresentationState,
        in bounds: CGRect,
        appearance: TeroFloatingGlassAppearance,
        selectionInsets: UIEdgeInsets,
        selectionSizes: [CGSize?],
        layoutDirection: UIUserInterfaceLayoutDirection,
        selectedIndex: Int? = nil
    ) -> Layout {
        var layout = Layout()

        let isMinimized = (state == .minimized)
        layout.capsuleHeight = isMinimized ? appearance.minimizedHeight : appearance.expandedHeight
        layout.cornerRadius = isMinimized ? appearance.minimizedCornerRadius : appearance.cornerRadius

        let available = bounds.width - appearance.horizontalInset * 2
        guard available > 0 else { return layout }

        // 最小化時 Action 縮成與膠囊同高的方形。
        let actionSide = min(appearance.actionSize.width, layout.capsuleHeight)
        let actionWidth = hasAction ? (isMinimized ? actionSide : appearance.actionSize.width) : 0
        let spacing = hasAction ? appearance.actionSpacing : 0
        let maximumTabsWidth = max(0, available - actionWidth - spacing)
        // 最小化是**單一等比縮放**：寬與高用同一個比例。
        //
        // 原本寬是 `itemCount × 48` 夾出來的，與高度比無關。兩軸來源不同的後果是格位
        // 容不下等比縮放後的外框——預設設定（3 格 ＋ Action）就已經落在這一支：外框
        // 被夾成滿格寬，比例從 1.875 掉到 1.55。高度比愈接近 1 愈嚴重，而寫成 0.8 的
        // 測試看不出來。改成同一個比例之後，外框一定塞得進格位，不必再夾。
        let expandedActionWidth = hasAction ? appearance.actionSize.width : 0
        let expandedTabsWidth = max(0, available - expandedActionWidth - spacing)
        let heightScale = appearance.expandedHeight > 0
            ? layout.capsuleHeight / appearance.expandedHeight
            : 1
        // 只留選取格（issue #93）：膠囊縮成一顆小膠囊。寬度取選取格等比縮放後的寬，夾在高度的
        // 1…1.6 倍之間——太窄像一顆點，太寬看不出「只剩一格」。
        let selectedOnly = isMinimized && appearance.minimizedLayout == .selectedOnly && itemCount > 0
        let tabsWidth: CGFloat
        if selectedOnly {
            let pill = expandedTabsWidth / CGFloat(itemCount) * heightScale
            tabsWidth = min(maximumTabsWidth,
                            min(max(pill, layout.capsuleHeight), layout.capsuleHeight * 1.6).rounded())
        } else if isMinimized {
            tabsWidth = min(maximumTabsWidth, expandedTabsWidth * heightScale)
        } else {
            tabsWidth = maximumTabsWidth
        }

        let isRTL = (layoutDirection == .rightToLeft)
        let groupInset = max(0, (available - tabsWidth - actionWidth - spacing) / 2)
        let tabsX = isRTL
            ? bounds.maxX - appearance.horizontalInset - groupInset - tabsWidth
            : bounds.minX + appearance.horizontalInset + groupInset

        layout.tabsCapsule = CGRect(
            x: tabsX,
            y: bounds.minY,
            width: tabsWidth,
            height: layout.capsuleHeight
        ).integral

        if hasAction {
            let actionHeight = isMinimized ? layout.capsuleHeight : min(appearance.actionSize.height, bounds.height)
            let actionX = isRTL
                ? bounds.minX + appearance.horizontalInset + groupInset
                : bounds.maxX - appearance.horizontalInset - groupInset - actionWidth
            layout.actionCapsule = CGRect(
                x: actionX,
                y: bounds.minY + ((layout.capsuleHeight - actionHeight) / 2).rounded(),
                width: actionWidth,
                height: actionHeight
            ).integral
        }

        guard itemCount > 0 else { return layout }
        if selectedOnly {
            return selectedOnlyFrames(
                into: layout, itemCount: itemCount, selectedIndex: selectedIndex, tabsWidth: tabsWidth,
                expandedSlotWidth: expandedTabsWidth / CGFloat(itemCount), scale: heightScale,
                appearance: appearance, selectionInsets: selectionInsets, selectionSizes: selectionSizes
            )
        }
        let slotWidth = tabsWidth / CGFloat(itemCount)
        layout.itemFrames = (0..<itemCount).map { index in
            let slot = isRTL ? (itemCount - 1 - index) : index
            return CGRect(
                x: CGFloat(slot) * slotWidth,
                y: 0,
                width: slotWidth,
                height: layout.capsuleHeight
            ).integral
        }
        // 選取外框按**自己的**尺寸等比縮放，不是跟著格位縮。
        //
        // 跟著格位縮就是跟著格位一起變形——而格位是看不見的，使用者看見的是那顆膠囊。
        // 膠囊的寬現在與高用同一個比例（見上），所以等比縮放後的外框一定塞得進格位。
        let scale = heightScale
        let expandedSlotWidth = expandedTabsWidth / CGFloat(itemCount)

        // 剩餘量按原本的左右／上下比例分配，非對稱內縮才不會被硬拉成置中。
        func distribute(_ total: CGFloat, _ near: CGFloat, _ far: CGFloat) -> (CGFloat, CGFloat) {
            let sum = near + far
            guard sum > 0 else { return (total / 2, total / 2) }
            return (total * near / sum, total * far / sum)
        }
        let targetWidth = max(0, expandedSlotWidth - selectionInsets.left - selectionInsets.right) * scale
        let targetHeight = max(0, appearance.expandedHeight - selectionInsets.top - selectionInsets.bottom) * scale
        let (left, right) = distribute(max(0, slotWidth - targetWidth), selectionInsets.left, selectionInsets.right)
        let (top, bottom) = distribute(
            max(0, layout.capsuleHeight - targetHeight), selectionInsets.top, selectionInsets.bottom
        )

        layout.selectionFrames = TeroTabSelectionGeometry.frames(
            inSlots: layout.itemFrames,
            // 指定尺寸走置中分支、繞過內縮，但同樣要等比縮——否則它在最小化時不會跟著小。
            requestedSizes: selectionSizes.map { $0.map { CGSize(width: $0.width * scale, height: $0.height * scale) } },
            insets: UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        )
        return layout
    }

    /// `.selectedOnly` 的格位：選取格佔滿膠囊，其餘收成膠囊中央的零寬矩形。
    ///
    /// 零寬而不是移出畫面：從展開內插過來時各格往中心收攏、同時淡出（alpha 由 Bar 套），
    /// 而不是往左右飛出去。選取外框只有選取格有，等比縮放的規則與 uniform 相同。
    private func selectedOnlyFrames(
        into layout: Layout,
        itemCount: Int,
        selectedIndex: Int?,
        tabsWidth: CGFloat,
        expandedSlotWidth: CGFloat,
        scale: CGFloat,
        appearance: TeroFloatingGlassAppearance,
        selectionInsets: UIEdgeInsets,
        selectionSizes: [CGSize?]
    ) -> Layout {
        var layout = layout
        let selected = selectedIndex.flatMap { (0..<itemCount).contains($0) ? $0 : nil } ?? 0
        let full = CGRect(x: 0, y: 0, width: tabsWidth, height: layout.capsuleHeight).integral
        let collapsed = CGRect(x: (tabsWidth / 2).rounded(), y: 0, width: 0, height: layout.capsuleHeight)
        layout.itemFrames = (0..<itemCount).map { $0 == selected ? full : collapsed }

        let requested = selectionSizes.indices.contains(selected) ? selectionSizes[selected] : nil
        let scaledInsets = UIEdgeInsets(
            top: selectionInsets.top * scale, left: selectionInsets.left * scale,
            bottom: selectionInsets.bottom * scale, right: selectionInsets.right * scale
        )
        let targetWidth = min(
            max(0, expandedSlotWidth - selectionInsets.left - selectionInsets.right) * scale,
            max(0, full.width - scaledInsets.left - scaledInsets.right)
        )
        let targetHeight = max(0, appearance.expandedHeight - selectionInsets.top - selectionInsets.bottom) * scale
        let size = requested.map { CGSize(width: min($0.width * scale, full.width), height: min($0.height * scale, full.height)) }
            ?? CGSize(width: targetWidth, height: targetHeight)
        let selection = TeroTabSelectionGeometry.frame(inSlot: full, requestedSize: size, insets: scaledInsets)
        let empty = CGRect(x: collapsed.midX, y: layout.capsuleHeight / 2, width: 0, height: 0)
        layout.selectionFrames = (0..<itemCount).map { $0 == selected ? selection : empty }
        return layout
    }

    internal static func interpolate(_ from: Layout, _ to: Layout, progress: CGFloat) -> Layout {
        let p = min(max(progress, 0), 1)
        func value(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        func rect(_ a: CGRect, _ b: CGRect) -> CGRect {
            CGRect(x: value(a.minX, b.minX), y: value(a.minY, b.minY),
                   width: value(a.width, b.width), height: value(a.height, b.height))
        }
        var result = from
        result.tabsCapsule = rect(from.tabsCapsule, to.tabsCapsule)
        if let a = from.actionCapsule, let b = to.actionCapsule { result.actionCapsule = rect(a, b) }
        result.itemFrames = zip(from.itemFrames, to.itemFrames).map(rect)
        result.selectionFrames = zip(from.selectionFrames, to.selectionFrames).map(rect)
        result.capsuleHeight = value(from.capsuleHeight, to.capsuleHeight)
        result.cornerRadius = value(from.cornerRadius, to.cornerRadius)
        return result
    }

}
