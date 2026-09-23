import XCTest
@testable import Tero

/// 對應 ticket #24。
final class OverflowTests: TeroTabBarControllerTestCase {

    private func makeController(limit: Int, tabCount: Int) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = limit
        configuration.regular.maximumVisibleItems = limit
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<tabCount).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    // MARK: 邊界規則

    func test_tabCountBelowLimit_showsEverythingWithoutMore() {
        let controller = makeController(limit: 6, tabCount: 4)

        XCTAssertEqual(controller.visibleTabs.count, 4)
        XCTAssertTrue(controller.overflowTabs.isEmpty)
        XCTAssertNil(tabBarControl(for: "more", in: controller), "沒有溢位就不該出現 More")
    }

    func test_tabCountEqualToLimit_showsEverythingWithoutMore() {
        let controller = makeController(limit: 6, tabCount: 6)

        XCTAssertEqual(controller.visibleTabs.count, 6)
        XCTAssertTrue(controller.overflowTabs.isEmpty)
        XCTAssertNil(tabBarControl(for: "more", in: controller))
    }

    /// 多加一個 Tab 反而少顯示一個——刻意的行為，因為上限包含 More。
    func test_oneTabOverLimit_dropsAVisibleSlotToMakeRoomForMore() {
        let controller = makeController(limit: 6, tabCount: 7)

        XCTAssertEqual(controller.visibleTabs.map(\.identifier), ["t0", "t1", "t2", "t3", "t4"])
        XCTAssertEqual(controller.overflowTabs.map(\.identifier), ["t5", "t6"])
        XCTAssertNotNil(tabBarControl(for: "more", in: controller))
    }

    func test_farOverLimit_keepsVisibleCountAtLimitMinusOne() {
        let controller = makeController(limit: 6, tabCount: 12)

        XCTAssertEqual(controller.visibleTabs.count, 5)
        XCTAssertEqual(controller.overflowTabs.count, 7)
    }

    func test_minimumLimitIsRespected() {
        let controller = makeController(limit: 2, tabCount: 5)

        XCTAssertEqual(controller.visibleTabs.count, 1)
        XCTAssertEqual(controller.overflowTabs.count, 4)
    }

    // MARK: 分割不變式

    func test_visibleAndOverflowAlwaysPartitionTabs() {
        for tabCount in 0...12 {
            let controller = makeController(limit: 5, tabCount: tabCount)
            let visible = controller.visibleTabs
            let overflow = controller.overflowTabs

            XCTAssertEqual(visible.count + overflow.count, controller.tabs.count, "tabCount=\(tabCount)")

            let union = (visible + overflow).map(\.identifier)
            XCTAssertEqual(Set(union).count, union.count, "不得重複，tabCount=\(tabCount)")
            XCTAssertEqual(Set(union), Set(controller.tabs.map(\.identifier)), "聯集必須等於全部")

            XCTAssertEqual(visible.map(\.identifier), visible.map(\.identifier).sorted { lhs, rhs in
                controller.tabs.firstIndex { $0.identifier == lhs }! < controller.tabs.firstIndex { $0.identifier == rhs }!
            }, "必須保持原始順序")
        }
    }

    func test_emptyTabsProducesEmptyPartition() {
        let controller = makeController(limit: 5, tabCount: 0)

        XCTAssertTrue(controller.visibleTabs.isEmpty)
        XCTAssertTrue(controller.overflowTabs.isEmpty)
    }

    // MARK: More 的選取語意

    func test_moreIsNeverTheSelectedTab() {
        let controller = makeController(limit: 4, tabCount: 8)

        controller.select(controller.tabs[6], at: 6, source: .overflow, animated: false)

        XCTAssertEqual(controller.selectedTab?.identifier, "t6")
        XCTAssertEqual(controller.selectedIndex, 6, "index 必須是原始 index")
        XCTAssertFalse(controller.tabs.contains { $0.identifier == "more" })
    }

    func test_selectingFromOverflowMarksMoreAsSelectedInTheBar() {
        let controller = makeController(limit: 4, tabCount: 8)

        controller.select(controller.tabs[6], at: 6, source: .overflow, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(tabBarControl(for: "more", in: controller)?.isSelected, true)
        for index in 0..<3 {
            XCTAssertEqual(tabBarControl(for: "t\(index)", in: controller)?.isSelected, false)
        }
    }

    func test_selectingVisibleTabClearsMoreSelection() {
        let controller = makeController(limit: 4, tabCount: 8)
        controller.select(controller.tabs[6], at: 6, source: .overflow, animated: false)

        controller.selectTab(withIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(tabBarControl(for: "more", in: controller)?.isSelected, false)
        XCTAssertEqual(tabBarControl(for: "t1", in: controller)?.isSelected, true)
    }

    func test_overflowSelectionEmitsDidSelectWithOverflowSource() {
        let controller = makeController(limit: 4, tabCount: 8)
        recorder.didSelectCalls = []

        controller.select(controller.tabs[5], at: 5, source: .overflow, animated: false)

        XCTAssertEqual(recorder.didSelectCalls.last?.identifier, "t5")
        XCTAssertEqual(recorder.didSelectCalls.last?.source, .overflow)
    }

    func test_overflowSelectionCanBeRejectedByDelegate() {
        let controller = makeController(limit: 4, tabCount: 8)
        recorder.shouldSelectResult = false

        XCTAssertFalse(controller.select(controller.tabs[5], at: 5, source: .overflow, animated: false))
        XCTAssertEqual(controller.selectedTab?.identifier, "t0")
    }

    // MARK: More 的 Badge

    func test_moreShowsDotWhenAnyOverflowTabHasABadge() {
        let controller = makeController(limit: 4, tabCount: 8)

        controller.setBadge(.value("9"), forTabWithIdentifier: "t7", animated: false)
        controller.view.layoutIfNeeded()

        // 圓點沒有可播報的原始值，因此 More 的 accessibilityValue 仍為 nil；
        // 這裡驗的是 More 上真的多了一個可見的 Badge 子視圖。
        guard let more = tabBarControl(for: "more", in: controller) else { return XCTFail() }
        XCTAssertTrue(more.subviews.contains { $0 is TeroTabBadgeView && !$0.isHidden })
    }

    func test_moreHasNoDotWhenOnlyVisibleTabsHaveBadges() {
        let controller = makeController(limit: 4, tabCount: 8)

        controller.setBadge(.value("9"), forTabWithIdentifier: "t0", animated: false)
        controller.view.layoutIfNeeded()

        guard let more = tabBarControl(for: "more", in: controller) else { return XCTFail() }
        XCTAssertFalse(more.subviews.contains { $0 is TeroTabBadgeView && !$0.isHidden })
    }

    func test_moreDotDoesNotAggregateValues() {
        let controller = makeController(limit: 4, tabCount: 8)

        controller.setBadge(.value("3"), forTabWithIdentifier: "t5", animated: false)
        controller.setBadge(.value("8"), forTabWithIdentifier: "t6", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNil(
            tabBarControl(for: "more", in: controller)?.accessibilityValue,
            "V1 不做數值加總，3 + 8 不會變成 11"
        )
    }

    // MARK: More 選單內容

    func test_overflowMenuListsOverflowTabsInOrder() {
        let controller = makeController(limit: 4, tabCount: 7)

        guard let menu = (tabBarControl(for: "more", in: controller) as? UIButton)?.menu else {
            return XCTFail("`.automatic` 應解析為選單並掛在 More 上")
        }
        let titles = menu.children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertEqual(titles, ["t3", "t4", "t5", "t6"])
    }

    func test_overflowMenuMarksTheSelectedOverflowTab() {
        let controller = makeController(limit: 4, tabCount: 7)
        controller.select(controller.tabs[5], at: 5, source: .overflow, animated: false)

        guard let menu = (tabBarControl(for: "more", in: controller) as? UIButton)?.menu else {
            return XCTFail()
        }
        let states = menu.children.compactMap { ($0 as? UIAction).map { ($0.title, $0.state) } }
        XCTAssertEqual(states.first { $0.0 == "t5" }?.1, .on)
        XCTAssertEqual(states.first { $0.0 == "t4" }?.1, .off)
    }

    func test_overflowMenuImageFallsBackFromOverflowImageToImage() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = 3
        let controller = makeController(configuration: configuration)

        let overflowOnly = makeTab("a")
        overflowOnly.item.overflowImage = UIImage(systemName: "star")
        overflowOnly.item.image = UIImage(systemName: "circle")

        let imageOnly = makeTab("b")
        imageOnly.item.image = UIImage(systemName: "square")

        let noImage = makeTab("c")

        controller.setTabs(
            [makeTab("keep0"), makeTab("keep1"), overflowOnly, imageOnly, noImage],
            selectedIdentifier: "keep0",
            animated: false
        )
        present(controller)

        guard let menu = (tabBarControl(for: "more", in: controller) as? UIButton)?.menu else {
            return XCTFail()
        }
        let actions = menu.children.compactMap { $0 as? UIAction }
        XCTAssertEqual(actions.count, 3)
        XCTAssertNotNil(actions[0].image, "有 overflowImage 就用它")
        XCTAssertNotNil(actions[1].image, "沒有 overflowImage 就退回 image")
        XCTAssertNil(actions[2].image, "兩者都沒有就沒有圖示")
    }

    func test_overflowMenuDisablesDisabledTabs() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = 3
        let controller = makeController(configuration: configuration)
        controller.setTabs(
            [makeTab("k0"), makeTab("k1"), makeTab("locked", enabled: false), makeTab("open")],
            selectedIdentifier: "k0",
            animated: false
        )
        present(controller)

        guard let menu = (tabBarControl(for: "more", in: controller) as? UIButton)?.menu else {
            return XCTFail()
        }
        let actions = menu.children.compactMap { $0 as? UIAction }
        XCTAssertTrue(actions.first { $0.title == "locked" }!.attributes.contains(.disabled))
        XCTAssertFalse(actions.first { $0.title == "open" }!.attributes.contains(.disabled))
    }

    func test_sheetStyleDoesNotAttachAMenu() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = 3
        configuration.morePresentationStyle = .sheet
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<6).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)

        XCTAssertNil(
            (tabBarControl(for: "more", in: controller) as? UIButton)?.menu,
            "sheet 樣式由 controller 呈現，不掛選單"
        )
    }

    // MARK: More 的預設外觀

    func test_moreUsesSystemSymbolWhenNoImageProvided() {
        let controller = makeController(limit: 3, tabCount: 6)

        guard let more = tabBarControl(for: "more", in: controller) else { return XCTFail() }
        let icons = more.subviews.compactMap { $0 as? UIImageView }
        XCTAssertTrue(icons.contains { $0.image != nil && !$0.isHidden }, "預設圖示應為系統符號")
    }

    func test_moreWithoutTitleShowsIconOnly() {
        let controller = makeController(limit: 3, tabCount: 6)

        guard let more = tabBarControl(for: "more", in: controller) else { return XCTFail() }
        let visibleLabels = more.subviews.compactMap { $0 as? UILabel }.filter { !$0.isHidden }
        XCTAssertTrue(visibleLabels.isEmpty, "套件不提供預設字串，因此沒有標題可顯示")
    }
}
