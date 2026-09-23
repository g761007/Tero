import XCTest
@testable import Tero

final class PublicAPIShapeTests: TeroTabBarControllerTestCase {

    // MARK: Style 解析（計畫書 §13、ADR-0002）

    func test_effectiveStyleFollowsOSVersion() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        let controller = TeroTabBarController(configuration: configuration)

        XCTAssertEqual(controller.requestedStyle, .floatingGlass, "要求的 Style 必須原樣回報")

        if #available(iOS 26, *) {
            XCTAssertEqual(controller.tabBarStyle, .floatingGlass)
        } else {
            XCTAssertEqual(controller.tabBarStyle, .classic, "iOS 26 以下一律降級")
        }
    }

    func test_classicIsNeverUpgraded() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .classic
        let controller = TeroTabBarController(configuration: configuration)

        XCTAssertEqual(controller.requestedStyle, .classic)
        XCTAssertEqual(controller.tabBarStyle, .classic)
    }

    func test_tabBarReflectsEffectiveStyle() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        let controller = TeroTabBarController(configuration: configuration)

        XCTAssertEqual(controller.tabBar.style, controller.tabBarStyle)
        XCTAssertEqual(controller.tabBar.presentationState, .expanded)
    }

    // MARK: 預設狀態

    func test_freshControllerHasNoSelection() {
        let controller = makeController()

        XCTAssertTrue(controller.tabs.isEmpty)
        XCTAssertNil(controller.selectedTab)
        XCTAssertEqual(controller.selectedIndex, NSNotFound)
        XCTAssertNil(controller.selectedTabIndex)
        XCTAssertNil(controller.actionItem)
        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_convenienceInitUsesDefaultConfiguration() {
        let controller = TeroTabBarController()

        XCTAssertEqual(controller.requestedStyle, .classic)
        XCTAssertEqual(controller.currentConfiguration().compact.maximumVisibleItems, 5)
        XCTAssertEqual(controller.currentConfiguration().regular.maximumVisibleItems, 6)
    }

    // MARK: Model

    func test_itemAccessibilityPropertiesRoundTrip() {
        let item = TeroTabItem(title: "Home", image: nil, selectedImage: nil)

        item.accessibilityLabel = "首頁"
        item.accessibilityIdentifier = "tab.home"

        XCTAssertEqual(item.accessibilityLabel, "首頁", "accessibilityLabel 繼承自 NSObject，必須真的能存值")
        XCTAssertEqual(item.accessibilityIdentifier, "tab.home")
    }

    func test_itemDefaultsToEnabled() {
        XCTAssertTrue(TeroTabItem(title: nil, image: nil, selectedImage: nil).isEnabled)
    }

    func test_badgeFactoriesProduceValidCombinations() {
        let dot = TeroTabBadge.dot()
        XCTAssertEqual(dot.style, .dot)
        XCTAssertNil(dot.value)

        let value = TeroTabBadge.value("99+")
        XCTAssertEqual(value.style, .value)
        XCTAssertEqual(value.value, "99+")
    }

    func test_badgeCopyIsIndependent() {
        let badge = TeroTabBadge.value("3")
        let copy = badge.copy() as! TeroTabBadge

        badge.value = "4"

        XCTAssertEqual(copy.value, "3")
    }

    func test_tabIdentityIsImmutableAndDistinctFromPresentation() {
        let item = TeroTabItem(title: "Home", image: nil, selectedImage: nil)
        let tab = TeroTab(identifier: "home", viewController: UIViewController(), item: item)

        // presentation 可變
        tab.item.title = "首頁"
        tab.item.badge = .dot()

        XCTAssertEqual(tab.identifier, "home")
        XCTAssertEqual(tab.item.title, "首頁")
        XCTAssertIdentical(tab.item, item)
    }

    // MARK: Main thread（計畫書 §51）

    func test_apiCalledOffMainThreadIsReported() {
        let controller = makeController()
        let done = expectation(description: "off-main")

        DispatchQueue.global().async {
            // 無 Tab，因此這次呼叫只會走到 assert 與 guard，不動任何 UIKit 狀態
            _ = controller.selectTab(withIdentifier: "nope", animated: false)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)

        XCTAssertEqual(reportedDiagnostics.count, 1)
        XCTAssertTrue(reportedDiagnostics[0].contains("main thread"))
    }
}
