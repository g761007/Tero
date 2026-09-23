import XCTest
@testable import Tero

final class SelectionTests: TeroTabBarControllerTestCase {

    private func makeThreeTabController() -> (TeroTabBarController, [TeroTab]) {
        let controller = makeController()
        let tabs = [makeTab("home"), makeTab("search"), makeTab("profile")]
        controller.setTabs(tabs, selectedIdentifier: "home", animated: false)
        present(controller)
        log.reset()
        recorder.didSelectCalls = []
        recorder.shouldSelectCalls = []
        return (controller, tabs)
    }

    // MARK: - KVO

    /// `selectedIndex` 與 `selectedTab` 要發得出 KVO 通知。
    ///
    /// 只標 `@objc` 不夠：Swift 端是直接存取的，不經 ObjC runtime，`willChangeValueForKey`
    /// 不會發，觀察者**靜默地永遠收不到**。某個接入專案有一處 `RACObserve` 就是這樣失效的
    /// ——而且那種失效不會有任何警告。少了 `dynamic` 這條會紅。
    func test_selectionIsObservableWithKVO() {
        let (controller, _) = makeThreeTabController()
        var indexChanges = 0
        var tabChanges = 0
        let observations = [
            controller.observe(\.selectedIndex, options: [.new]) { _, _ in indexChanges += 1 },
            controller.observe(\.selectedTab, options: [.new]) { _, _ in tabChanges += 1 }
        ]
        defer { observations.forEach { $0.invalidate() } }

        _ = controller.selectTab(withIdentifier: "profile", animated: false)

        XCTAssertGreaterThan(indexChanges, 0, "selectedIndex 的觀察者要收到通知")
        XCTAssertGreaterThan(tabChanges, 0, "selectedTab 的觀察者要收到通知")
    }

    func test_selectByIdentifier_updatesStateAndReturnsTrue() {
        let (controller, tabs) = makeThreeTabController()

        let result = controller.selectTab(withIdentifier: "profile", animated: false)

        XCTAssertTrue(result)
        XCTAssertEqual(controller.selectedTab?.identifier, "profile")
        XCTAssertEqual(controller.selectedIndex, 2)
        XCTAssertTrue(isContentViewInstalled(tabs[2], in: controller))
        XCTAssertFalse(isContentViewInstalled(tabs[0], in: controller))
    }

    func test_selectByIndex_updatesStateAndReturnsTrue() {
        let (controller, _) = makeThreeTabController()

        XCTAssertTrue(controller.selectTab(at: 1, animated: false))
        XCTAssertEqual(controller.selectedTab?.identifier, "search")
        XCTAssertEqual(controller.selectedTabIndex, 1)
    }

    func test_selectUnknownIdentifier_returnsFalseAndLeavesStateUnchanged() {
        let (controller, _) = makeThreeTabController()

        XCTAssertFalse(controller.selectTab(withIdentifier: "nope", animated: false))
        XCTAssertEqual(controller.selectedTab?.identifier, "home")
        XCTAssertTrue(recorder.didSelectCalls.isEmpty)
    }

    func test_selectOutOfRangeIndex_returnsFalse() {
        let (controller, _) = makeThreeTabController()

        XCTAssertFalse(controller.selectTab(at: 99, animated: false))
        XCTAssertFalse(controller.selectTab(at: -1, animated: false))
        XCTAssertEqual(controller.selectedTab?.identifier, "home")
    }

    func test_selectDisabledTab_returnsFalse() {
        let controller = makeController()
        let disabled = makeTab("locked", enabled: false)
        controller.setTabs([makeTab("home"), disabled], selectedIdentifier: "home", animated: false)
        present(controller)

        XCTAssertFalse(controller.selectTab(withIdentifier: "locked", animated: false))
        XCTAssertEqual(controller.selectedTab?.identifier, "home")
        XCTAssertTrue(isContentViewInstalled(controller.tabs[0], in: controller))
    }

    func test_selectRejectedByDelegate_returnsFalseAndLeavesStateUnchanged() {
        let (controller, tabs) = makeThreeTabController()
        recorder.shouldSelectResult = false

        XCTAssertFalse(controller.selectTab(withIdentifier: "search", animated: false))
        XCTAssertEqual(controller.selectedTab?.identifier, "home")
        XCTAssertTrue(isContentViewInstalled(tabs[0], in: controller))
        XCTAssertFalse(isContentViewInstalled(tabs[1], in: controller))
        XCTAssertTrue(recorder.didSelectCalls.isEmpty, "被拒絕時不應發出 didSelect")
    }

    func test_selectAlreadySelectedTab_returnsTrueWithoutSideEffects() {
        let (controller, _) = makeThreeTabController()

        XCTAssertTrue(controller.selectTab(withIdentifier: "home", animated: false))
        XCTAssertEqual(controller.selectedIndex, 0)
        XCTAssertTrue(log.events.isEmpty, "不應產生任何 appearance 或 delegate 事件，實際為 \(log.events)")
    }
}
