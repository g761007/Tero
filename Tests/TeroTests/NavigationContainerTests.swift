import XCTest
import UIKit
@testable import Tero

/// 在建立 chrome 的那一刻記下它找到的容器。
private final class ContainerLookupPage: UIViewController, TeroNavigationChromeProviding {
    private(set) weak var containerWhileMakingChrome: TeroNavigationContainer?
    func makeTeroNavigationChromeView() -> UIView {
        containerWhileMakingChrome = teroNavigationContainer
        return UIView()
    }
    var teroNavigationChromeHeight: CGFloat { 44 }
}

/// Phase 1：stack、containment、無動畫的 push／pop／set。
///
/// 測試名就是規格，與 `SetTabsTests` 同一種寫法。轉場、事件面與 interactive pop
/// 分屬 Phase 2／3，不在這裡。
final class NavigationContainerTests: TeroTabBarControllerTestCase {

    private func page(_ name: String) -> LifecycleSpyViewController {
        LifecycleSpyViewController(name: name, log: log)
    }

    /// 讓容器真正上螢幕，appearance 事件才會發生。
    private func present(_ container: TeroNavigationContainer) {
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
    }

    // MARK: - 空 stack 與 initializer（B10）

    func test_emptyContainer_hasNoViewControllers() {
        let container = TeroNavigationContainer()

        XCTAssertTrue(container.viewControllers.isEmpty)
        XCTAssertNil(container.topViewController)
        XCTAssertNil(container.rootViewController)
        XCTAssertTrue(reportedDiagnostics.isEmpty, "空 stack 是合法狀態，不該回報診斷")
    }

    func test_initWithRootViewController_putsItAtBothEndsOfTheStack() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)

        XCTAssertEqual(container.viewControllers.count, 1)
        XCTAssertIdentical(container.topViewController, root)
        XCTAssertIdentical(container.rootViewController, root)
        XCTAssertIdentical(root.parent, container)
    }

    func test_initWithRootViewController_doesNotLoadAnyView() {
        let root = page("root")
        _ = TeroNavigationContainer(rootViewController: root)

        XCTAssertNil(root.viewIfLoaded, "initializer 走內部安裝路徑，不該載入 view")
        XCTAssertTrue(log.events.isEmpty, "也不該發出任何 appearance 事件")
    }

    // MARK: - Push

    func test_push_appendsToTheStackAndBecomesTop() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        let detail = page("detail")

        container.pushViewController(detail, animated: false)

        XCTAssertEqual(container.viewControllers.count, 2)
        XCTAssertIdentical(container.topViewController, detail)
        XCTAssertIdentical(container.rootViewController, container.viewControllers.first)
    }

    func test_push_makesTheViewControllerAChild() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        let detail = page("detail")

        container.pushViewController(detail, animated: false)

        XCTAssertIdentical(detail.parent, container)
        XCTAssertTrue(container.children.contains { $0 === detail })
    }

    func test_pushingTheSameViewControllerTwice_secondCallIsANoOpAndReportsDiagnostic() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        container.pushViewController(detail, animated: false)

        XCTAssertEqual(container.viewControllers.count, 2, "第二次 push 不該改變 stack")
        XCTAssertEqual(reportedDiagnostics.count, 1)
    }

    func test_pushingAViewControllerAlreadyLowerInTheStack_isANoOpAndReportsDiagnostic() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)
        container.pushViewController(page("detail"), animated: false)

        container.pushViewController(root, animated: false)

        XCTAssertEqual(container.viewControllers.count, 2)
        XCTAssertEqual(reportedDiagnostics.count, 1)
    }

    func test_pushingAViewControllerOwnedByAnotherParent_isANoOpAndReportsDiagnostic() {
        let other = TeroNavigationContainer(rootViewController: page("otherRoot"))
        let borrowed = other.topViewController!
        let container = TeroNavigationContainer(rootViewController: page("root"))

        container.pushViewController(borrowed, animated: false)

        XCTAssertEqual(container.viewControllers.count, 1)
        XCTAssertIdentical(borrowed.parent, other, "原本的容器仍然持有它")
        XCTAssertEqual(reportedDiagnostics.count, 1)
    }

    // MARK: - Pop

    func test_pop_returnsTheRemovedOneAndRestoresTheOneBelow() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        let popped = container.popViewController(animated: false)

        XCTAssertIdentical(popped, detail)
        XCTAssertIdentical(container.topViewController, root)
        XCTAssertEqual(container.viewControllers.count, 1)
    }

    func test_pop_detachesTheRemovedViewController() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        container.popViewController(animated: false)

        XCTAssertNil(detail.parent, "結算之後才離開 children，但 Phase 1 沒有動畫，兩者同時發生")
        XCTAssertFalse(container.children.contains { $0 === detail })
    }

    func test_popOnSingleEntryStack_returnsNilAndLeavesTheStackAlone() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)

        let popped = container.popViewController(animated: false)

        XCTAssertNil(popped, "pop 永遠不會製造空 stack")
        XCTAssertIdentical(container.topViewController, root)
        XCTAssertTrue(reportedDiagnostics.isEmpty, "這不是錯誤，不該回報診斷")
    }

    func test_popOnEmptyStack_returnsNilAndReportsNoDiagnostic() {
        let container = TeroNavigationContainer()

        let popped = container.popViewController(animated: false)

        XCTAssertNil(popped)
        XCTAssertTrue(reportedDiagnostics.isEmpty)
    }

    func test_popToRoot_leavesOnlyTheRoot() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)
        let middle = page("middle")
        let top = page("top")
        container.pushViewController(middle, animated: false)
        container.pushViewController(top, animated: false)

        container.popToRootViewController(animated: false)

        XCTAssertEqual(container.viewControllers.count, 1)
        XCTAssertIdentical(container.topViewController, root)
        XCTAssertNil(middle.parent, "中間那些也要離開 children")
        XCTAssertNil(top.parent)
    }

    func test_popToRootWhenAlreadyAtRoot_isASilentNoOp() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)

        container.popToRootViewController(animated: false)

        XCTAssertIdentical(container.topViewController, root)
        XCTAssertTrue(reportedDiagnostics.isEmpty)
    }

    // MARK: - setViewControllers

    func test_setViewControllers_replacesTheWholeStack() {
        let container = TeroNavigationContainer(rootViewController: page("old"))
        let a = page("a"), b = page("b")

        container.setViewControllers([a, b], animated: false)

        XCTAssertEqual(container.viewControllers.count, 2)
        XCTAssertIdentical(container.rootViewController, a)
        XCTAssertIdentical(container.topViewController, b)
    }

    func test_setViewControllers_detachesTheOnesThatLeft() {
        let old = page("old")
        let container = TeroNavigationContainer(rootViewController: old)

        container.setViewControllers([page("new")], animated: false)

        XCTAssertNil(old.parent)
    }

    func test_setViewControllers_empty_isLegalAndClearsTheStack() {
        let container = TeroNavigationContainer(rootViewController: page("root"))

        container.setViewControllers([], animated: false)

        XCTAssertTrue(container.viewControllers.isEmpty)
        XCTAssertNil(container.topViewController)
        XCTAssertTrue(reportedDiagnostics.isEmpty, "空 stack 合法")
    }

    func test_setViewControllers_withAnIdenticalArray_isASilentNoOp() {
        let a = page("a"), b = page("b")
        let container = TeroNavigationContainer()
        container.setViewControllers([a, b], animated: false)
        log.reset()

        container.setViewControllers([a, b], animated: false)

        XCTAssertEqual(container.viewControllers.count, 2)
        XCTAssertTrue(log.events.isEmpty, "完全相同的陣列不該跑任何轉場")
        XCTAssertTrue(reportedDiagnostics.isEmpty)
    }

    func test_setViewControllers_withDuplicateInstances_keepsTheFirstAndReportsDiagnostic() {
        let a = page("a")
        let container = TeroNavigationContainer()

        container.setViewControllers([a, a], animated: false)

        XCTAssertEqual(container.viewControllers.count, 1)
        XCTAssertEqual(reportedDiagnostics.count, 1)
    }

    // MARK: - Appearance

    func test_pushWhileVisible_deliversPairedAppearanceEvents() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)
        present(container)
        log.reset()

        container.pushViewController(page("detail"), animated: false)

        XCTAssertEqual(log.events, [
            "root.willDisappear", "detail.willAppear",
            "root.didDisappear", "detail.didAppear"
        ])
    }

    func test_pushWhileNotVisible_commitsWithoutAppearanceEvents() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        let detail = page("detail")

        container.pushViewController(detail, animated: false)

        XCTAssertIdentical(container.topViewController, detail, "狀態仍然更新")
        XCTAssertTrue(log.events.isEmpty, "容器沒上螢幕就不發 appearance 事件")
    }

    func test_pushBeforeTheViewLoads_installsTheContentOnLoad() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        container.loadViewIfNeeded()

        XCTAssertIdentical(detail.view.superview, container.view)
    }

    // MARK: - 從子頁找到容器

    func test_everyPageInTheStackFindsItsContainer() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        XCTAssertIdentical(root.teroNavigationContainer, container)
        XCTAssertIdentical(detail.teroNavigationContainer, container)
    }

    func test_aChildOfAPageFindsThePagesContainer() {
        let root = page("root")
        let container = TeroNavigationContainer(rootViewController: root)
        let nested = UIViewController()
        root.addChild(nested)
        nested.didMove(toParent: root)

        XCTAssertIdentical(nested.teroNavigationContainer, container)
    }

    func test_aPageOutsideAnyContainerFindsNone() {
        XCTAssertNil(page("alone").teroNavigationContainer)
    }

    /// 與 `navigationController` 相同：不含自己，找的是上一層。
    func test_aContainerFindsTheOneAboveItRatherThanItself() {
        let outer = TeroNavigationContainer(rootViewController: page("outer"))
        let inner = TeroNavigationContainer(rootViewController: page("inner"))
        outer.pushViewController(inner, animated: false)

        XCTAssertIdentical(inner.teroNavigationContainer, outer)
        XCTAssertNil(outer.teroNavigationContainer)
    }

    /// chrome 上的動作最常在這裡取容器：容器建立 chrome 之前就把頁面收成 child。
    func test_aPageFindsItsContainerWhileMakingItsChrome() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        let detail = ContainerLookupPage()

        container.pushViewController(detail, animated: false)

        XCTAssertIdentical(detail.containerWhileMakingChrome, container)
    }

    // MARK: - 轉發

    func test_statusBarAndOrientationForwardToTheTopViewController() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        XCTAssertIdentical(container.childForStatusBarStyle, detail)
        XCTAssertIdentical(container.childForHomeIndicatorAutoHidden, detail)
    }
}
