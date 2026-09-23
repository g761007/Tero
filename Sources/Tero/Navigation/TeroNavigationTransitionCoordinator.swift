import UIKit

/// 驅動 stack 轉場的動畫器。持有唯一一段正在飛的轉場。
///
/// 用 `UIViewPropertyAnimator` 而非 `UIView.animate`：它可中斷、可反轉、可從目前狀態接續，
/// 這三件事 Phase 3 的互動式返回都需要（§13）。
///
/// **settle-forward**（ADR-0014）：新的 stack 變更抵達時，正在跑的那一段立刻結算到自己的
/// 終點，而不是被丟棄。丟棄會留下沒收到 `didMove` 的 child——1.x 的 presentation state 是
/// 純量所以可以丟，stack 的中途狀態帶成對的 containment 副作用，不能。
internal final class TeroNavigationTransitionCoordinator {

    internal enum Operation {
        case push
        case pop

        /// 進入的那一個從哪個方向來，以容器寬度的倍數表示。
        fileprivate var incomingOffsetRatio: CGFloat { self == .push ? 1 : -TeroNavigationTransitionCoordinator.parallaxRatio }
        /// 離開的那一個往哪個方向去。
        fileprivate var outgoingOffsetRatio: CGFloat { self == .push ? -TeroNavigationTransitionCoordinator.parallaxRatio : 1 }
    }

    /// 離開的那一頁只走一小段，讓兩頁看起來是疊著的而不是各走各的（§12）。
    fileprivate static let parallaxRatio: CGFloat = 0.3

    private var animator: UIViewPropertyAnimator?
    private var settleHandler: (() -> Void)?

    internal var isRunning: Bool { animator != nil }

    /// 跑一段轉場；結束時呼叫 `settle`。
    ///
    /// 呼叫前必須先讓上一段結算完畢（`settleRunningTransition()`），這個型別不排隊。
    /// `alongside` 與兩頁的位移放進同一個 animator：容器用它讓 chrome 跟著轉場走（issue #91）。
    internal func run(
        operation: Operation,
        from outgoing: UIViewController?,
        to incoming: UIViewController?,
        in containerView: UIView,
        duration: TimeInterval,
        alongside: (() -> Void)? = nil,
        settle: @escaping () -> Void
    ) {
        let width = containerView.bounds.width
        guard width > 0, incoming !== outgoing else {
            settle()
            return
        }

        incoming?.view.transform = CGAffineTransform(translationX: width * operation.incomingOffsetRatio, y: 0)
        outgoing?.view.transform = .identity

        // pop 時離開的那一頁要蓋在上面，否則它會被進入的那一頁遮住。
        if operation == .pop, let outgoingView = outgoing?.viewIfLoaded {
            containerView.bringSubviewToFront(outgoingView)
        }

        settleHandler = settle
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 1) {
            incoming?.view.transform = .identity
            outgoing?.view.transform = CGAffineTransform(translationX: width * operation.outgoingOffsetRatio, y: 0)
            alongside?()
        }
        animator.addCompletion { [weak self] _ in
            outgoing?.view.transform = .identity
            incoming?.view.transform = .identity
            guard let self else { return }
            let handler = self.settleHandler
            self.animator = nil
            self.settleHandler = nil
            handler?()
        }
        self.animator = animator
        animator.startAnimation()
    }

    // MARK: - 互動式

    private var interactive: (outgoing: UIViewController?, incoming: UIViewController?, width: CGFloat)?

    internal var isInteractive: Bool { interactive != nil }

    /// 開始一段由手勢驅動的返回。**不提交任何 stack 變更**——提交發生在 finish 判定成立時
    /// （ADR-0014），因此取消之後 `viewControllers` 根本沒被動過。
    internal func beginInteractive(
        from outgoing: UIViewController?,
        to incoming: UIViewController?,
        in containerView: UIView
    ) {
        let width = containerView.bounds.width
        incoming?.view.transform = CGAffineTransform(translationX: -width * Self.parallaxRatio, y: 0)
        outgoing?.view.transform = .identity
        if let outgoingView = outgoing?.viewIfLoaded {
            containerView.bringSubviewToFront(outgoingView)
        }
        interactive = (outgoing, incoming, width)
    }

    /// 以 0…1 的進度更新兩頁的位置。1 表示手指已經把上一頁完全拉開。
    internal func updateInteractive(progress: CGFloat) {
        guard let interactive else { return }
        let clamped = min(max(progress, 0), 1)
        interactive.outgoing?.view.transform = CGAffineTransform(translationX: interactive.width * clamped, y: 0)
        interactive.incoming?.view.transform = CGAffineTransform(
            translationX: -interactive.width * Self.parallaxRatio * (1 - clamped), y: 0
        )
    }

    /// 結束手勢。`finish` 為 true 時跑到終點，false 時退回起點。
    ///
    /// 兩條路徑都會呼叫 `completion`；呼叫端據此決定要提交還是要把 appearance 反向補回去。
    internal func endInteractive(
        finish: Bool,
        progress: CGFloat,
        duration: TimeInterval,
        alongside: (() -> Void)? = nil,
        completion: @escaping () -> Void
    ) {
        guard let interactive else {
            completion()
            return
        }
        self.interactive = nil

        let remaining = max(0.05, duration * Double(finish ? (1 - progress) : progress))
        let animator = UIViewPropertyAnimator(duration: remaining, dampingRatio: 1) {
            if finish {
                interactive.outgoing?.view.transform = CGAffineTransform(translationX: interactive.width, y: 0)
                interactive.incoming?.view.transform = .identity
            } else {
                interactive.outgoing?.view.transform = .identity
                interactive.incoming?.view.transform = CGAffineTransform(
                    translationX: -interactive.width * Self.parallaxRatio, y: 0
                )
            }
            alongside?()
        }
        animator.addCompletion { [weak self] _ in
            interactive.outgoing?.view.transform = .identity
            interactive.incoming?.view.transform = .identity
            guard let self else { return }
            let handler = self.settleHandler
            self.animator = nil
            self.settleHandler = nil
            handler?()
            completion()
        }
        self.animator = animator
        animator.startAnimation()
    }

    /// 中止手勢段並把兩頁的位置還原。
    ///
    /// 互動段不適用 settle-forward：手指還在螢幕上，它沒有「自己的終點」可以結算過去。
    /// 由於它從未提交，中止是安全的——呼叫端負責把 appearance 反向補回去。
    internal func abortInteractive() {
        guard let interactive else { return }
        self.interactive = nil
        interactive.outgoing?.view.transform = .identity
        interactive.incoming?.view.transform = .identity
    }

    /// 把正在跑的那一段立刻結算到終點。沒有東西在跑時什麼都不做。
    ///
    /// 用 `stopAnimation(false)` 取回控制權再 `finishAnimation(at: .end)`，讓 completion
    /// 照常跑——結算的內容（`didMove`、`removeFromParent`、appearance 的 end）不能跳過。
    internal func settleRunningTransition() {
        guard let animator else { return }
        if animator.state == .active {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .end)
        } else {
            // 已經停在某處：completion 不會再來，自己補上。
            let handler = settleHandler
            self.animator = nil
            settleHandler = nil
            handler?()
        }
    }
}
