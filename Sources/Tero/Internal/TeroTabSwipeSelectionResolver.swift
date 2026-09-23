import UIKit

/// 滑動選取的決策邏輯。Consumer 不應依賴此型別（計畫書 §52）。
///
/// 與捲動狀態機同樣的處理：把「該選哪一格」抽成純運算，手勢管線只負責餵資料。
/// 這樣門檻、方向與 RTL 都能被單獨驗證，不必模擬真實觸控。
internal struct TeroTabSwipeSelectionResolver {

    internal var translationThreshold: CGFloat = 40
    internal var velocityThreshold: CGFloat = 300

    internal init() {}

    /// `drag` 進行中：每一格「被選取多少」。
    ///
    /// 拖曳原本完全不動進度，只改 frame。於是放開時協調器從陳舊的進度起跑，第一個
    /// callback 先把外框拉回起點那一格——使用者看到的是「閃回去再滑過來」。
    /// 進度跟著手指走之後，`beginSelectionSegment` 抓到的起點就是畫面上的樣子。
    ///
    /// 依幾何位置內插，所以 RTL 自動成立：格位的 midX 無論語意順序如何都是遞增的。
    internal func slotWeights(fingerX: CGFloat, slotCenters: [CGFloat]) -> [CGFloat] {
        guard !slotCenters.isEmpty else { return [] }
        var weights = [CGFloat](repeating: 0, count: slotCenters.count)
        guard slotCenters.count > 1 else {
            weights[0] = 1
            return weights
        }
        if fingerX <= slotCenters[0] {
            weights[0] = 1
            return weights
        }
        if let last = slotCenters.indices.last, fingerX >= slotCenters[last] {
            weights[last] = 1
            return weights
        }
        for index in 0..<(slotCenters.count - 1) {
            let lower = slotCenters[index]
            let upper = slotCenters[index + 1]
            guard fingerX >= lower, fingerX <= upper, upper > lower else { continue }
            let ratio = (fingerX - lower) / (upper - lower)
            weights[index] = 1 - ratio
            weights[index + 1] = ratio
            return weights
        }
        return weights
    }

    /// `drag` 進行中：外框該在哪。
    ///
    /// **跟的是手指的位置，不是位移量。** 原本的實作是「手勢開始時的外框 ＋ translation」，
    /// 那是相對位移：選取在 A、手指按在 D 拖 10pt，外框從 A 偏移 10pt，不是跟著 D 走。
    /// 只有手勢剛好從選取那一格起手時兩者才相等——文件說的是「連續跟隨手指」。
    ///
    /// 抽成純運算的理由與 `nearestSlot` 相同：手勢管線餵不進測試，這段算術可以。
    internal func indicatorFrame(
        followingCenterX centerX: CGFloat,
        startFrame: CGRect,
        in bounds: CGRect
    ) -> CGRect {
        var frame = startFrame
        frame.origin.x = centerX - frame.width / 2
        let lowerBound = bounds.minX
        let upperBound = max(lowerBound, bounds.maxX - frame.width)
        frame.origin.x = min(max(frame.origin.x, lowerBound), upperBound)
        return frame
    }

    /// `drag` 放開時：吸附到中心最接近的格位。
    internal func nearestSlot(toCenterX centerX: CGFloat, slotCenters: [CGFloat]) -> Int? {
        guard !slotCenters.isEmpty else { return nil }
        return slotCenters
            .enumerated()
            .min { abs($0.element - centerX) < abs($1.element - centerX) }?
            .offset
    }

    /// `swipe`：依位移與速度決定要跳到哪一格。
    ///
    /// `selectableSlotCount` 只算 Tab，不含 More——滑到 More 沒有意義。
    /// 回傳 nil 代表不動（未達門檻、已在頭尾、或目標是 More）。
    internal func adjacentSlot(
        from current: Int,
        translation: CGFloat,
        velocity: CGFloat,
        layoutDirection: UIUserInterfaceLayoutDirection,
        selectableSlotCount: Int
    ) -> Int? {
        guard abs(translation) >= translationThreshold || abs(velocity) >= velocityThreshold else {
            return nil
        }
        guard translation != 0 || velocity != 0 else { return nil }

        // 方向以位移為準；位移為零時退回速度。
        let signal = translation != 0 ? translation : velocity
        let isRTL = (layoutDirection == .rightToLeft)
        let movesForward = isRTL ? (signal > 0) : (signal < 0)

        let target = movesForward ? current + 1 : current - 1
        guard target >= 0, target < selectableSlotCount else { return nil }
        return target
    }
}
