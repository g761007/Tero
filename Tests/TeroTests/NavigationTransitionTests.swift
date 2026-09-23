import XCTest
import UIKit
@testable import Tero

/// Phase 2：轉場引擎。
///
/// 這裡驗的是 Phase 1 碰不到的那一半——commit 與 settle 之間真的隔著時間之後，
/// ADR-0014 的「stack 同步提交、畫面落後」與 settle-forward 才會被執行到。
final class NavigationTransitionTests: TeroTabBarControllerTestCase {

    private func page(_ name: String) -> LifecycleSpyViewController {
        LifecycleSpyViewController(name: name, log: log)
    }

    /// 轉場時間刻意拉長，讓「轉場進行中」的斷言不必跟時鐘賽跑。
    private func presented(root: UIViewController, duration: TimeInterval = 1.0) -> TeroNavigationContainer {
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = duration
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        return container
    }

    private func waitForSettle(_ container: TeroNavigationContainer) {
        waitUntil("轉場結算") { container.transitionState == .idle }
    }

    // MARK: - 同步提交，畫面落後

    func test_push_commitsTheStackBeforeTheAnimationFinishes() {
        let container = presented(root: page("root"))
        let detail = page("detail")

        container.pushViewController(detail, animated: true)

        XCTAssertIdentical(container.topViewController, detail, "陣列在 return 之前就已變更")
        XCTAssertEqual(container.viewControllers.count, 2)
        XCTAssertEqual(container.transitionState, .pushing, "但轉場還在跑")
        waitForSettle(container)
    }

    func test_pop_removesFromTheStackBeforeTheAnimationFinishes() {
        let root = page("root")
        let container = presented(root: root)
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        let popped = container.popViewController(animated: true)

        XCTAssertIdentical(popped, detail)
        XCTAssertIdentical(container.topViewController, root)
        XCTAssertEqual(container.transitionState, .popping)
        waitForSettle(container)
    }

    func test_duringAPopTransition_thePoppedOneIsStillAChildButNoLongerInViewControllers() {
        let container = presented(root: page("root"))
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        container.popViewController(animated: true)

        XCTAssertFalse(container.viewControllers.contains { $0 === detail }, "已離開 stack")
        XCTAssertTrue(container.children.contains { $0 === detail }, "但還沒離開 children——結算才移除")
        waitForSettle(container)
        XCTAssertFalse(container.children.contains { $0 === detail }, "結算後才離開")
    }

    // MARK: - settle-forward

    func test_pushWhileATransitionRuns_settlesTheRunningOneThenRunsTheNewOne() {
        let container = presented(root: page("root"))
        let first = page("first")
        let second = page("second")

        container.pushViewController(first, animated: true)
        container.pushViewController(second, animated: true)

        XCTAssertEqual(container.viewControllers.count, 3)
        XCTAssertIdentical(container.topViewController, second)
        waitForSettle(container)
        XCTAssertIdentical(first.parent, container, "被早結算的那一個仍然完整留在 stack 裡")
    }

    func test_rapidPush_endsWithEveryViewControllerOnTheStackInCallOrder() {
        let container = presented(root: page("root"), duration: 0.6)
        let pages = (1...4).map { page("p\($0)") }

        for p in pages { container.pushViewController(p, animated: true) }

        XCTAssertEqual(container.viewControllers.count, 5)
        XCTAssertIdentical(container.topViewController, pages.last)
        waitForSettle(container)
        for p in pages {
            XCTAssertIdentical(p.parent, container, "\(p.name) 應該仍是 child")
        }
    }

    func test_rapidPush_givesEveryIntermediatePageAPairedAppearance() {
        let container = presented(root: page("root"), duration: 0.6)
        log.reset()
        let middle = page("middle")

        container.pushViewController(middle, animated: true)
        container.pushViewController(page("last"), animated: true)
        waitForSettle(container)

        let appears = log.events.filter { $0.hasPrefix("middle.") }
        XCTAssertTrue(appears.contains("middle.willAppear"), "settle-forward 不能吞掉中間頁的 appearance")
        XCTAssertTrue(appears.contains("middle.didAppear"))
        XCTAssertTrue(appears.contains("middle.willDisappear"), "而且要成對——這是不用丟棄的理由")
        XCTAssertTrue(appears.contains("middle.didDisappear"))
    }

    func test_aTransitionThatWasSettledEarly_doesNotLaterOverwriteTheStack() {
        let container = presented(root: page("root"))
        container.pushViewController(page("first"), animated: true)
        let second = page("second")

        container.pushViewController(second, animated: true)
        waitForSettle(container)

        XCTAssertIdentical(container.topViewController, second, "舊轉場的 completion 不該把 top 改回去")
        XCTAssertEqual(container.viewControllers.count, 3)
    }

    func test_popDuringItsOwnPushTransition_endsAtTheViewControllerBelow() {
        let root = page("root")
        let container = presented(root: root)
        let detail = page("detail")

        container.pushViewController(detail, animated: true)
        let popped = container.popViewController(animated: true)

        XCTAssertIdentical(popped, detail)
        XCTAssertIdentical(container.topViewController, root)
        waitForSettle(container)
        XCTAssertNil(detail.parent, "一來一回之後那一頁要完全離開")
    }

    // MARK: - 無動畫路徑不受影響

    func test_unanimatedPush_settlesSynchronously() {
        let container = presented(root: page("root"))

        container.pushViewController(page("detail"), animated: false)

        XCTAssertEqual(container.transitionState, .idle, "animated: false 不啟動轉場")
    }

    func test_pushWhileOffscreen_settlesSynchronouslyEvenWhenAnimated() {
        let container = TeroNavigationContainer(rootViewController: page("root"))

        container.pushViewController(page("detail"), animated: true)

        XCTAssertEqual(container.transitionState, .idle, "沒有 window 就沒有動畫可跑")
    }
}
