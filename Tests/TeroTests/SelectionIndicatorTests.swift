import XCTest
@testable import Tero

/// 對應 ticket #37 的選取外框。
final class SelectionIndicatorTests: TeroTabBarControllerTestCase {

    private func makeController(
        floating: Bool,
        indicator: TeroTabSelectionIndicatorStyle = .automatic,
        tabCount: Int = 3,
        limit: Int = 6,
        mutate: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        if floating { configuration.style = .floatingGlass }
        configuration.compact.maximumVisibleItems = limit
        configuration.itemAppearance.selectionIndicatorStyle = indicator
        mutate(configuration)
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<tabCount).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func indicator(in controller: TeroTabBarController) -> TeroTabSelectionIndicatorView? {
        func search(_ view: UIView) -> TeroTabSelectionIndicatorView? {
            if let indicator = view as? TeroTabSelectionIndicatorView { return indicator }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(controller.tabBar)
    }

    private var isFloatingAvailable: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    // MARK: 顯示時機

    func test_automaticShowsOnFloatingGlass() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        XCTAssertEqual(indicator(in: controller)?.isHidden, false)
    }

    func test_automaticHidesOnClassic() {
        let controller = makeController(floating: false)

        XCTAssertEqual(indicator(in: controller)?.isHidden, true, "貼底滿版的 Classic 沒有這個外框")
    }

    func test_alwaysShowsOnClassicToo() {
        let controller = makeController(floating: false, indicator: .always)

        XCTAssertEqual(indicator(in: controller)?.isHidden, false)
    }

    func test_neverHidesOnFloatingGlass() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true, indicator: .never)

        XCTAssertEqual(indicator(in: controller)?.isHidden, true)
    }

    // MARK: 跟隨選取

    func test_indicatorSitsBehindTheSelectedItem() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        guard let frame = indicator(in: controller)?.frame,
              let selected = tabBarControl(for: "t0", in: controller) else { return XCTFail() }

        XCTAssertEqual(frame.midX, selected.frame.midX, accuracy: 1.0)
        XCTAssertEqual(frame.midY, selected.frame.midY, accuracy: 1.0)
    }

    func test_indicatorFollowsSelection() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        controller.selectTab(withIdentifier: "t2", animated: false)
        controller.view.layoutIfNeeded()

        guard let frame = indicator(in: controller)?.frame,
              let selected = tabBarControl(for: "t2", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, selected.frame.midX, accuracy: 1.0)
    }

    func test_indicatorMovesToMoreWhenOverflowTabIsSelected() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true, tabCount: 8, limit: 4)

        controller.select(controller.tabs[6], at: 6, source: .overflow, animated: false)
        controller.view.layoutIfNeeded()

        guard let frame = indicator(in: controller)?.frame,
              let more = tabBarControl(for: "more", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, more.frame.midX, accuracy: 1.0)
    }

    func test_indicatorHidesWithNoTabs() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        controller.setTabs([], selectedIdentifier: nil, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(indicator(in: controller)?.isHidden, true)
    }

    // MARK: 外觀

    func test_solidMaterialUsesConfiguredColour() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true) {
            $0.itemAppearance.selectionIndicatorMaterial = .solid
            $0.itemAppearance.selectionIndicatorColor = .systemPink
        }

        XCTAssertEqual(indicator(in: controller)?.contentView.backgroundColor, .systemPink)
    }

    // MARK: 材質

    func test_automaticUsesSolidOnFloatingGlass() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        // 靜止的選取不顯示 liquid glass：玻璃材質會在邊界外暈開一圈柔邊，
        // 把內縮的 gap 填掉、邊緣也糊掉。移動中的玻璃由另一層透鏡負責（ADR-0010）。
        XCTAssertNil(indicator(in: controller)?.effect)
        XCTAssertNotNil(indicator(in: controller)?.contentView.backgroundColor)
    }

    func test_automaticUsesSolidOnClassic() {
        let controller = makeController(floating: false, indicator: .always)

        XCTAssertNil(indicator(in: controller)?.effect)
        XCTAssertNotNil(indicator(in: controller)?.contentView.backgroundColor)
    }

    func test_explicitGlassOnClassicStillUsesGlass() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: false, indicator: .always) {
            $0.itemAppearance.selectionIndicatorMaterial = .glass
        }

        guard #available(iOS 26, *) else { return }
        XCTAssertTrue(indicator(in: controller)?.effect is UIGlassEffect)
    }

    func test_reduceTransparencyFallsBackToSolid() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceTransparency: true)
        let controller = makeController(floating: true) {
            $0.itemAppearance.selectionIndicatorMaterial = .glass
            $0.itemAppearance.selectionIndicatorColor = .systemPink
        }

        XCTAssertNil(indicator(in: controller)?.effect, "降低透明度時不用玻璃")
        XCTAssertEqual(indicator(in: controller)?.contentView.backgroundColor, .systemPink)
    }

    func test_glassUsesTheGlassTintNotTheSolidColour() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true) {
            $0.itemAppearance.selectionIndicatorMaterial = .glass
            $0.itemAppearance.selectionIndicatorColor = .systemPink
            $0.itemAppearance.selectionIndicatorGlassTint = .systemTeal
        }

        guard #available(iOS 26, *) else { return }
        let glass = indicator(in: controller)?.effect as? UIGlassEffect
        XCTAssertEqual(glass?.tintColor, .systemTeal, "玻璃吃 glassTint，不吃實色的顏色")
    }

    func test_glassIndicatorDoesNotTakeTouches() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        XCTAssertEqual(indicator(in: controller)?.isUserInteractionEnabled, false)
    }

    // MARK: 逐格尺寸

    func test_itemCanRequestItsOwnSelectionWidth() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)
        controller.tabs[1].item.selectionSize = CGSize(width: 30, height: 24)
        controller.setTabs(controller.tabs, selectedIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t1", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.width, 30, accuracy: 1.0)
        XCTAssertEqual(frame.height, 24, accuracy: 1.0)
        XCTAssertEqual(frame.midX, item.frame.midX, accuracy: 1.0, "仍以格位中心對齊")
    }

    func test_neighbouringTabsKeepTheirOwnSelectionWidths() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)
        controller.tabs[1].item.selectionSize = CGSize(width: 30, height: 24)
        controller.setTabs(controller.tabs, selectedIdentifier: "t0", animated: false)
        controller.view.layoutIfNeeded()
        let defaultWidth = indicator(in: controller)?.frame.width

        controller.selectTab(withIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNotEqual(defaultWidth, 30)
        guard let width = indicator(in: controller)?.frame.width else { return XCTFail() }
        XCTAssertEqual(width, 30, accuracy: 1.0)
    }

    func test_requestedSelectionSizeIsClampedToTheSlot() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)
        controller.tabs[0].item.selectionSize = CGSize(width: 9999, height: 9999)
        controller.setTabs(controller.tabs, selectedIdentifier: "t0", animated: false)
        controller.view.layoutIfNeeded()

        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        XCTAssertLessThanOrEqual(frame.width, item.frame.width)
        XCTAssertLessThanOrEqual(frame.height, item.frame.height)
    }

    func test_indicatorDefaultsToACapsule() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        guard let view = indicator(in: controller) else { return XCTFail() }
        XCTAssertEqual(view.layer.cornerRadius, view.bounds.height / 2, accuracy: 0.5)
    }

    func test_indicatorUsesExplicitCornerRadius() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true) {
            $0.itemAppearance.selectionIndicatorCornerRadius = 6
        }

        XCTAssertEqual(indicator(in: controller)?.layer.cornerRadius, 6)
    }

    func test_indicatorRespectsInsets() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let insets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        let controller = makeController(floating: true) {
            $0.itemAppearance.selectionIndicatorInsets = insets
        }

        guard let frame = indicator(in: controller)?.frame,
              let selected = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.width, selected.frame.width - insets.left - insets.right, accuracy: 1.0)
        XCTAssertEqual(frame.height, selected.frame.height - insets.top - insets.bottom, accuracy: 1.0)
    }

    func test_indicatorIsBehindTheItemViews() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        guard let view = indicator(in: controller),
              let container = view.superview,
              let item = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        let indicatorIndex = container.subviews.firstIndex(of: view)
        let itemIndex = container.subviews.firstIndex(of: item)
        XCTAssertNotNil(indicatorIndex)
        XCTAssertNotNil(itemIndex)
        XCTAssertLessThan(indicatorIndex!, itemIndex!, "外框必須襯在項目底下")
    }

    func test_indicatorDoesNotInterceptTouches() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)

        XCTAssertEqual(indicator(in: controller)?.isUserInteractionEnabled, false)
    }

    // MARK: 最小化

    func test_indicatorRelayoutsWhenMinimized() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeController(floating: true)
        guard let expanded = indicator(in: controller)?.frame else { return XCTFail() }

        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        guard let view = indicator(in: controller) else { return XCTFail() }
        XCTAssertLessThan(view.frame.height, expanded.height)
        XCTAssertEqual(view.transform, .identity, "重新排版，不是縮放")
    }
}
