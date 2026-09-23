import XCTest
@testable import Tero

/// 對應 ticket #22。點擊路徑透過公開的 `tabBar` 視圖階層驅動，
/// 只使用公開的 UIKit API（`UIControl.sendActions`、`accessibilityIdentifier`）。
final class ClassicTabBarTests: TeroTabBarControllerTestCase {

    private func makePresentedController() -> TeroTabBarController {
        let controller = makeController()
        controller.setTabs(
            [makeTab("home"), makeTab("search"), makeTab("profile")],
            selectedIdentifier: "home",
            animated: false
        )
        present(controller)
        return controller
    }

    // MARK: 點擊

    func test_tappingTab_selectsItWithUserSource() {
        let controller = makePresentedController()
        recorder.shouldSelectCalls = []
        recorder.didSelectCalls = []

        tapTabBarItem("search", in: controller)

        XCTAssertEqual(controller.selectedTab?.identifier, "search")
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertEqual(recorder.shouldSelectCalls.first?.source, .user)
        XCTAssertEqual(recorder.didSelectCalls.first?.source, .user)
    }

    func test_tappingSelectedTab_emitsDidReselectAndDoesNotTransitionContent() {
        let controller = makePresentedController()
        log.reset()
        recorder.didSelectCalls = []

        tapTabBarItem("home", in: controller)

        XCTAssertEqual(recorder.didReselectCalls, ["home"])
        XCTAssertTrue(recorder.didSelectCalls.isEmpty)
        XCTAssertTrue(
            log.events.filter { !$0.hasPrefix("delegate.") }.isEmpty,
            "不應重做 view controller 轉場，實際為 \(log.events)"
        )
    }

    func test_tappingDisabledTab_doesNothing() {
        let controller = makeController()
        controller.setTabs(
            [makeTab("home"), makeTab("locked", enabled: false)],
            selectedIdentifier: "home",
            animated: false
        )
        present(controller)
        recorder.didSelectCalls = []

        // 第一層：控制項本身就是 disabled，UIKit 不會把觸控送給它
        XCTAssertEqual(tabBarControl(for: "locked", in: controller)?.isEnabled, false)

        // 第二層：即使強行觸發動作，controller 自己的守門仍然成立
        forceTapTabBarItem("locked", in: controller)

        XCTAssertEqual(controller.selectedTab?.identifier, "home")
        XCTAssertTrue(recorder.didSelectCalls.isEmpty)
    }

    func test_tappingTabRejectedByDelegate_leavesSelectionUnchanged() {
        let controller = makePresentedController()
        recorder.shouldSelectResult = false

        tapTabBarItem("profile", in: controller)

        XCTAssertEqual(controller.selectedTab?.identifier, "home")
    }

    // MARK: 選取狀態

    func test_barSelectionFollowsProgrammaticSelection() {
        let controller = makePresentedController()

        controller.selectTab(withIdentifier: "profile", animated: false)

        XCTAssertEqual(tabBarControl(for: "home", in: controller)?.isSelected, false)
        XCTAssertEqual(tabBarControl(for: "profile", in: controller)?.isSelected, true)
    }

    func test_barReflectsInitialSelection() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "search", animated: false)
        present(controller)

        XCTAssertEqual(tabBarControl(for: "search", in: controller)?.isSelected, true)
        XCTAssertEqual(tabBarControl(for: "home", in: controller)?.isSelected, false)
    }

    func test_barItemsAreRebuiltWhenTabsChange() {
        let controller = makePresentedController()

        controller.setTabs([makeTab("news")], selectedIdentifier: nil, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNotNil(tabBarControl(for: "news", in: controller))
        XCTAssertNil(tabBarControl(for: "search", in: controller), "移除的 Tab 不該還留在 Bar 上")
    }

    func test_emptyTabsProducesNoBarItems() {
        let controller = makePresentedController()

        controller.setTabs([], selectedIdentifier: nil, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNil(tabBarControl(for: "home", in: controller))
    }

    // MARK: 版面與 safe area

    func test_barIsPinnedToBottomAndFullWidth() {
        let controller = makePresentedController()
        controller.view.layoutIfNeeded()

        let barFrame = controller.tabBar.frame
        XCTAssertEqual(barFrame.width, controller.view.bounds.width, accuracy: 0.5)
        XCTAssertEqual(barFrame.maxY, controller.view.bounds.maxY, accuracy: 0.5)
        XCTAssertEqual(barFrame.minX, 0, accuracy: 0.5)
    }

    func test_barHeightAddsHomeIndicatorSafeAreaOnTopOfContentHeight() {
        let controller = makePresentedController()
        controller.view.layoutIfNeeded()

        let expectedContentHeight = controller.currentConfiguration().classicAppearance.barHeight
        let expected = expectedContentHeight + controller.view.safeAreaInsets.bottom

        XCTAssertEqual(controller.tabBar.frame.height, expected, accuracy: 0.5,
                       "設定的 bar 高度不含 home indicator 安全區")
    }

    func test_childSafeAreaAvoidsTabBar() {
        let controller = makePresentedController()
        controller.view.layoutIfNeeded()

        guard let child = controller.selectedViewController else {
            return XCTFail("應有 selected view controller")
        }
        child.view.layoutIfNeeded()

        let barContentHeight = controller.currentConfiguration().classicAppearance.barHeight
        XCTAssertEqual(
            child.view.safeAreaInsets.bottom,
            controller.view.safeAreaInsets.bottom + barContentHeight,
            accuracy: 0.5,
            "子畫面的 safe area 必須避開 Bar，且不重複計算 home indicator"
        )
    }

    func test_everyChildGetsTheSafeAreaInsetNotJustTheSelectedOne() {
        let controller = makePresentedController()
        controller.view.layoutIfNeeded()

        let barContentHeight = controller.currentConfiguration().classicAppearance.barHeight
        for child in controller.children {
            XCTAssertEqual(child.additionalSafeAreaInsets.bottom, barContentHeight, accuracy: 0.5,
                           "尚未顯示的 Tab 也必須先備好 inset，切換時才不會跳動")
        }
    }

    // MARK: Style

    func test_barStyleMatchesEffectiveStyle() {
        let controller = makePresentedController()

        XCTAssertEqual(controller.tabBar.style, controller.tabBarStyle)
    }
}
