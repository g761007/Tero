import XCTest
@testable import Tero

/// 對應 ticket #32 與 ADR-0006。
final class AccessibilityTests: TeroTabBarControllerTestCase {

    private func makePresentedController(
        floating: Bool = false,
        tabCount: Int = 3
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        if floating { configuration.style = .floatingGlass }
        configuration.compact.maximumVisibleItems = 6
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<tabCount).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    // MARK: VoiceOver

    func test_barCarriesTheTabBarTraitSoTheSystemAnnouncesPosition() {
        let controller = makePresentedController()

        XCTAssertTrue(controller.tabBar.accessibilityTraits.contains(.tabBar))
        XCTAssertFalse(controller.tabBar.isAccessibilityElement, "子項目必須各自可達")
    }

    func test_eachTabIsAnAccessibilityElementWithAButtonTrait() {
        let controller = makePresentedController()

        for index in 0..<3 {
            guard let control = tabBarControl(for: "t\(index)", in: controller) else {
                return XCTFail("t\(index) 不可達")
            }
            XCTAssertTrue(control.accessibilityTraits.contains(.button))
        }
    }

    func test_selectedTabCarriesTheSelectedTrait() {
        let controller = makePresentedController()

        XCTAssertTrue(tabBarControl(for: "t0", in: controller)!.accessibilityTraits.contains(.selected))
        XCTAssertFalse(tabBarControl(for: "t1", in: controller)!.accessibilityTraits.contains(.selected))

        controller.selectTab(withIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertFalse(tabBarControl(for: "t0", in: controller)!.accessibilityTraits.contains(.selected))
        XCTAssertTrue(tabBarControl(for: "t1", in: controller)!.accessibilityTraits.contains(.selected))
    }

    func test_disabledTabCarriesTheNotEnabledTrait() {
        let controller = makeController()
        controller.setTabs([makeTab("open"), makeTab("locked", enabled: false)], selectedIdentifier: nil, animated: false)
        present(controller)

        XCTAssertTrue(tabBarControl(for: "locked", in: controller)!.accessibilityTraits.contains(.notEnabled))
    }

    func test_labelDefaultsToTitleAndCanBeOverridden() {
        let controller = makeController()
        let plain = makeTab("plain")
        let overridden = makeTab("overridden")
        overridden.item.accessibilityLabel = "自訂名稱"
        controller.setTabs([plain, overridden], selectedIdentifier: nil, animated: false)
        present(controller)

        XCTAssertEqual(tabBarControl(for: "plain", in: controller)?.accessibilityLabel, "plain")
        XCTAssertEqual(tabBarControl(for: "overridden", in: controller)?.accessibilityLabel, "自訂名稱")
    }

    // MARK: Badge 的播報

    func test_valueBadgeIsAnnouncedByDefault() {
        let controller = makePresentedController()

        controller.setBadge(.value("5"), forTabWithIdentifier: "t1", animated: false)

        XCTAssertEqual(tabBarControl(for: "t1", in: controller)?.accessibilityValue, "5")
    }

    func test_dotBadgeIsSilentUnlessTheConsumerSuppliesWording() {
        let controller = makePresentedController()

        controller.setBadge(.dot(), forTabWithIdentifier: "t1", animated: false)
        XCTAssertNil(
            tabBarControl(for: "t1", in: controller)?.accessibilityValue,
            "圓點沒有原始值，套件也不得夾帶字串"
        )

        let spoken = TeroTabBadge.dot()
        spoken.accessibilityValue = "有未讀訊息"
        controller.setBadge(spoken, forTabWithIdentifier: "t1", animated: false)

        XCTAssertEqual(tabBarControl(for: "t1", in: controller)?.accessibilityValue, "有未讀訊息")
    }

    func test_consumerWordingOverridesTheRawValue() {
        let controller = makePresentedController()
        let badge = TeroTabBadge.value("5")
        badge.accessibilityValue = "5 則新訊息"

        controller.setBadge(badge, forTabWithIdentifier: "t1", animated: false)

        XCTAssertEqual(tabBarControl(for: "t1", in: controller)?.accessibilityValue, "5 則新訊息")
    }

    func test_badgeAccessibilityValueSurvivesCopying() {
        let badge = TeroTabBadge.dot()
        badge.accessibilityValue = "有未讀"

        let copy = badge.copy() as! TeroTabBadge

        XCTAssertEqual(copy.accessibilityValue, "有未讀")
    }

    // MARK: 右至左

    func test_rightToLeftMirrorsTabOrder() {
        let controller = makePresentedController()
        let leftToRight = (0..<3).compactMap { tabBarControl(for: "t\($0)", in: controller)?.frame.minX }
        XCTAssertEqual(leftToRight, leftToRight.sorted(), "LTR 下 t0 最左")

        controller.tabBar.semanticContentAttribute = .forceRightToLeft
        controller.tabBar.setNeedsLayout()
        controller.tabBar.layoutIfNeeded()

        let rightToLeft = (0..<3).compactMap { tabBarControl(for: "t\($0)", in: controller)?.frame.minX }
        XCTAssertEqual(rightToLeft, rightToLeft.sorted(by: >), "RTL 下 t0 最右")
    }

    func test_rightToLeftMirrorsBadgeOffsetHorizontally() {
        let controller = makePresentedController()
        let badge = TeroTabBadge.value("1")
        badge.offset = CGPoint(x: 10, y: 0)
        controller.setBadge(badge, forTabWithIdentifier: "t0", animated: false)
        controller.view.layoutIfNeeded()

        guard let control = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        let ltrBadgeX = control.subviews.compactMap { $0 as? TeroTabBadgeView }.first?.frame.minX

        controller.tabBar.semanticContentAttribute = .forceRightToLeft
        controller.reloadAllTabs(animated: false)
        controller.tabBar.layoutIfNeeded()

        guard let rtlControl = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        let rtlBadgeX = rtlControl.subviews.compactMap { $0 as? TeroTabBadgeView }.first?.frame.minX

        XCTAssertNotNil(ltrBadgeX)
        XCTAssertNotNil(rtlBadgeX)
        XCTAssertNotEqual(ltrBadgeX, rtlBadgeX, "位移的水平方向應取反")
    }

    func test_customContentIsNeverTransformed() {
        final class Provider: NSObject, TeroTabContentProvider {
            let view = UIView()
            func makeContentView() -> UIView { view }
        }
        let provider = Provider()
        let controller = makeController()
        let item = TeroTabItem(title: "a", image: nil, selectedImage: nil)
        item.accessibilityIdentifier = "tab.a"
        item.contentProvider = provider
        controller.setTabs(
            [TeroTab(identifier: "a", viewController: UIViewController(), item: item)],
            selectedIdentifier: nil,
            animated: false
        )
        present(controller)

        controller.tabBar.semanticContentAttribute = .forceRightToLeft
        controller.tabBar.layoutIfNeeded()

        XCTAssertEqual(provider.view.transform, .identity, "Provider 的 view 內部鏡像由 consumer 自理")
    }

    // MARK: 降低透明度

    func test_reduceTransparencyMakesClassicOpaque() {
        overrideAccessibility(reduceTransparency: true)
        let controller = makePresentedController()

        guard let control = tabBarControl(for: "t0", in: controller),
              let capsule = capsule(containing: control, in: controller) else { return XCTFail() }

        XCTAssertNil(capsule.effect, "不該再用模糊")
        let alpha = capsule.contentView.backgroundColor?.cgColor.alpha ?? 0
        XCTAssertEqual(alpha, 1, accuracy: 0.001, "應為不透明實色")
    }

    func test_reduceTransparencyMakesGlassOpaque() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        overrideAccessibility(reduceTransparency: true)
        let controller = makePresentedController(floating: true)

        guard let control = tabBarControl(for: "t0", in: controller),
              let capsule = capsule(containing: control, in: controller) else { return XCTFail() }

        XCTAssertFalse(capsule.effect is UIGlassEffect)
        XCTAssertNil(capsule.effect)
        let alpha = capsule.contentView.backgroundColor?.cgColor.alpha ?? 0
        XCTAssertEqual(alpha, 1, accuracy: 0.001)
    }

    func test_reduceTransparencyUsesTintWhenTinted() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        overrideAccessibility(reduceTransparency: true)
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.floatingGlassAppearance.glassTintMode = .tinted
        configuration.floatingGlassAppearance.glassTintColor = UIColor.systemTeal.withAlphaComponent(0.3)
        let controller = makeController(configuration: configuration)
        controller.setTabs([makeTab("t0")], selectedIdentifier: nil, animated: false)
        present(controller)
        controller.view.layoutIfNeeded()

        guard let control = tabBarControl(for: "t0", in: controller),
              let capsule = capsule(containing: control, in: controller) else { return XCTFail() }
        let alpha = capsule.contentView.backgroundColor?.cgColor.alpha ?? 0
        XCTAssertEqual(alpha, 1, accuracy: 0.001, "tint 應轉為不透明版本")
    }

    func test_noExtraKnobIsIntroducedForReducedTransparency() {
        // 顏色自動衍生：設定物件上沒有任何 reducedTransparency 相關屬性
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        let mirror = Mirror(reflecting: configuration.floatingGlassAppearance)
        let names = mirror.children.compactMap(\.label).map { $0.lowercased() }
        XCTAssertFalse(names.contains { $0.contains("reduce") || $0.contains("opaque") })
    }

    // MARK: 減少動態效果

    func test_reduceMotionDisablesAnimationsAndTellsTheProvider() {
        final class Provider: NSObject, TeroTabContentProvider {
            var animatedFlags: [Bool] = []
            func makeContentView() -> UIView { UIView() }
            func updateContentView(
                _ contentView: UIView,
                selected: Bool,
                presentationState: TeroTabBarPresentationState,
                animated: Bool
            ) { animatedFlags.append(animated) }
        }
        let provider = Provider()
        let controller = makeController()
        let items = (0..<2).map { index -> TeroTab in
            let item = TeroTabItem(title: "t\(index)", image: nil, selectedImage: nil)
            item.accessibilityIdentifier = "tab.t\(index)"
            item.contentProvider = provider
            return TeroTab(identifier: "t\(index)", viewController: UIViewController(), item: item)
        }
        controller.setTabs(items, selectedIdentifier: "t0", animated: false)
        present(controller)

        overrideAccessibility(reduceMotion: true)
        provider.animatedFlags.removeAll()

        // 明確要求動畫，但減少動態效果應把它一路關掉
        controller.selectTab(withIdentifier: "t1", animated: true)

        XCTAssertFalse(provider.animatedFlags.isEmpty)
        XCTAssertTrue(
            provider.animatedFlags.allSatisfy { $0 == false },
            "Reduce Motion 開啟時必須把 animated=false 傳給 Provider，否則玻璃靜止而動畫還在跳"
        )
    }

    func test_reduceMotionOffStillPassesAnimatedThrough() {
        final class Provider: NSObject, TeroTabContentProvider {
            var animatedFlags: [Bool] = []
            func makeContentView() -> UIView { UIView() }
            func updateContentView(
                _ contentView: UIView,
                selected: Bool,
                presentationState: TeroTabBarPresentationState,
                animated: Bool
            ) { animatedFlags.append(animated) }
        }
        let provider = Provider()
        let controller = makeController()
        let items = (0..<2).map { index -> TeroTab in
            let item = TeroTabItem(title: "t\(index)", image: nil, selectedImage: nil)
            item.accessibilityIdentifier = "tab.t\(index)"
            item.contentProvider = provider
            return TeroTab(identifier: "t\(index)", viewController: UIViewController(), item: item)
        }
        controller.setTabs(items, selectedIdentifier: "t0", animated: false)
        present(controller)

        overrideAccessibility(reduceMotion: false)
        provider.animatedFlags.removeAll()

        controller.selectTab(withIdentifier: "t1", animated: true)

        XCTAssertTrue(provider.animatedFlags.contains(true))
    }
}
