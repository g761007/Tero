import UIKit

/// 選取轉場的協調器。Consumer 不應依賴此型別（計畫書 §52）。
///
/// 這裡只回答「怎麼從 A 到 B」。「A 與 B 在哪」是 layout engine 的事——
/// 兩者刻意分開，版面才不會被動畫的中間狀態污染。
///
/// 協調器同時是整段轉場的**時鐘**：指示器的 frame 由 `UIViewPropertyAnimator` 帶，
/// 其餘無法直接動畫的東西（tint、標題顏色、provider 的進度）則靠 `onProgress`
/// 每幀取得同一段轉場的進度，兩者因此不會各走各的。
internal final class TeroTabSelectionTransitionCoordinator {

    /// 一次轉場的終點。
    internal struct Target: Equatable {
        internal var frame: CGRect
        internal var cornerRadius: CGFloat
        /// 目標格位。`nil` 代表沒有選取，用來在格位消失時仍能描述狀態。
        internal var slot: Int?

        internal init(frame: CGRect, cornerRadius: CGFloat, slot: Int?) {
            self.frame = frame
            self.cornerRadius = cornerRadius
            self.slot = slot
        }
    }

    internal var motion = TeroTabMotionConfiguration()

    /// 本段轉場的進度（0…1）。每幀回報一次，結束時保證以 1 收尾。
    internal var onSegmentStart: ((Int?, Bool) -> Void)?
    private var revision = 0
    private weak var pulseView: UIView?

    internal var onProgress: ((CGFloat) -> Void)?

    /// 目前正在前往、或已經停住的終點。
    internal private(set) var target: Target?

    /// `allowsInterruptibleTransition` 為 false 時排在後面的終點。
    private var pendingTarget: Target?

    /// 是否有一段轉場還沒落定。
    ///
    /// 用 `state` 而不是 `isRunning`：後者在某些狀態下會回報 false，
    /// 但動畫器仍持有這個指示器的屬性，此時把它當成閒置會導致重複啟動。
    internal var isRunning: Bool {
        animator?.state == .active
    }

    /// 本段轉場的水平位移。0 代表這一段沒有橫向移動（例如展開↔最小化）。
    internal var segmentTravel: CGFloat {
        segmentEndFrame.midX - segmentStartFrame.midX
    }

    private weak var indicator: UIView?
    private var animator: UIViewPropertyAnimator?
    private var displayLink: CADisplayLink?
    private var pulseAnimators: [UIViewPropertyAnimator] = []
    private var segmentStartFrame: CGRect = .zero
    private var segmentEndFrame: CGRect = .zero

    /// `CADisplayLink` 會強參考 target，直接掛協調器會成環。
    private final class DisplayLinkProxy: NSObject {
        weak var coordinator: TeroTabSelectionTransitionCoordinator?
        @objc func tick() { coordinator?.reportProgress() }
    }

    private let displayLinkProxy = DisplayLinkProxy()

    internal init() {
        displayLinkProxy.coordinator = self
    }

    deinit {
        displayLink?.invalidate()
    }

    internal func attach(to indicator: UIView) {
        self.indicator = indicator
    }

    // MARK: - Transitions

    /// 把指示器帶到 `newTarget`。
    ///
    /// 轉場進行中再次呼叫預設會**從目前畫面上的位置**直接轉向，不排隊（補充規格 §13）。
    internal func move(to newTarget: Target, animated: Bool) {
        guard let indicator else { return }

        // 目標沒變而動畫還在跑：讓它跑完。每次 layout 都重啟會讓彈簧永遠到不了終點。
        // 已經停在目標上也不必再跑一次——presentation state 變更會先用舊幾何
        // 叫一次、版面跑完再叫一次，沒有這道守門就會平白啟動一段空動畫。
        if target == newTarget, isRunning || indicator.frame == newTarget.frame { return }

        cancelPulse()

        // 減少動態效果：協調器一律就地就位，不跑彈簧。
        // 要不要改以交叉淡入交棒是 Bar 的事——淡入淡出必須連 Icon 一起做，
        // 只淡外框會看起來像外框自己在閃（補充規格 §17）。
        guard animated, !TeroAccessibility.isReduceMotionEnabled() else {
            settle(at: newTarget)
            onSegmentStart?(newTarget.slot, false)
            apply(newTarget, to: indicator)
            onProgress?(1)
            return
        }

        if isRunning, !motion.allowsInterruptibleTransition {
            // 逃生口：保留「先讓目前這段跑完」的舊行為。
            pendingTarget = newTarget
            return
        }

        // 停在目前的 presentation 值，新的一段就從畫面上看到的位置起跑。
        let previousRevision = revision
        stopAnimator()
        guard revision == previousRevision else { return }
        revision += 1
        let token = revision
        target = newTarget
        pendingTarget = nil
        indicator.transform = .identity
        segmentStartFrame = indicator.frame
        segmentEndFrame = newTarget.frame

        let animator = UIViewPropertyAnimator(
            duration: TeroTabSpring.nominalDuration(for: motion),
            timingParameters: TeroTabSpring.timingParameters(for: motion)
        )
        // 一律可中斷：UIKit 的 `isInterruptible = false` 連 `stopAnimation` 都不允許，
        // 而「不可中斷」在這裡的語意是排隊政策（見上面的逃生口），不是禁止停止。
        animator.isInterruptible = true
        animator.isUserInteractionEnabled = true
        animator.addAnimations { [weak self] in
            guard let self, let indicator = self.indicator else { return }
            self.apply(newTarget, to: indicator)
        }
        animator.addCompletion { [weak self] position in
            guard let self, self.revision == token else { return }
            self.animator = nil
            self.stopDisplayLink()
            guard position == .end else { return }
            self.onProgress?(1)
            guard self.revision == token else { return }
            self.drainPendingTarget()
        }
        self.animator = animator
        startDisplayLink()
        // 每一段都至少回報起點與終點，訂閱者才不必猜第一幀什麼時候到。
        onSegmentStart?(newTarget.slot, true)
        guard revision == token else { return }
        onProgress?(0)
        guard revision == token else { return }
        animator.startAnimation()
    }

    /// 放棄目前的轉場，指示器停在畫面上當下的位置。
    internal func cancel() {
        revision += 1
        stopAnimator()
        cancelPulse()
        pendingTarget = nil
    }

    /// 重複點擊選取中的 Tab 的回饋：膠囊輕輕脹一下再收回（補充規格 §12）。
    ///
    /// 轉場進行中不插入回饋——那會和位移動畫搶同一個 `transform`。
    internal func pulse(on indicator: UIView) {
        guard !isRunning else { return }
        guard !TeroAccessibility.isReduceMotionEnabled() else { return }

        cancelPulse()
        pulseView = indicator
        let half = motion.reselectDuration / 2
        let expand = UIViewPropertyAnimator(duration: half, dampingRatio: 0.7) {
            indicator.transform = CGAffineTransform(scaleX: 1.07, y: 1.07)
        }
        expand.addCompletion { [weak self] position in
            guard let self, position == .end, let indicator = self.pulseView else { return }
            let settle = UIViewPropertyAnimator(duration: half, dampingRatio: 0.55) {
                indicator.transform = .identity
            }
            self.pulseAnimators = [settle]
            settle.startAnimation()
        }
        pulseAnimators = [expand]
        expand.startAnimation()
    }

    private func cancelPulse() {
        for animator in pulseAnimators where animator.state == .active {
            animator.stopAnimation(true)
        }
        pulseAnimators = []
        pulseView?.transform = .identity
        pulseView = nil
    }

    /// 忘掉目前的終點。格位重建之後舊的 frame 不再有意義，
    /// 下一次定位要當成第一次（直接就位，不要從舊位置飛過來）。
    internal func reset() {
        cancel()
        target = nil
    }

    // MARK: - Progress

    /// 本段轉場目前的進度。
    ///
    /// 優先以指示器 presentation layer 的水平位移比例推導，進度因此與彈簧
    /// 看到的曲線一致；水平幾乎沒有位移時（例如展開↔最小化）退回時間比例。
    private func currentProgress() -> CGFloat {
        guard let animator, animator.state == .active else { return 1 }
        let travel = segmentEndFrame.midX - segmentStartFrame.midX
        guard abs(travel) > 1, let presentation = indicator?.layer.presentation() else {
            return clamped(animator.fractionComplete)
        }
        return clamped((presentation.frame.midX - segmentStartFrame.midX) / travel)
    }

    private func reportProgress() {
        onProgress?(currentProgress())
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func startDisplayLink() {
        stopDisplayLink()
        guard onProgress != nil else { return }
        let link = CADisplayLink(target: displayLinkProxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - Internals

    /// 結束目前這段：停動畫、清排隊、記下新的終點。
    private func settle(at newTarget: Target) {
        revision += 1
        stopAnimator()
        pendingTarget = nil
        target = newTarget
    }

    private func drainPendingTarget() {
        guard let pending = pendingTarget else { return }
        pendingTarget = nil
        move(to: pending, animated: true)
    }

    private func stopAnimator() {
        let progress = currentProgress()
        let frame = indicator?.layer.presentation()?.frame
        let corner = indicator?.layer.presentation()?.cornerRadius
        stopDisplayLink()
        guard let animator else { return }
        self.animator = nil
        if animator.state == .active { animator.stopAnimation(true) }
        if let frame { indicator?.frame = frame }
        if let corner { indicator?.layer.cornerRadius = corner }
        onProgress?(progress)
    }

    private func apply(_ target: Target, to indicator: UIView) {
        indicator.frame = target.frame
        indicator.layer.cornerRadius = target.cornerRadius
    }

    /// 減少動態效果在執行中被打開時，讓目前這段立刻落定。
    ///
    /// 只改設定不做這件事的話，已經在飛的彈簧會照樣飛完，
    /// 使用者剛打開的設定要等下一次切換才看得到效果。
    internal func settleImmediately() {
        guard let indicator, let target else { return }
        stopAnimator()
        cancelPulse()
        pendingTarget = nil
        apply(target, to: indicator)
        onProgress?(1)
    }
}
