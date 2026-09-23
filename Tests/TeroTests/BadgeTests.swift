import XCTest
@testable import Tero

/// 對應 ticket #23。Badge 的視覺（顏色、尺寸、位置）屬於目視驗收，
/// 這裡斷言的是可從公開 API 觀察到的語意：`accessibilityValue`。
final class BadgeTests: TeroTabBarControllerTestCase {

    private func makePresentedController() -> TeroTabBarController {
        let controller = makeController()
        controller.setTabs([makeTab("home"), makeTab("inbox")], selectedIdentifier: "home", animated: false)
        present(controller)
        return controller
    }

    // MARK: 語意

    func test_valueBadgeIsAnnounced() {
        let controller = makePresentedController()

        controller.setBadge(.value("99+"), forTabWithIdentifier: "inbox", animated: false)

        XCTAssertEqual(tabBarControl(for: "inbox", in: controller)?.accessibilityValue, "99+")
    }

    func test_valueBadgeAcceptsArbitraryStrings() {
        let controller = makePresentedController()

        for value in ["1", "99+", "NEW", "很多"] {
            controller.setBadge(.value(value), forTabWithIdentifier: "inbox", animated: false)
            XCTAssertEqual(tabBarControl(for: "inbox", in: controller)?.accessibilityValue, value)
        }
    }

    func test_dotBadgeIgnoresValue() {
        let controller = makePresentedController()
        let badge = TeroTabBadge()
        badge.style = .dot
        badge.value = "應被忽略"

        controller.setBadge(badge, forTabWithIdentifier: "inbox", animated: false)

        XCTAssertNil(
            tabBarControl(for: "inbox", in: controller)?.accessibilityValue,
            "`.dot` 忽略 value，因此沒有可播報的原始值"
        )
    }

    func test_settingBadgeToNilRemovesIt() {
        let controller = makePresentedController()
        controller.setBadge(.value("3"), forTabWithIdentifier: "inbox", animated: false)

        controller.setBadge(nil, forTabWithIdentifier: "inbox", animated: false)

        XCTAssertNil(tabBarControl(for: "inbox", in: controller)?.accessibilityValue)
        XCTAssertNil(controller.tabs[1].item.badge)
    }

    func test_setBadgeWritesThroughToTheItem() {
        let controller = makePresentedController()

        controller.setBadge(.value("7"), forTabWithIdentifier: "inbox", animated: false)

        XCTAssertEqual(controller.tabs[1].item.badge?.style, .value)
        XCTAssertEqual(controller.tabs[1].item.badge?.value, "7")
    }

    func test_setBadgeForUnknownIdentifierIsIgnored() {
        let controller = makePresentedController()

        controller.setBadge(.value("1"), forTabWithIdentifier: "nope", animated: false)

        XCTAssertNil(controller.tabs[0].item.badge)
        XCTAssertNil(controller.tabs[1].item.badge)
    }

    func test_badgeSurvivesTabSwitching() {
        let controller = makePresentedController()
        controller.setBadge(.value("5"), forTabWithIdentifier: "inbox", animated: false)

        controller.selectTab(withIdentifier: "inbox", animated: false)
        controller.selectTab(withIdentifier: "home", animated: false)

        XCTAssertEqual(tabBarControl(for: "inbox", in: controller)?.accessibilityValue, "5")
    }

    // MARK: 直接改 Item 之後 reload

    func test_mutatingItemThenReloadTabPicksUpTheBadge() {
        let controller = makePresentedController()

        controller.tabs[1].item.badge = .value("12")
        controller.reloadTab(withIdentifier: "inbox", animated: false)

        XCTAssertEqual(tabBarControl(for: "inbox", in: controller)?.accessibilityValue, "12")
    }

    func test_reloadAllTabsPicksUpEveryChange() {
        let controller = makePresentedController()

        controller.tabs[0].item.badge = .value("A")
        controller.tabs[1].item.badge = .value("B")
        controller.reloadAllTabs(animated: false)

        XCTAssertEqual(tabBarControl(for: "home", in: controller)?.accessibilityValue, "A")
        XCTAssertEqual(tabBarControl(for: "inbox", in: controller)?.accessibilityValue, "B")
    }

    func test_reloadTabPicksUpTitleEnabledAndAccessibilityChanges() {
        let controller = makePresentedController()

        controller.tabs[1].item.isEnabled = false
        controller.tabs[1].item.accessibilityLabel = "收件匣"
        controller.reloadTab(withIdentifier: "inbox", animated: false)

        let control = tabBarControl(for: "inbox", in: controller)
        XCTAssertEqual(control?.isEnabled, false)
        XCTAssertEqual(control?.accessibilityLabel, "收件匣")
    }

    func test_reloadTabDoesNotChangeSelection() {
        let controller = makePresentedController()
        recorder.didSelectCalls = []

        controller.reloadAllTabs(animated: false)

        XCTAssertEqual(controller.selectedTab?.identifier, "home")
        XCTAssertEqual(tabBarControl(for: "home", in: controller)?.isSelected, true)
        XCTAssertTrue(recorder.didSelectCalls.isEmpty)
    }

    func test_reloadTabForUnknownIdentifierIsIgnored() {
        let controller = makePresentedController()
        controller.reloadTab(withIdentifier: "nope", animated: false)
        XCTAssertEqual(controller.selectedTab?.identifier, "home")
    }

    // MARK: 工廠與模型

    func test_factoriesProduceOnlyValidCombinations() {
        XCTAssertEqual(TeroTabBadge.dot().style, .dot)
        XCTAssertNil(TeroTabBadge.dot().value)
        XCTAssertEqual(TeroTabBadge.value("x").style, .value)
        XCTAssertEqual(TeroTabBadge.value("x").value, "x")
    }

    func test_objectiveCStyleConstructionStillWorks() {
        // ObjC 端只有 style 與 value 兩個屬性可用
        let badge = TeroTabBadge()
        badge.style = .value
        badge.value = "42"

        let controller = makePresentedController()
        controller.setBadge(badge, forTabWithIdentifier: "inbox", animated: false)

        XCTAssertEqual(tabBarControl(for: "inbox", in: controller)?.accessibilityValue, "42")
    }
}

extension BadgeTests {

    /// 回歸測試：Badge 曾經以「內容上緣為中心」定位，導致一半被畫到 Bar 之外。
    /// 用公開 API 就能驗這個不變式——Item 控制項的所有可見子視圖都必須落在它自己的 bounds 內。
    func test_badgeStaysInsideTheItemBounds() {
        let controller = makePresentedController()
        controller.setBadge(.value("99+"), forTabWithIdentifier: "home", animated: false)
        controller.setBadge(.dot(), forTabWithIdentifier: "inbox", animated: false)
        controller.view.layoutIfNeeded()

        for identifier in ["home", "inbox"] {
            guard let control = tabBarControl(for: identifier, in: controller) else {
                return XCTFail("找不到 \(identifier)")
            }
            XCTAssertFalse(control.bounds.isEmpty)
            for subview in control.subviews where !subview.isHidden {
                XCTAssertTrue(
                    control.bounds.insetBy(dx: -0.5, dy: -0.5).contains(subview.frame),
                    "\(identifier) 的 \(type(of: subview)) frame \(subview.frame) 超出 bounds \(control.bounds)"
                )
            }
        }
    }

    func test_badgeStaysInsideBoundsWhenItemIsNarrow() {
        let controller = makeController()
        controller.setTabs(
            (0..<5).map { makeTab("t\($0)") },
            selectedIdentifier: "t0",
            animated: false
        )
        present(controller)
        controller.setBadge(.value("1234"), forTabWithIdentifier: "t4", animated: false)
        controller.view.layoutIfNeeded()

        guard let control = tabBarControl(for: "t4", in: controller) else { return XCTFail() }
        for subview in control.subviews where !subview.isHidden {
            XCTAssertTrue(
                control.bounds.insetBy(dx: -0.5, dy: -0.5).contains(subview.frame),
                "窄 Item 上的長 Badge 也不該溢出：\(subview.frame) vs \(control.bounds)"
            )
        }
    }
}
