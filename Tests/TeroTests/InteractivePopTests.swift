import XCTest
import UIKit
@testable import Tero

/// Phase 3：互動式返回。
///
/// 驗的是 §17 的復原清單能不能成立。關鍵在 ADR-0014 的一個決定：**finish 判定成立前不提交**，
/// 所以取消之後 `viewControllers` 根本沒被動過——復原不需要還原程式碼。
/// 但 appearance 已經送出去了，UIKit 沒有 rollback，那一組必須手動反向補回。
final class InteractivePopTests: TeroTabBarControllerTestCase {

    private func page(_ name: String) -> LifecycleSpyViewController {
        LifecycleSpyViewController(name: name, log: log)
    }

    private func twoPageContainer(duration: TimeInterval = 0.2) -> (TeroNavigationContainer, LifecycleSpyViewController, LifecycleSpyViewController) {
        let root = page("root")
        let detail = page("detail")
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = duration
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        container.pushViewController(detail, animated: false)
        log.reset()
        return (container, root, detail)
    }

    private func waitForIdle(_ container: TeroNavigationContainer) {
        waitUntil("互動式返回結算") { container.transitionState == .idle }
    }

    // MARK: - 開始的前提

    func test_beginInteractivePop_onSingleEntryStack_isRefused() {
        let container = TeroNavigationContainer(rootViewController: page("root"))
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()

        XCTAssertFalse(container.beginInteractivePop(), "只有一頁時沒有可返回的目標")
        XCTAssertEqual(container.transitionState, .idle)
    }

    func test_beginInteractivePop_whileAnotherTransitionRuns_isRefused() {
        let (container, _, _) = twoPageContainer(duration: 1.0)
        container.pushViewController(page("third"), animated: true)

        XCTAssertFalse(container.beginInteractivePop(), "同時只能有一段轉場")
        waitForIdle(container)
    }

    // MARK: - 手勢進行中

    func test_duringTheGesture_theStackIsUntouched() {
        let (container, _, detail) = twoPageContainer()

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.4)

        XCTAssertEqual(container.viewControllers.count, 2, "手勢進行中不提交")
        XCTAssertIdentical(container.topViewController, detail)
        XCTAssertEqual(container.transitionState, .interactivePop)

        container.endInteractivePop(progress: 0.4, velocity: 0)
        waitForIdle(container)
    }

    func test_duringTheGesture_thePageBelowIsAlreadyInTheHierarchy() {
        let (container, root, _) = twoPageContainer()

        container.beginInteractivePop()

        XCTAssertIdentical(root.view.superview, container.view, "下一頁要先在階層裡才跟得動")
        XCTAssertIdentical(root.parent, container)

        container.endInteractivePop(progress: 0, velocity: 0)
        waitForIdle(container)
    }

    // MARK: - 取消

    func test_cancel_leavesViewControllersUnchanged() {
        let (container, _, detail) = twoPageContainer()

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.3)
        container.endInteractivePop(progress: 0.3, velocity: 0)
        waitForIdle(container)

        XCTAssertEqual(container.viewControllers.count, 2, "取消之後 stack 一個字都沒變")
        XCTAssertIdentical(container.topViewController, detail)
        XCTAssertIdentical(detail.parent, container)
    }

    func test_cancel_reversesTheAppearanceItAlreadySent() {
        let (container, root, _) = twoPageContainer()

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.3)
        container.endInteractivePop(progress: 0.3, velocity: 0)
        waitForIdle(container)

        XCTAssertEqual(log.events.filter { $0.hasPrefix("detail.") },
                       ["detail.willDisappear", "detail.willAppear", "detail.didAppear"],
                       "上層頁從未真的離開，序列要收斂回『它還在』")
        XCTAssertEqual(log.events.filter { $0.hasPrefix("root.") },
                       ["root.willAppear", "root.willDisappear", "root.didDisappear"],
                       "下層頁從未真的出現")
    }

    func test_cancel_removesThePageBelowFromTheHierarchy() {
        let (container, root, _) = twoPageContainer()

        container.beginInteractivePop()
        container.endInteractivePop(progress: 0.1, velocity: 0)
        waitForIdle(container)

        XCTAssertNil(root.view.superview, "取消之後下一頁要退出畫面")
    }

    // MARK: - 完成

    func test_finish_commitsAtTheDecisionPointNotWhenTheAnimationEnds() {
        let (container, root, detail) = twoPageContainer(duration: 1.0)

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.8)
        container.endInteractivePop(progress: 0.8, velocity: 0)

        XCTAssertIdentical(container.topViewController, root, "判定成立的當下就提交")
        XCTAssertEqual(container.viewControllers.count, 1)
        XCTAssertEqual(container.transitionState, .finishingInteractivePop, "動畫還在跑")
        XCTAssertTrue(container.children.contains { $0 === detail }, "但還沒離開 children")

        waitForIdle(container)
        XCTAssertNil(detail.parent, "結算後才離開")
    }

    func test_finish_deliversAPlainDisappearanceForThePageThatLeft() {
        let (container, _, _) = twoPageContainer()

        container.beginInteractivePop()
        container.endInteractivePop(progress: 0.9, velocity: 0)
        waitForIdle(container)

        XCTAssertEqual(log.events.filter { $0.hasPrefix("detail.") },
                       ["detail.willDisappear", "detail.didDisappear"],
                       "完成時不該有反向補償")
        XCTAssertEqual(log.events.filter { $0.hasPrefix("root.") },
                       ["root.willAppear", "root.didAppear"])
    }

    // MARK: - §16 的判定

    func test_velocityAloneCanFinishTheGesture() {
        let (container, root, _) = twoPageContainer()

        container.beginInteractivePop()
        container.endInteractivePop(progress: 0.1, velocity: 1200)

        XCTAssertIdentical(container.topViewController, root, "距離不夠但甩得夠快，一樣完成")
        waitForIdle(container)
    }

    func test_shortSlowGestureCancels() {
        let (container, _, detail) = twoPageContainer()

        container.beginInteractivePop()
        container.endInteractivePop(progress: 0.2, velocity: 100)
        waitForIdle(container)

        XCTAssertIdentical(container.topViewController, detail)
    }

    // MARK: - 與其他 mutation 的界線

    func test_programmaticPushDuringAnInteractivePop_leavesNoUnpairedAppearanceOrOrphanView() {
        let (container, root, detail) = twoPageContainer()

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.4)
        let third = page("third")
        container.pushViewController(third, animated: false)

        XCTAssertIdentical(container.topViewController, third, "push 照常提交，被收掉的是手勢段")
        XCTAssertEqual(container.transitionState, .idle)

        // 手勢段送出的 begin 必須有配對的 end：root 被拉出來又收回去，一來一回。
        XCTAssertEqual(log.events.filter { $0.hasPrefix("root.") },
                       ["root.willAppear", "root.willDisappear", "root.didDisappear"],
                       "手勢段的 appearance 要收乾淨，不能留下沒配對的 begin")
        XCTAssertNil(root.view.superview, "被手指拉出來的那一頁不能留在畫面上")

        // 手勢已經沒了，之後放開手指不該有任何作用。
        let before = container.viewControllers.map(ObjectIdentifier.init)
        container.endInteractivePop(progress: 0.9, velocity: 2000)
        XCTAssertEqual(container.viewControllers.map(ObjectIdentifier.init), before,
                       "手勢段已被收掉，放開手指不該再改動 stack")
        XCTAssertIdentical(container.topViewController, third)
        _ = detail
    }
}
