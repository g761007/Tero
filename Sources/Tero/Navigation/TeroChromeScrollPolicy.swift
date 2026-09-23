import CoreGraphics

/// 頂部 chrome 對捲動的反應方式。
///
/// 與 `TeroTabBarScrollBehavior` 是**兩組不同的值**，這正是 §26 要求 top 與 bottom
/// 各自決策的原因：同一次下捲，頂部可以整個收起來，底部可以只縮小或什麼都不做。
///
/// 「收起來」實際長什麼樣由 chrome view 決定（`TeroNavigationBar` 是 primary 淡出、
/// secondary 遞補）；這個值只決定容器**要不要**依捲動推進收合進度。
@objc public enum TeroChromeScrollBehavior: Int {
    /// 不隨捲動改變，收合進度恆為 0。
    case fixed
    /// 下捲時收合、上捲時展開（§24 的 hidePrimary）。預設值。
    case hidePrimary
}

/// 由捲動樣本算出 chrome 的收合進度。
///
/// **與 Tab Bar 的狀態機分開**：兩者讀同一份樣本與同一個方向鎖（`TeroScrollDirectionLock`），
/// 但輸出不同——這邊是 0…1 的連續進度，那邊是三個離散狀態。§26 明令不得
/// 讓 `headerProgress == tabBarProgress`。
///
/// 純值型別，可直接以 seam 2 測試。
internal struct TeroChromeScrollPolicy: Equatable {

    internal struct Configuration: Equatable {
        internal var behavior: TeroChromeScrollBehavior
        /// 從方向鎖的錨點走多遠算收完。
        internal var collapseDistance: CGFloat
        internal var directionLockDistance: CGFloat

        internal init(
            behavior: TeroChromeScrollBehavior = .hidePrimary,
            collapseDistance: CGFloat = 120,
            directionLockDistance: CGFloat = 8
        ) {
            self.behavior = behavior
            self.collapseDistance = collapseDistance
            self.directionLockDistance = directionLockDistance
        }
    }

    internal private(set) var progress: CGFloat = 0

    private var lock = TeroScrollDirectionLock()
    private var lastOffset: CGFloat = 0
    private var collapsedAtAnchor: CGFloat = 0
    private var wasAtBottomOverscroll = false

    internal init() {}

    internal mutating func reset(progress: CGFloat = 0, offset: CGFloat = 0) {
        self.progress = min(max(progress, 0), 1)
        collapsedAtAnchor = self.progress
        lastOffset = offset
        lock.reset(to: offset)
        wasAtBottomOverscroll = false
    }

    /// 吃進一次取樣，回傳應該生效的收合進度。
    ///
    /// 排除的輸入與 Tab Bar 那邊一致——回頂、refresh、幾何變更、非使用者驅動、
    /// 底部回彈——因為那些都不是「使用者想要收起 chrome」的訊號。
    @discardableResult
    internal mutating func consume(
        _ sample: TeroTabScrollSample,
        configuration: Configuration
    ) -> CGFloat {
        guard sample.offset.isFinite, sample.maximumOffset.isFinite else { return progress }
        defer { lastOffset = sample.offset }

        guard configuration.behavior != .fixed else {
            progress = 0
            return progress
        }
        if sample.geometryChanged {
            reset(progress: progress, offset: sample.offset)
            return progress
        }
        if sample.offset <= 0.5 || sample.maximumOffset <= 0.5 || sample.isRefreshing {
            reset(progress: 0, offset: max(0, sample.offset))
            return progress
        }
        guard sample.isUserDriven else {
            reset(progress: progress, offset: sample.offset)
            return progress
        }
        if sample.offset > sample.maximumOffset + 0.5 {
            wasAtBottomOverscroll = true
            return progress
        }
        if wasAtBottomOverscroll {
            reset(progress: progress, offset: sample.offset)
            return progress
        }

        let delta = sample.offset - lastOffset
        guard delta != 0 else { return progress }

        lock.consume(offset: sample.offset, delta: delta, lockDistance: configuration.directionLockDistance)
        guard lock.direction != .none else { return progress }

        let distance = configuration.collapseDistance > 0 ? configuration.collapseDistance : 120
        let travelled = lock.translation(at: sample.offset)
        progress = min(max(collapsedAtAnchor + travelled / distance, 0), 1)
        return progress
    }
}
