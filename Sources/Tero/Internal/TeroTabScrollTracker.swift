import UIKit

/// 不替換 UIScrollViewDelegate；只將 offset 與幾何觀察送入純狀態機。
internal final class TeroTabScrollTracker {
    internal var configuration = TeroTabScrollStateMachine.Configuration(behavior: .none)
    internal var onStateChange: ((TeroTabBarPresentationState) -> Void)?
    /// 同一份樣本的第二個出口。頂部 chrome 與 Tab Bar 讀同一筆，不各自觀察同一個
    /// scroll view——兩個觀察者會各自算出自己的方向鎖，在邊界上得到不同結論。
    internal var onSample: ((TeroTabScrollSample) -> Void)?
    internal private(set) weak var trackedScrollView: UIScrollView?
    private var machine = TeroTabScrollStateMachine()
    private var observations: [NSKeyValueObservation] = []
    private var geometry: Geometry?
    private var lastTime: CFTimeInterval = 0
    private var lastOffset: CGFloat = 0
    private var suspensionDepth = 0

    private struct Geometry: Equatable {
        var size: CGSize
        var contentSize: CGSize
        var inset: UIEdgeInsets
        init(_ scroll: UIScrollView) {
            size = scroll.bounds.size
            contentSize = scroll.contentSize
            inset = scroll.adjustedContentInset
        }
    }

    internal var isLocked: Bool {
        get { machine.isLocked }
        set { machine.isLocked = newValue }
    }
    internal var state: TeroTabBarPresentationState { machine.state }

    internal func track(_ scrollView: UIScrollView?, resetTo state: TeroTabBarPresentationState) {
        observations.removeAll()
        trackedScrollView = scrollView
        reset(to: state)
        guard let scrollView else { return }
        observations = [
            scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                self?.handleOffsetChange(of: scroll)
            },
            scrollView.observe(\.contentSize, options: [.new]) { [weak self] _, _ in self?.rebase() },
            scrollView.observe(\.adjustedContentInset, options: [.new]) { [weak self] _, _ in self?.rebase() }
        ]
    }

    /// Tero 自己造成的 inset／layout 變更整段暫停，不能只忽略下一筆 KVO。
    internal func withoutTracking(_ update: () -> Void) {
        suspensionDepth += 1
        update()
        suspensionDepth -= 1
        rebase()
    }

    internal func reset(to state: TeroTabBarPresentationState) {
        lastOffset = trackedScrollView.map(Self.offset) ?? 0
        lastTime = CACurrentMediaTime()
        geometry = trackedScrollView.map(Geometry.init)
        machine.reset(to: state, offset: lastOffset)
    }

    private func rebase() { reset(to: state) }

    private func handleOffsetChange(of scrollView: UIScrollView) {
        guard suspensionDepth == 0 else { return }
        let now = CACurrentMediaTime()
        let offset = Self.offset(scrollView)
        let nextGeometry = Geometry(scrollView)
        let changed = geometry != nextGeometry
        let elapsed = now - lastTime
        let velocity: CGFloat
        if scrollView.isDragging {
            velocity = -scrollView.panGestureRecognizer.velocity(in: scrollView).y
        } else if scrollView.isDecelerating, elapsed > 0.001, elapsed < 0.25, !changed {
            velocity = (offset - lastOffset) / elapsed
        } else {
            velocity = 0
        }
        var sample = TeroTabScrollSample(
            offset: offset,
            maximumOffset: max(0, scrollView.contentSize.height - scrollView.bounds.height
                + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom),
            velocity: velocity
        )
        sample.isUserDriven = scrollView.isDragging || scrollView.isDecelerating
        sample.isRefreshing = scrollView.refreshControl?.isRefreshing == true
        sample.geometryChanged = changed
        geometry = nextGeometry
        lastOffset = offset
        lastTime = now
        onSample?(sample)
        let previous = machine.state
        let next = machine.consume(sample, configuration: configuration)
        if next != previous { onStateChange?(next) }
    }

    private static func offset(_ scroll: UIScrollView) -> CGFloat {
        scroll.contentOffset.y + scroll.adjustedContentInset.top
    }
}
