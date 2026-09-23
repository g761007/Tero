import XCTest
@testable import Tero

/// 對應 ticket #31。
final class RuntimeConfigurationTests: TeroTabBarControllerTestCase {

    private func makePresentedController(
        _ mutate: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        mutate(configuration)
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<6).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    /// 標題實際畫出來的顏色。
    ///
    /// 比對的是解析後的分量而不是 `UIColor` 實例：tint 現在是沿著選取進度
    /// 插補出來的具體顏色，不會、也不應該是設定裡那個動態顏色物件本身。
    private func captionColor(of identifier: String, in controller: TeroTabBarController) -> UIColor? {
        guard let label = tabBarControl(for: identifier, in: controller)?
            .subviews
            .compactMap({ $0 as? UILabel })
            .first else { return nil }
        return label.textColor.resolvedColor(with: label.traitCollection)
    }

    private func resolved(_ color: UIColor, like identifier: String, in controller: TeroTabBarController) -> UIColor? {
        guard let control = tabBarControl(for: identifier, in: controller) else { return nil }
        return color.resolvedColor(with: control.traitCollection)
    }

    // MARK: 深拷貝

    func test_appliedConfigurationIsDeepCopied() {
        let controller = makePresentedController()
        let update = controller.currentConfiguration()
        update.compact.maximumVisibleItems = 3

        controller.applyConfiguration(update, animated: false)
        // 套用後再改原本那份物件
        update.compact.maximumVisibleItems = 6
        update.itemAppearance.selectedTintColor = .magenta

        let snapshot = controller.currentConfiguration()
        XCTAssertEqual(snapshot.compact.maximumVisibleItems, 3, "套用後的修改不該影響 controller")
        XCTAssertNotEqual(snapshot.itemAppearance.selectedTintColor, .magenta)
    }

    // MARK: 可見數量上限

    func test_changingMaximumVisibleItemsRecomputesThePartition() {
        let controller = makePresentedController { $0.compact.maximumVisibleItems = 6 }
        XCTAssertEqual(controller.visibleTabs.count, 6)
        XCTAssertTrue(controller.overflowTabs.isEmpty)

        let update = controller.currentConfiguration()
        update.compact.maximumVisibleItems = 3
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.visibleTabs.count, 2)
        XCTAssertEqual(controller.overflowTabs.count, 4)
        XCTAssertNotNil(tabBarControl(for: "more", in: controller))
    }

    func test_changingMaximumVisibleItemsKeepsSelection() {
        let controller = makePresentedController { $0.compact.maximumVisibleItems = 6 }
        controller.selectTab(withIdentifier: "t5", animated: false)
        recorder.didSelectCalls = []

        let update = controller.currentConfiguration()
        update.compact.maximumVisibleItems = 3
        controller.applyConfiguration(update, animated: false)

        XCTAssertEqual(controller.selectedTab?.identifier, "t5")
        XCTAssertTrue(recorder.didSelectCalls.isEmpty, "只是顯示位置變了")
        XCTAssertTrue(controller.overflowTabs.contains { $0.identifier == "t5" })
    }

    // MARK: 外觀

    func test_changingTintColoursTakesEffect() {
        let controller = makePresentedController()
        let pink = resolved(.systemPink, like: "t0", in: controller)
        XCTAssertNotEqual(captionColor(of: "t0", in: controller), pink)  // 預設 tint 不是粉紅

        let update = controller.currentConfiguration()
        update.itemAppearance.selectedTintColor = .systemPink
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        assertSameColor(captionColor(of: "t0", in: controller), pink, "t0 是選取中的 Tab")
    }

    func test_changingClassicBarHeightTakesEffect() {
        let controller = makePresentedController()
        let before = controller.tabBar.frame.height

        let update = controller.currentConfiguration()
        update.classicAppearance.barHeight = 80
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.tabBar.frame.height, before - 49 + 80, accuracy: 1.0)
    }

    func test_changingClassicBarHeightUpdatesChildSafeArea() {
        let controller = makePresentedController()

        let update = controller.currentConfiguration()
        update.classicAppearance.barHeight = 80
        controller.applyConfiguration(update, animated: false)

        for child in controller.children {
            XCTAssertEqual(child.additionalSafeAreaInsets.bottom, 80, accuracy: 0.5)
        }
    }

    // MARK: Glass tint

    func test_changingGlassTintTakesEffect() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makePresentedController {
            $0.style = .floatingGlass
            $0.compact.maximumVisibleItems = 6
        }

        let update = controller.currentConfiguration()
        update.floatingGlassAppearance.glassTintMode = .tinted
        update.floatingGlassAppearance.glassTintColor = .systemTeal
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        guard let control = tabBarControl(for: "t0", in: controller),
              let capsule = capsule(containing: control, in: controller),
              let glass = capsule.effect as? UIGlassEffect else {
            return XCTFail("應為玻璃")
        }
        XCTAssertEqual(glass.tintColor, .systemTeal)
    }

    // MARK: 捲動行為

    func test_changingScrollBehaviourTakesEffect() {
        final class Scrolling: UIViewController, TeroScrollProviding {
            final class DraggingScrollView: UIScrollView {
                override var isDragging: Bool { true }
            }
            let scrollView = DraggingScrollView()
            var teroTrackingScrollView: UIScrollView? { scrollView }
            override func viewDidLoad() {
                super.viewDidLoad()
                scrollView.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
                scrollView.contentSize = CGSize(width: 390, height: 5000)
                view.addSubview(scrollView)
            }
        }
        let scrolling = Scrolling()
        let item = TeroTabItem(title: "feed", image: nil, selectedImage: nil)
        item.accessibilityIdentifier = "tab.feed"
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.scrollConfiguration.velocityThreshold = 10_000
        let controller = makeController(configuration: configuration)
        controller.setTabs(
            [TeroTab(identifier: "feed", viewController: scrolling, item: item)],
            selectedIdentifier: nil,
            animated: false
        )
        present(controller)
        scrolling.loadViewIfNeeded()
        controller.refreshScrollTracking()

        func scroll(to offset: CGFloat) {
            scrolling.scrollView.contentOffset = CGPoint(
                x: 0,
                y: -scrolling.scrollView.adjustedContentInset.top + offset
            )
        }

        scroll(to: 300)
        XCTAssertEqual(controller.tabBarPresentationState, .expanded, "預設 .none 不該收合")

        let update = controller.currentConfiguration()
        update.scrollConfiguration.behavior = .hideOnScrollDown
        controller.applyConfiguration(update, animated: false)

        scroll(to: 0)
        scroll(to: 300)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "套用新行為後應生效")
    }

    // MARK: More 呈現方式

    func test_changingMorePresentationStyleTakesEffect() {
        let controller = makePresentedController { $0.compact.maximumVisibleItems = 3 }
        XCTAssertNotNil(
            (tabBarControl(for: "more", in: controller) as? UIButton)?.menu,
            "`.automatic` 預設為選單"
        )

        let update = controller.currentConfiguration()
        update.morePresentationStyle = .sheet
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNil(
            (tabBarControl(for: "more", in: controller) as? UIButton)?.menu,
            "sheet 樣式不掛選單"
        )
    }

    // MARK: Style 不可 runtime 變更

    func test_changingStyleIsIgnoredAndReported() {
        let controller = makePresentedController()
        XCTAssertEqual(controller.requestedStyle, .classic)

        let update = controller.currentConfiguration()
        update.style = .floatingGlass
        controller.applyConfiguration(update, animated: false)

        XCTAssertEqual(controller.requestedStyle, .classic, "style 欄位應被忽略")
        XCTAssertEqual(controller.tabBar.style, .classic)
        XCTAssertEqual(reportedDiagnostics.count, 1)
        XCTAssertTrue(reportedDiagnostics[0].contains("style"))
    }

    func test_applyingSameStyleReportsNothing() {
        let controller = makePresentedController()

        controller.applyConfiguration(controller.currentConfiguration(), animated: false)

        XCTAssertTrue(reportedDiagnostics.isEmpty)
    }

    // MARK: 其他不變式

    func test_applyingConfigurationKeepsActionItem() {
        let controller = makePresentedController()
        let action = TeroTabActionItem(identifier: "compose", image: UIImage(systemName: "plus"))
        action.accessibilityIdentifier = "tab.compose"
        controller.setActionItem(action, animated: false)

        controller.applyConfiguration(controller.currentConfiguration(), animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.actionItem?.identifier, "compose")
        XCTAssertNotNil(tabBarControl(for: "compose", in: controller))
    }

    func test_applyingConfigurationKeepsBadges() {
        let controller = makePresentedController()
        controller.setBadge(.value("7"), forTabWithIdentifier: "t1", animated: false)

        controller.applyConfiguration(controller.currentConfiguration(), animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(tabBarControl(for: "t1", in: controller)?.accessibilityValue, "7")
    }

    func test_applyingBeforeViewLoadsStillStoresTheConfiguration() {
        let controller = makeController()
        let update = TeroTabBarConfiguration.defaultConfiguration()
        update.compact.maximumVisibleItems = 4

        controller.applyConfiguration(update, animated: false)

        XCTAssertEqual(controller.currentConfiguration().compact.maximumVisibleItems, 4)
        XCTAssertFalse(controller.isViewLoaded)
    }
}
