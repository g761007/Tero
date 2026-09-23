import XCTest
@testable import Tero

/// 對應 ticket #24：上限依 `horizontalSizeClass` 而非裝置類型選用。
final class SizeClassTests: TeroTabBarControllerTestCase {

    private func makeConfiguredController() -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = 3
        configuration.regular.maximumVisibleItems = 6
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<6).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        return controller
    }

    func test_compactUsesCompactLimit() {
        let controller = makeConfiguredController()
        presentWithSizeClass(controller, .compact)

        XCTAssertEqual(controller.visibleTabs.count, 2, "上限 3 含 More，因此可見 2 個")
        XCTAssertEqual(controller.overflowTabs.count, 4)
    }

    func test_regularUsesRegularLimit() {
        let controller = makeConfiguredController()
        presentWithSizeClass(controller, .regular)

        XCTAssertEqual(controller.visibleTabs.count, 6, "上限 6 且剛好 6 個 Tab，全部顯示")
        XCTAssertTrue(controller.overflowTabs.isEmpty)
    }

    func test_sizeClassChangeAtRuntimeRecomputesThePartition() {
        let controller = makeConfiguredController()
        let host = presentWithSizeClass(controller, .regular)
        XCTAssertEqual(controller.visibleTabs.count, 6)

        // 模擬進入 Slide Over：iPad 上也會變成 compact
        host.override(horizontalSizeClass: .compact)

        XCTAssertEqual(controller.visibleTabs.count, 2)
        XCTAssertEqual(controller.overflowTabs.count, 4)
        XCTAssertNotNil(tabBarControl(for: "more", in: controller))
    }

    func test_sizeClassChangeDoesNotChangeSelection() {
        let controller = makeConfiguredController()
        let host = presentWithSizeClass(controller, .regular)
        controller.selectTab(withIdentifier: "t5", animated: false)
        recorder.didSelectCalls = []

        // t5 從「直接可見」變成「溢位」
        host.override(horizontalSizeClass: .compact)

        XCTAssertEqual(controller.selectedTab?.identifier, "t5", "選取狀態不該改變")
        XCTAssertEqual(controller.selectedIndex, 5)
        XCTAssertTrue(recorder.didSelectCalls.isEmpty, "只有顯示位置變了，不是選取變更")
        XCTAssertTrue(controller.overflowTabs.contains { $0.identifier == "t5" })
        XCTAssertEqual(tabBarControl(for: "more", in: controller)?.isSelected, true)
    }

    func test_sizeClassChangeBackRestoresVisibility() {
        let controller = makeConfiguredController()
        let host = presentWithSizeClass(controller, .compact)
        controller.selectTab(withIdentifier: "t5", animated: false)

        host.override(horizontalSizeClass: .regular)

        XCTAssertEqual(controller.visibleTabs.count, 6)
        XCTAssertEqual(controller.selectedTab?.identifier, "t5")
        XCTAssertEqual(tabBarControl(for: "t5", in: controller)?.isSelected, true)
    }
}
