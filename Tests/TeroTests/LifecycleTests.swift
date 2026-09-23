import XCTest
@testable import Tero

/// 對應計畫書 §45。切換 Tab 必須產生真正的 appearance 事件，
/// 不得以隱藏視圖模擬——否則曝光追蹤與資源釋放都會錯。
final class LifecycleTests: TeroTabBarControllerTestCase {

    private var appearanceEvents: [String] {
        log.events.filter { !$0.hasPrefix("delegate.") }
    }

    func test_presentingContainer_forwardsAppearanceToSelectedChildOnly() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "home", animated: false)

        present(controller)

        XCTAssertEqual(appearanceEvents, ["home.willAppear", "home.didAppear"])
    }

    func test_switchingTabs_producesInterleavedAppearanceSequence() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "home", animated: false)
        present(controller)
        log.reset()

        controller.selectTab(withIdentifier: "search", animated: false)

        XCTAssertEqual(
            appearanceEvents,
            ["home.willDisappear", "search.willAppear", "home.didDisappear", "search.didAppear"]
        )
    }

    func test_switchingTabs_delegateOrderSurroundsTheTransition() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "home", animated: false)
        present(controller)
        log.reset()

        controller.selectTab(withIdentifier: "search", animated: false)

        XCTAssertEqual(log.events, [
            "delegate.shouldSelect(search)",
            "home.willDisappear",
            "search.willAppear",
            "home.didDisappear",
            "search.didAppear",
            "delegate.didSelect(search)"
        ], "shouldSelect 必須在任何轉場之前，didSelect 必須在轉場完成之後")
    }

    func test_switchingTabsWhileContainerNotVisible_producesNoAppearanceEvents() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "home", animated: false)
        loadWithoutPresenting(controller)
        log.reset()

        controller.selectTab(withIdentifier: "search", animated: false)

        XCTAssertTrue(appearanceEvents.isEmpty, "容器不可見時不應發出 child 的 appearance 事件，實際為 \(appearanceEvents)")
        XCTAssertEqual(controller.selectedTab?.identifier, "search", "但選取狀態仍應更新")
    }

    func test_switchingTabsTwice_doesNotLeakAppearanceEvents() {
        let controller = makeController()
        controller.setTabs([makeTab("a"), makeTab("b"), makeTab("c")], selectedIdentifier: "a", animated: false)
        present(controller)
        log.reset()

        controller.selectTab(withIdentifier: "b", animated: false)
        controller.selectTab(withIdentifier: "c", animated: false)
        controller.selectTab(withIdentifier: "a", animated: false)

        XCTAssertEqual(appearanceEvents, [
            "a.willDisappear", "b.willAppear", "a.didDisappear", "b.didAppear",
            "b.willDisappear", "c.willAppear", "b.didDisappear", "c.didAppear",
            "c.willDisappear", "a.willAppear", "c.didDisappear", "a.didAppear"
        ])
    }
}
