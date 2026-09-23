import XCTest
@testable import Tero

final class SetTabsTests: TeroTabBarControllerTestCase {

    func test_setTabs_withSelectedIdentifier_selectsThatTab() {
        let controller = makeController()
        let tabs = [makeTab("home"), makeTab("search"), makeTab("profile")]

        controller.setTabs(tabs, selectedIdentifier: "search", animated: false)

        XCTAssertEqual(controller.selectedTab?.identifier, "search")
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertEqual(controller.selectedTabIndex, 1)
        XCTAssertIdentical(controller.selectedViewController, tabs[1].viewController)
    }

    func test_setTabs_withNilIdentifier_selectsFirstTab() {
        let controller = makeController()

        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: nil, animated: false)

        XCTAssertEqual(controller.selectedTab?.identifier, "home")
        XCTAssertEqual(controller.selectedIndex, 0)
    }

    func test_setTabs_withNilIdentifier_preservesCurrentSelection() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "search", animated: false)

        // 刷新列表：順序改變、成員增加，但 search 仍在
        controller.setTabs(
            [makeTab("news"), makeTab("home"), makeTab("search")],
            selectedIdentifier: nil,
            animated: false
        )

        XCTAssertEqual(controller.selectedTab?.identifier, "search")
        XCTAssertEqual(controller.selectedIndex, 2, "index 應為新列表中的位置")
    }

    func test_setTabs_withNilIdentifier_whenCurrentSelectionDisappears_selectsFirst() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "search", animated: false)

        controller.setTabs([makeTab("news"), makeTab("home")], selectedIdentifier: nil, animated: false)

        XCTAssertEqual(controller.selectedTab?.identifier, "news")
        XCTAssertEqual(controller.selectedIndex, 0)
    }

    func test_setTabs_withUnknownSelectedIdentifier_fallsBackToPreservationRules() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "search", animated: false)

        controller.setTabs(
            [makeTab("home"), makeTab("search")],
            selectedIdentifier: "does-not-exist",
            animated: false
        )

        XCTAssertEqual(controller.selectedTab?.identifier, "search", "無效的 identifier 應退回保留規則")
    }

    func test_setTabs_empty_clearsSelection() {
        let controller = makeController()
        controller.setTabs([makeTab("home")], selectedIdentifier: nil, animated: false)

        controller.setTabs([], selectedIdentifier: nil, animated: false)

        XCTAssertNil(controller.selectedTab)
        XCTAssertNil(controller.selectedViewController)
        XCTAssertEqual(controller.selectedIndex, NSNotFound)
        XCTAssertNil(controller.selectedTabIndex)
        XCTAssertTrue(controller.tabs.isEmpty)
    }

    func test_setTabs_withDuplicateIdentifiers_keepsFirstAndReportsDiagnostic() {
        let controller = makeController()
        let first = makeTab("home")
        let duplicate = makeTab("home")

        controller.setTabs([first, duplicate, makeTab("search")], selectedIdentifier: nil, animated: false)

        XCTAssertEqual(controller.tabs.map(\.identifier), ["home", "search"])
        XCTAssertIdentical(controller.tabs.first, first, "應保留第一個")
        XCTAssertEqual(reportedDiagnostics.count, 1)
        XCTAssertTrue(reportedDiagnostics[0].contains("home"))
    }

    func test_setTabs_attachesEveryTabAsChild() {
        let controller = makeController()
        let tabs = [makeTab("home"), makeTab("search"), makeTab("profile")]

        controller.setTabs(tabs, selectedIdentifier: nil, animated: false)

        for tab in tabs {
            XCTAssertIdentical(tab.viewController.parent, controller, "\(tab.identifier) 應為 child")
        }
        XCTAssertEqual(controller.children.count, 3)
    }

    func test_setTabs_onlySelectedContentViewIsInHierarchy() {
        let controller = makeController()
        let tabs = [makeTab("home"), makeTab("search")]
        controller.setTabs(tabs, selectedIdentifier: "home", animated: false)

        present(controller)

        XCTAssertTrue(isContentViewInstalled(tabs[0], in: controller))
        XCTAssertFalse(isContentViewInstalled(tabs[1], in: controller))
    }

    func test_setTabs_removedTabIsDetached() {
        let controller = makeController()
        let removed = makeTab("search")
        controller.setTabs([makeTab("home"), removed], selectedIdentifier: nil, animated: false)

        controller.setTabs([makeTab("home")], selectedIdentifier: nil, animated: false)

        XCTAssertNil(removed.viewController.parent)
        XCTAssertEqual(controller.children.count, 1)
    }

    func test_setTabs_beforeViewLoads_installsContentOnLoad() {
        let controller = makeController()
        let tabs = [makeTab("home")]
        controller.setTabs(tabs, selectedIdentifier: nil, animated: false)

        XCTAssertFalse(controller.isViewLoaded, "setTabs 不應強制載入 view")
        loadWithoutPresenting(controller)

        XCTAssertTrue(isContentViewInstalled(tabs[0], in: controller))
    }
}

extension SetTabsTests {

    /// 回歸測試：同一個 identifier 換成新的 `TeroTab` 實例時，
    /// 舊的 view controller 必須被卸除，否則 child 會累積。
    func test_setTabs_replacingTabWithSameIdentifier_detachesOldViewController() {
        let controller = makeController()
        let original = makeTab("home")
        controller.setTabs([original], selectedIdentifier: nil, animated: false)
        present(controller)

        let replacement = makeTab("home")
        controller.setTabs([replacement], selectedIdentifier: nil, animated: false)

        XCTAssertNil(original.viewController.parent, "舊的 view controller 應被卸除")
        XCTAssertIdentical(replacement.viewController.parent, controller)
        XCTAssertEqual(controller.children.count, 1)
        XCTAssertTrue(isContentViewInstalled(replacement, in: controller))
        XCTAssertFalse(isContentViewInstalled(original, in: controller))
    }

    /// 選取的 identity 以 identifier 為準，因此替換實例不算選取變更、不發事件。
    func test_setTabs_replacingTabWithSameIdentifier_emitsNoDidSelect() {
        let controller = makeController()
        controller.setTabs([makeTab("home")], selectedIdentifier: nil, animated: false)
        recorder.didSelectCalls = []

        controller.setTabs([makeTab("home")], selectedIdentifier: nil, animated: false)

        XCTAssertTrue(recorder.didSelectCalls.isEmpty)
        XCTAssertEqual(controller.selectedTab?.identifier, "home")
    }
}
