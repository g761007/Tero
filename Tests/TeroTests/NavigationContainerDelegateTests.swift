import XCTest
import UIKit
@testable import Tero

/// 記下事件與當下的 stack，時點才驗得到。
private final class NavigationSpy: NSObject, TeroNavigationContainerDelegate {
    private(set) var events: [String] = []
    private(set) var stackDepthAtWillShow: [Int] = []

    /// 記錄從呼叫之後開始算；鋪陳階段的事件不是測試要看的。
    func reset() {
        events.removeAll()
        stackDepthAtWillShow.removeAll()
    }

    func teroNavigationContainer(
        _ container: TeroNavigationContainer,
        willShow viewController: UIViewController,
        animated: Bool
    ) {
        events.append("will(\(viewController.title ?? "?"),\(animated))")
        stackDepthAtWillShow.append(container.viewControllers.count)
    }

    func teroNavigationContainer(
        _ container: TeroNavigationContainer,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        events.append("did(\(viewController.title ?? "?"),\(animated))")
    }
}

/// C6：`willShow`／`didShow` 的時點就是 commit 與 settle（ADR-0014）。
final class NavigationContainerDelegateTests: TeroTabBarControllerTestCase {

    private func page(_ name: String) -> UIViewController {
        let controller = UIViewController()
        controller.title = name
        return controller
    }

    private func presented(_ root: UIViewController) -> (TeroNavigationContainer, NavigationSpy) {
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = 0.2
        let spy = NavigationSpy()
        container.delegate = spy
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        return (container, spy)
    }

    // MARK: - commit 與 settle

    func test_pushWithoutAnimation_sendsWillShowThenDidShowBeforeItReturns() {
        let (container, spy) = presented(page("root"))

        container.pushViewController(page("detail"), animated: false)

        XCTAssertEqual(spy.events, ["will(detail,false)", "did(detail,false)"],
                       "無動畫時 commit 與 settle 是同一刻，兩個事件在 return 之前依序送出")
    }

    func test_animatedPush_sendsWillShowBeforeItReturnsAndDidShowOnlyAfterTheAnimation() {
        let (container, spy) = presented(page("root"))

        container.pushViewController(page("detail"), animated: true)

        XCTAssertEqual(spy.events, ["will(detail,true)"],
                       "willShow 落在 commit：方法 return 之前就送出，不等動畫")

        waitUntil("轉場結算") { container.transitionState == .idle }

        XCTAssertEqual(spy.events, ["will(detail,true)", "did(detail,true)"])
    }

    func test_willShowSeesTheNewStackAlready() {
        let (container, spy) = presented(page("root"))

        container.pushViewController(page("detail"), animated: true)

        XCTAssertEqual(spy.stackDepthAtWillShow, [2],
                       "commit 的定義就是 stack 已經是新值——delegate 看到的必須是新的")
    }

    func test_replacingTheStackWithoutChangingTheTopSendsNothing() {
        let root = page("root")
        let (container, spy) = presented(root)
        let middle = page("middle")
        container.pushViewController(middle, animated: false)
        let top = container.topViewController
        spy.reset()

        container.setViewControllers([root, middle], animated: false)

        XCTAssertIdentical(container.topViewController, top, "前提：最上層沒有換")
        XCTAssertEqual(spy.events, [], "最上層沒換就沒有「顯示了誰」這回事")
    }

    // MARK: - 互動式返回

    func test_cancelledInteractivePop_sendsNeitherEvent() {
        let (container, spy) = presented(page("root"))
        container.pushViewController(page("detail"), animated: false)
        spy.reset()

        XCTAssertTrue(container.beginInteractivePop())
        container.updateInteractivePop(progress: 0.3)
        container.endInteractivePop(progress: 0.3, velocity: 0)
        waitUntil("取消結算") { container.transitionState == .idle }

        XCTAssertEqual(spy.events, [],
                       "取消的手勢 stack 一個字都沒變過；發事件就是在報告一次沒發生的切換")
    }

    func test_finishedInteractivePop_sendsWillShowAtTheFinishDecisionAndDidShowAtTheEnd() {
        let (container, spy) = presented(page("root"))
        container.pushViewController(page("detail"), animated: false)
        spy.reset()

        XCTAssertTrue(container.beginInteractivePop())
        container.updateInteractivePop(progress: 0.8)
        container.endInteractivePop(progress: 0.8, velocity: 0)

        XCTAssertEqual(spy.events, ["will(root,true)"],
                       "提交落在 finish 判定成立的那一刻，不是動畫結束時")

        waitUntil("完成結算") { container.transitionState == .idle }

        XCTAssertEqual(spy.events, ["will(root,true)", "did(root,true)"])
    }
}
