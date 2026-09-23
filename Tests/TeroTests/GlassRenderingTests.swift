import XCTest
@testable import Tero

/// 對應 ticket #28。`UIGlassEffect` 與 `UIGlassContainerEffect` 都是公開型別，
/// 因此可以直接斷言 Bar 上掛的是哪一種效果，不需要內部存取。
final class GlassRenderingTests: TeroTabBarControllerTestCase {

    private var isGlassAvailable: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    private func makeFloatingController(
        tint: TeroTabGlassTintMode = .automatic,
        tintColor: UIColor? = nil,
        spacing: CGFloat? = nil,
        withAction: Bool = true
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.floatingGlassAppearance.glassTintMode = tint
        configuration.floatingGlassAppearance.glassTintColor = tintColor
        if let spacing { configuration.floatingGlassAppearance.glassContainerSpacing = spacing }
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<3).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        if withAction {
            let action = TeroTabActionItem(identifier: "compose", image: UIImage(systemName: "plus"))
            action.accessibilityIdentifier = "tab.compose"
            controller.setActionItem(action, animated: false)
        }
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func tabsCapsule(in controller: TeroTabBarController) -> UIVisualEffectView? {
        guard let control = tabBarControl(for: "t0", in: controller) else { return nil }
        return capsule(containing: control, in: controller)
    }

    private func actionCapsule(in controller: TeroTabBarController) -> UIVisualEffectView? {
        guard let control = tabBarControl(for: "compose", in: controller) else { return nil }
        return capsule(containing: control, in: controller)
    }

    // MARK: 玻璃效果

    func test_floatingCapsulesUseSystemGlass() throws {
        try XCTSkipUnless(isGlassAvailable)
        guard #available(iOS 26, *) else { return }
        let controller = makeFloatingController()

        XCTAssertTrue(tabsCapsule(in: controller)?.effect is UIGlassEffect)
        XCTAssertTrue(actionCapsule(in: controller)?.effect is UIGlassEffect)
    }

    func test_glassIsInteractive() throws {
        try XCTSkipUnless(isGlassAvailable)
        guard #available(iOS 26, *) else { return }
        let controller = makeFloatingController()

        let glass = tabsCapsule(in: controller)?.effect as? UIGlassEffect
        XCTAssertEqual(glass?.isInteractive, true)
    }

    func test_automaticTintLeavesTintColorUnset() throws {
        try XCTSkipUnless(isGlassAvailable)
        guard #available(iOS 26, *) else { return }
        let controller = makeFloatingController(tint: .automatic, tintColor: .systemPink)

        let glass = tabsCapsule(in: controller)?.effect as? UIGlassEffect
        XCTAssertNil(glass?.tintColor, "`.automatic` 使用 Liquid Glass 自身的 backdrop adaptation")
    }

    func test_tintedModeAppliesTheTintColour() throws {
        try XCTSkipUnless(isGlassAvailable)
        guard #available(iOS 26, *) else { return }
        let controller = makeFloatingController(tint: .tinted, tintColor: .systemPink)

        let glass = tabsCapsule(in: controller)?.effect as? UIGlassEffect
        XCTAssertEqual(glass?.tintColor, .systemPink)
        let actionGlass = actionCapsule(in: controller)?.effect as? UIGlassEffect
        XCTAssertEqual(actionGlass?.tintColor, .systemPink)
    }

    // MARK: 玻璃容器

    func test_tabsAndActionShareOneGlassContainer() throws {
        try XCTSkipUnless(isGlassAvailable)
        guard #available(iOS 26, *) else { return }
        let controller = makeFloatingController()

        guard let tabs = tabsCapsule(in: controller),
              let action = actionCapsule(in: controller) else { return XCTFail() }

        let tabsContainer = glassContainer(around: tabs, in: controller)
        let actionContainer = glassContainer(around: action, in: controller)

        XCTAssertNotNil(tabsContainer)
        XCTAssertIdentical(tabsContainer, actionContainer, "兩者必須在同一個玻璃容器內才會融合")
        XCTAssertTrue(tabsContainer?.effect is UIGlassContainerEffect)
    }

    func test_containerSpacingComesFromAppearance() throws {
        try XCTSkipUnless(isGlassAvailable)
        guard #available(iOS 26, *) else { return }
        let controller = makeFloatingController(spacing: 33)

        guard let tabs = tabsCapsule(in: controller),
              let container = glassContainer(around: tabs, in: controller),
              let effect = container.effect as? UIGlassContainerEffect else {
            return XCTFail("應有玻璃容器")
        }
        XCTAssertEqual(effect.spacing, 33, accuracy: 0.01)
    }

    // MARK: Classic 不使用玻璃

    func test_classicUsesBlurNotGlass() {
        let controller = makeController()
        controller.setTabs([makeTab("a")], selectedIdentifier: nil, animated: false)
        present(controller)
        controller.view.layoutIfNeeded()

        guard let control = tabBarControl(for: "a", in: controller),
              let capsule = capsule(containing: control, in: controller) else { return XCTFail() }

        XCTAssertTrue(capsule.effect is UIBlurEffect, "Classic 的模糊是它自己的外觀，不是玻璃的仿製")
        if #available(iOS 26, *) {
            XCTAssertFalse(capsule.effect is UIGlassEffect)
        }
    }

    func test_classicWithoutBlurUsesSolidColour() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.classicAppearance.usesBlurEffect = false
        configuration.classicAppearance.backgroundColor = .systemPink
        let controller = makeController(configuration: configuration)
        controller.setTabs([makeTab("a")], selectedIdentifier: nil, animated: false)
        present(controller)
        controller.view.layoutIfNeeded()

        guard let control = tabBarControl(for: "a", in: controller),
              let capsule = capsule(containing: control, in: controller) else { return XCTFail() }
        XCTAssertNil(capsule.effect)
        XCTAssertEqual(capsule.contentView.backgroundColor, .systemPink)
    }

    // MARK: 降級

    func test_requestedStyleIsReportedEvenWhenDowngraded() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        let controller = TeroTabBarController(configuration: configuration)

        XCTAssertEqual(controller.requestedStyle, .floatingGlass)
        if #available(iOS 26, *) {
            XCTAssertEqual(controller.tabBarStyle, .floatingGlass)
        } else {
            XCTAssertEqual(controller.tabBarStyle, .classic)
            XCTAssertEqual(controller.tabBar.style, .classic)
        }
    }

    func test_floatingPathNeverUsesBlur() throws {
        try XCTSkipUnless(isGlassAvailable)
        guard #available(iOS 26, *) else { return }
        let controller = makeFloatingController()

        XCTAssertFalse(tabsCapsule(in: controller)?.effect is UIBlurEffect)
        XCTAssertFalse(actionCapsule(in: controller)?.effect is UIBlurEffect)
    }

    // MARK: 狀態切換後仍是玻璃

    func test_glassSurvivesMinimizing() throws {
        try XCTSkipUnless(isGlassAvailable)
        guard #available(iOS 26, *) else { return }
        let controller = makeFloatingController()

        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertTrue(tabsCapsule(in: controller)?.effect is UIGlassEffect)
        XCTAssertTrue(actionCapsule(in: controller)?.effect is UIGlassEffect)
    }
}
