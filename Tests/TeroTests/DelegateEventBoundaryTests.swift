import XCTest
@testable import Tero

/// 對應計畫書 §36。這些「不該發事件」的規則，是 Analytics 不被灌水的依據。
final class DelegateEventBoundaryTests: TeroTabBarControllerTestCase {

    func test_firstSelectionFromSetTabs_emitsDidSelectWithInitialSource() {
        let controller = makeController()

        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: nil, animated: false)

        XCTAssertEqual(recorder.didSelectCalls.count, 1)
        XCTAssertEqual(recorder.didSelectCalls.first?.identifier, "home")
        XCTAssertEqual(recorder.didSelectCalls.first?.source, .initial)
    }

    func test_initialSelection_doesNotConsultShouldSelect() {
        let controller = makeController()
        recorder.shouldSelectResult = false

        controller.setTabs([makeTab("home")], selectedIdentifier: nil, animated: false)

        XCTAssertTrue(recorder.shouldSelectCalls.isEmpty, "初始選取不允許被 delegate 阻止")
        XCTAssertEqual(controller.selectedTab?.identifier, "home")
    }

    func test_setTabsPreservingSameSelection_emitsNoDidSelect() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "search", animated: false)
        recorder.didSelectCalls = []

        controller.setTabs(
            [makeTab("home"), makeTab("search"), makeTab("profile")],
            selectedIdentifier: nil,
            animated: false
        )

        XCTAssertEqual(controller.selectedTab?.identifier, "search")
        XCTAssertTrue(recorder.didSelectCalls.isEmpty, "選取未改變就不該發事件")
    }

    func test_setTabsWithEmptyArray_emitsNoEvents() {
        let controller = makeController()
        controller.setTabs([makeTab("home")], selectedIdentifier: nil, animated: false)
        recorder.didSelectCalls = []
        recorder.didReselectCalls = []

        controller.setTabs([], selectedIdentifier: nil, animated: false)

        XCTAssertTrue(recorder.didSelectCalls.isEmpty)
        XCTAssertTrue(recorder.didReselectCalls.isEmpty)
    }

    func test_programmaticSelect_consultsShouldSelectWithProgrammaticSource() {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("search")], selectedIdentifier: "home", animated: false)
        recorder.shouldSelectCalls = []

        controller.selectTab(withIdentifier: "search", animated: false)

        XCTAssertEqual(recorder.shouldSelectCalls.count, 1)
        XCTAssertEqual(recorder.shouldSelectCalls.first?.source, .programmatic)
        XCTAssertEqual(recorder.didSelectCalls.last?.source, .programmatic)
    }

    func test_programmaticSelectOfSelectedTab_emitsNoDidReselect() {
        let controller = makeController()
        controller.setTabs([makeTab("home")], selectedIdentifier: nil, animated: false)
        recorder.didReselectCalls = []

        XCTAssertTrue(controller.selectTab(withIdentifier: "home", animated: false))

        XCTAssertTrue(
            recorder.didReselectCalls.isEmpty,
            "didReselect 專屬於使用者互動；程式呼叫觸發會造成非預期的導覽重置"
        )
    }

    /// 使用者點擊路徑目前只有內部入口；#22 接上 Tab Bar 之後會改由公開的點擊路徑驅動。
    func test_userSelectOfSelectedTab_emitsDidReselect() {
        let controller = makeController()
        let tabs = [makeTab("home")]
        controller.setTabs(tabs, selectedIdentifier: nil, animated: false)
        recorder.didReselectCalls = []

        XCTAssertTrue(controller.select(tabs[0], at: 0, source: .user, animated: false))

        XCTAssertEqual(recorder.didReselectCalls, ["home"])
        XCTAssertTrue(recorder.didSelectCalls.filter { $0.source == .user }.isEmpty)
    }
}
