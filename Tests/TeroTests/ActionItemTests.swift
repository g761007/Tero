import XCTest
@testable import Tero

/// 對應 ticket #26。Action 是獨立指令，不是 Tab。
final class ActionItemTests: TeroTabBarControllerTestCase {

    final class TriggerRecorder: NSObject, TeroTabBarControllerDelegate {
        private(set) var triggered: [String] = []
        private(set) var selections: [String] = []
        private(set) var reselections: [String] = []

        func teroTabBarController(_ c: TeroTabBarController, didTrigger actionItem: TeroTabActionItem) {
            triggered.append(actionItem.identifier)
        }
        func teroTabBarController(_ c: TeroTabBarController, didSelect tab: TeroTab, source: TeroTabSelectionSource) {
            selections.append(tab.identifier)
        }
        func teroTabBarController(_ c: TeroTabBarController, didReselect tab: TeroTab) {
            reselections.append(tab.identifier)
        }

        func reset() {
            triggered.removeAll()
            selections.removeAll()
            reselections.removeAll()
        }
    }

    private func makeAction(_ identifier: String = "compose", enabled: Bool = true) -> TeroTabActionItem {
        let action = TeroTabActionItem(identifier: identifier, image: UIImage(systemName: "plus"))
        action.isEnabled = enabled
        action.accessibilityIdentifier = "tab.\(identifier)"
        return action
    }

    private func makePresentedController(
        tabCount: Int = 4,
        action: TeroTabActionItem? = nil
    ) -> (TeroTabBarController, TriggerRecorder) {
        let triggers = TriggerRecorder()
        let controller = makeController()
        controller.delegate = triggers
        controller.setTabs((0..<tabCount).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        if let action { controller.setActionItem(action, animated: false) }
        present(controller)
        controller.view.layoutIfNeeded()
        // 初始選取會發出 didSelect(.initial)，那不是本測試的觀察對象
        triggers.reset()
        return (controller, triggers)
    }

    // MARK: 存在與否

    func test_noActionMeansNoExtraSlot() {
        let (controller, _) = makePresentedController(tabCount: 4)

        XCTAssertNil(controller.actionItem)
        XCTAssertNil(tabBarControl(for: "compose", in: controller))
    }

    func test_settingActionAddsAControl() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        XCTAssertEqual(controller.actionItem?.identifier, "compose")
        XCTAssertNotNil(tabBarControl(for: "compose", in: controller))
    }

    func test_clearingActionRemovesTheControl() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        controller.setActionItem(nil, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNil(controller.actionItem)
        XCTAssertNil(tabBarControl(for: "compose", in: controller))
    }

    // MARK: 互動語意

    func test_tappingActionOnlyEmitsDidTrigger() {
        let (controller, triggers) = makePresentedController(tabCount: 4, action: makeAction())

        tapTabBarItem("compose", in: controller)

        XCTAssertEqual(triggers.triggered, ["compose"])
        XCTAssertTrue(triggers.selections.isEmpty)
        XCTAssertTrue(triggers.reselections.isEmpty)
    }

    func test_tappingActionDoesNotChangeSelection() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())
        let indexBefore = controller.selectedIndex

        tapTabBarItem("compose", in: controller)

        XCTAssertEqual(controller.selectedTab?.identifier, "t0")
        XCTAssertEqual(controller.selectedIndex, indexBefore)
    }

    func test_disabledActionCannotBeTriggered() {
        let (controller, triggers) = makePresentedController(tabCount: 4, action: makeAction(enabled: false))

        XCTAssertEqual(tabBarControl(for: "compose", in: controller)?.isEnabled, false)
        forceTapTabBarItem("compose", in: controller)

        XCTAssertTrue(triggers.triggered.isEmpty, "強行觸發時 controller 的守門仍應成立")
    }

    func test_actionIsNeverSelected() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        tapTabBarItem("compose", in: controller)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(tabBarControl(for: "compose", in: controller)?.isSelected, false)
        XCTAssertEqual(tabBarControl(for: "t0", in: controller)?.isSelected, true)
    }

    // MARK: 不影響 Overflow 計算

    func test_actionDoesNotCountTowardsMaximumVisibleItems() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = 4
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<6).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)

        let visibleWithoutAction = controller.visibleTabs.count
        controller.setActionItem(makeAction(), animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.visibleTabs.count, visibleWithoutAction, "Action 不該擠掉一個 Tab")
        XCTAssertEqual(controller.visibleTabs.count, 3, "上限 4 含 More，因此可見 3 個")
    }

    func test_actionNeverEntersOverflowMenu() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = 3
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<6).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        controller.setActionItem(makeAction(), animated: false)
        present(controller)

        guard let menu = (tabBarControl(for: "more", in: controller) as? UIButton)?.menu else {
            return XCTFail("應有溢位選單")
        }
        let titles = menu.children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertFalse(titles.contains("compose"))
        XCTAssertFalse(controller.overflowTabs.contains { $0.identifier == "compose" })
    }

    // MARK: 版面

    func test_actionIsCentredInTheBar() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        guard let action = tabBarControl(for: "compose", in: controller) else { return XCTFail() }
        let barMidX = controller.tabBar.bounds.midX
        XCTAssertEqual(action.frame.midX, barMidX, accuracy: 1.0)
    }

    func test_barHasOneMoreColumnWhenActionIsPresent() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        guard let action = tabBarControl(for: "compose", in: controller) else { return XCTFail() }
        let expectedWidth = controller.tabBar.bounds.width / 5  // 4 個 Tab + Action
        XCTAssertEqual(action.frame.width, expectedWidth, accuracy: 1.0)
    }

    func test_oddNumberOfSlotsPutsTheExtraOneOnTheLeft() {
        // 5 個 Tab（未超過上限）＋ Action → 左 3、右 2
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = 6
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<5).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        controller.setActionItem(makeAction(), animated: false)
        present(controller)
        controller.view.layoutIfNeeded()

        guard let action = tabBarControl(for: "compose", in: controller) else { return XCTFail() }
        let tabFrames = (0..<5).compactMap { tabBarControl(for: "t\($0)", in: controller)?.frame }
        XCTAssertEqual(tabFrames.count, 5)

        let leftOfAction = tabFrames.filter { $0.midX < action.frame.midX }.count
        let rightOfAction = tabFrames.filter { $0.midX > action.frame.midX }.count
        XCTAssertEqual(leftOfAction, 3)
        XCTAssertEqual(rightOfAction, 2)
    }

    func test_evenNumberOfSlotsIsSymmetric() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        guard let action = tabBarControl(for: "compose", in: controller) else { return XCTFail() }
        let tabFrames = (0..<4).compactMap { tabBarControl(for: "t\($0)", in: controller)?.frame }
        XCTAssertEqual(tabFrames.filter { $0.midX < action.frame.midX }.count, 2)
        XCTAssertEqual(tabFrames.filter { $0.midX > action.frame.midX }.count, 2)
    }

    func test_actionAndTabsDoNotOverlap() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        guard let action = tabBarControl(for: "compose", in: controller) else { return XCTFail() }
        for index in 0..<4 {
            guard let tab = tabBarControl(for: "t\(index)", in: controller) else { return XCTFail() }
            XCTAssertFalse(tab.frame.intersects(action.frame.insetBy(dx: 1, dy: 0)), "t\(index) 與 Action 重疊")
        }
    }

    // MARK: 自訂內容

    func test_actionCanUseAContentProvider() {
        final class Provider: NSObject, TeroTabContentProvider {
            var madeCount = 0
            func makeContentView() -> UIView { madeCount += 1; return UIView() }
        }
        let provider = Provider()
        let action = makeAction()
        action.contentProvider = provider

        let (controller, _) = makePresentedController(tabCount: 4, action: action)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(provider.madeCount, 1)
    }

    // MARK: 狀態保留

    func test_actionSurvivesTabChanges() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        controller.setTabs((0..<3).map { makeTab("n\($0)") }, selectedIdentifier: nil, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.actionItem?.identifier, "compose")
        XCTAssertNotNil(tabBarControl(for: "compose", in: controller))
    }

    func test_actionIsRetainedEvenWithNoTabs() {
        let (controller, _) = makePresentedController(tabCount: 4, action: makeAction())

        controller.setTabs([], selectedIdentifier: nil, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.actionItem?.identifier, "compose", "Action 的狀態應保留")
    }
}
