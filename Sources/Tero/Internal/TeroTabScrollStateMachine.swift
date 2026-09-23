import CoreGraphics

/// 捲動的一次取樣。刻意不含任何 UIKit 型別，讓狀態機能在無 UI 的環境下測試。
internal struct TeroTabScrollSample: Equatable {

    /// 相對於內容頂部的位移。0 表示在頂部，負值表示往上拉過頭（回彈）。
    internal var offset: CGFloat

    /// 可捲動的最大位移。`offset` 超過它表示往下拉過頭（回彈）。
    internal var maximumOffset: CGFloat

    /// 手勢速度（點／秒）。正值代表使用者往上滑，也就是「往下捲動內容」。
    internal var velocity: CGFloat
    internal var isUserDriven = true
    internal var isRefreshing = false
    internal var geometryChanged = false

    internal init(offset: CGFloat, maximumOffset: CGFloat, velocity: CGFloat = 0) {
        self.offset = offset
        self.maximumOffset = maximumOffset
        self.velocity = velocity
    }
}

/// 捲動驅動 Presentation State 的狀態機。
///
/// 這一塊沒有任何公開 API 可用——系統的捲動最小化行為只存在於 `UITabBarController`
/// 上（見 `docs/spikes/0001-objc-interop.md` 的查證），因此方向判定、位移門檻、
/// 速度門檻、回彈偵測與回頂重置全部自理。它是本專案最容易在重構時悄悄壞掉的邏輯，
/// 所以獨立成純值型別，能被單獨驗證。
internal struct TeroTabScrollStateMachine {

    internal struct Configuration {
        internal var behavior: TeroTabBarScrollBehavior
        internal var downwardTranslationThreshold: CGFloat
        internal var upwardTranslationThreshold: CGFloat
        internal var velocityThreshold: CGFloat
        internal var directionLockDistance: CGFloat

        internal init(
            behavior: TeroTabBarScrollBehavior,
            downwardTranslationThreshold: CGFloat = 40,
            upwardTranslationThreshold: CGFloat = 24,
            velocityThreshold: CGFloat = 120,
            directionLockDistance: CGFloat = 8
        ) {
            self.behavior = behavior
            self.downwardTranslationThreshold = downwardTranslationThreshold
            self.upwardTranslationThreshold = upwardTranslationThreshold
            self.velocityThreshold = velocityThreshold
            self.directionLockDistance = directionLockDistance
        }
    }

    internal private(set) var state: TeroTabBarPresentationState = .expanded

    /// 程式呼叫 `.hidden` 進入鎖定；鎖定期間捲動輸入完全不改變狀態（ADR-0004）。
    internal var isLocked = false

    private var lastOffset: CGFloat = 0
    private var lock = TeroScrollDirectionLock()
    private var wasAtBottomOverscroll = false

    internal init() {}

    /// 切換 Tab 或重新解析追蹤對象時使用。
    internal mutating func reset(to state: TeroTabBarPresentationState, offset: CGFloat = 0) {
        self.state = state
        lastOffset = offset
        lock.reset(to: offset)
        wasAtBottomOverscroll = false
    }

    /// 吃進一次取樣，回傳應該生效的狀態。
    @discardableResult
    internal mutating func consume(
        _ sample: TeroTabScrollSample,
        configuration: Configuration
    ) -> TeroTabBarPresentationState {
        guard sample.offset.isFinite, sample.maximumOffset.isFinite else { return state }
        defer { lastOffset = sample.offset }
        guard !isLocked else { return state }
        guard configuration.behavior != .none else {
            reset(to: state, offset: sample.offset)
            return state
        }
        // Layout 期間可能正在拖曳，必須先排除幾何更新，再判斷回頂。
        if sample.geometryChanged {
            reset(to: state, offset: sample.offset)
            return state
        }
        if sample.offset <= 0.5 || sample.maximumOffset <= 0.5 || sample.isRefreshing {
            reset(to: .expanded, offset: max(0, sample.offset))
            return state
        }
        guard sample.isUserDriven else {
            reset(to: state, offset: sample.offset)
            return state
        }
        if sample.offset > sample.maximumOffset + 0.5 {
            wasAtBottomOverscroll = true
            return state
        }
        if wasAtBottomOverscroll {
            reset(to: state, offset: sample.offset)
            return state
        }

        let delta = sample.offset - lastOffset
        guard delta != 0 else { return state }
        // 方向判定與門檻算術由 TeroScrollDirectionLock 提供，頂部 chrome 讀同一份（§26）。
        lock.consume(
            offset: sample.offset,
            delta: delta,
            lockDistance: Self.distance(configuration.directionLockDistance, fallback: 8)
        )
        let translation = lock.translation(at: sample.offset)
        let velocity = sample.velocity.isFinite ? sample.velocity : 0
        let exceedsVelocity = abs(velocity) >= Self.distance(configuration.velocityThreshold, fallback: 120)
        switch lock.direction {
        case .down:
            if delta > 0 && (translation >= Self.distance(configuration.downwardTranslationThreshold, fallback: 40)
                || (exceedsVelocity && velocity > 0)) {
                state = collapsedState(for: configuration.behavior)
            }
        case .up:
            if delta < 0 && (-translation >= Self.distance(configuration.upwardTranslationThreshold, fallback: 24)
                || (exceedsVelocity && velocity < 0)) {
                state = .expanded
            }
        case .none: break
        }
        return state
    }

    private static func distance(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : fallback
    }

    private func collapsedState(for behavior: TeroTabBarScrollBehavior) -> TeroTabBarPresentationState {
        switch behavior {
        case .hideOnScrollDown:
            return .hidden
        case .minimizeOnScrollDown:
            return .minimized
        case .none, .inherit:
            // .inherit 到不了這裡——resolver 在更早的地方就把它換成設定裡的行為。
            return state
        }
    }
}

/// 生效行為的解析。優先順序固定：可見畫面的偏好 → 配置 → 生效行為（計畫書 §38）。
internal struct TeroTabScrollBehaviorResolver {

    internal func resolve(
        preferred: TeroTabBarScrollBehavior?,
        configured: TeroTabBarScrollBehavior,
        style: TeroTabBarStyle
    ) -> TeroTabBarScrollBehavior {
        // `.inherit` 是「沒有偏好」：頁面說 inherit 就交回設定，設定自己說 inherit
        // 就沒有東西可繼承，等同 `.none`。
        let expressed = preferred == .inherit ? nil : preferred
        let resolved = expressed ?? configured
        let requested = resolved == .inherit ? .none : resolved

        // Classic 不支援最小化，降級為隱藏（計畫書 §16）。
        if style == .classic, requested == .minimizeOnScrollDown {
            return .hideOnScrollDown
        }
        return requested
    }
}
