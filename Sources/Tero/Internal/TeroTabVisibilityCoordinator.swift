import UIKit

/// 可見度是數值時間軸，render 是幾何的唯一寫入者。
/// 不把 UIView 的 model frame 當成動畫當下的 frame，也不在每幀重啟 animator。
internal final class TeroTabVisibilityCoordinator {
    internal private(set) var progress: CGFloat = 0
    internal private(set) var target: CGFloat = 0
    internal var onUpdate: ((CGFloat, Bool) -> Void)?
    internal var isRunning: Bool { displayLink != nil }
    private var start: CGFloat = 0
    private var startTime: CFTimeInterval = 0
    private var duration: TimeInterval = 0
    private var revision = 0
    private var displayLink: CADisplayLink?
    private final class Proxy: NSObject {
        weak var owner: TeroTabVisibilityCoordinator?
        @objc func tick(_ link: CADisplayLink) { owner?.tick(at: link.timestamp) }
    }
    private let proxy = Proxy()
    internal init(progress: CGFloat = 0) {
        self.progress = progress
        self.target = progress
        proxy.owner = self
    }
    deinit { displayLink?.invalidate() }

    internal func move(to value: CGFloat, duration: TimeInterval, animated: Bool) {
        let value = value.isFinite ? min(max(value, 0), 1) : 0
        if value == target, isRunning, animated { return }
        revision += 1
        let token = revision
        displayLink?.invalidate()
        displayLink = nil
        target = value
        start = progress
        self.duration = duration.isFinite ? max(0, duration) : 0.28
        guard animated, !TeroAccessibility.isReduceMotionEnabled(), self.duration > 0, start != target else {
            progress = target
            onUpdate?(progress, false)
            return
        }
        startTime = CACurrentMediaTime()
        onUpdate?(progress, true)
        guard revision == token else { return }
        let link = CADisplayLink(target: proxy, selector: #selector(Proxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    internal func settle() { move(to: target, duration: 0, animated: false) }

    private func tick(at time: CFTimeInterval) {
        let t = min(max((time - startTime) / duration, 0), 1)
        // Smoothstep：端點速度為零，單調且不會超過可操作幾何的範圍。
        let eased = CGFloat(t * t * (3 - 2 * t))
        progress = start + (target - start) * eased
        if t >= 1 {
            progress = target
            displayLink?.invalidate()
            displayLink = nil
        }
        onUpdate?(progress, true)
    }
}
