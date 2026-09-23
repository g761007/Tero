import XCTest
@testable import Tero

private final class PresentationProgressProvider: NSObject, TeroTabInteractiveContentProvider {
    let view = UIView()
    var samples: [(CGFloat, Bool)] = []
    var onProgress: (() -> Void)?
    func makeContentView() -> UIView { view }
    func updateContentView(_ contentView: UIView, presentationProgress: CGFloat, animated: Bool) {
        samples.append((presentationProgress, animated))
        onProgress?()
    }
}

final class VisibilityTransitionTests: TeroTabBarControllerTestCase {
    private func setup(provider: PresentationProgressProvider? = nil) -> TeroTabBarController {
        let config = TeroTabBarConfiguration()
        config.style = .floatingGlass
        config.motion.minimizeDuration = 0.25
        config.motion.restoreDuration = 0.15
        let controller = makeController(configuration: config)
        let tabs = (0..<4).map { makeTab("t\($0)") }
        tabs[0].item.contentProvider = provider
        controller.setTabs(tabs, selectedIdentifier: "t0", animated: false)
        present(controller)
        return controller
    }
    private func advance(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    func test_intermediateGeometryAndProviderProgressThenReverseWithoutJump() throws {
        guard #available(iOS 26, *) else { throw XCTSkip() }
        let provider = PresentationProgressProvider()
        let controller = setup(provider: provider)
        let height = controller.tabBar.bounds.height
        controller.setTabBarPresentationState(.minimized, animated: true)
        advance(0.10)
        let intermediate = controller.tabBar.bounds.height
        XCTAssertLessThan(intermediate, height)
        XCTAssertGreaterThan(intermediate, controller.currentConfiguration().floatingGlassAppearance.minimizedHeight)
        XCTAssertTrue(provider.samples.contains { $0.0 > 0 && $0.0 < 1 })
        controller.setTabBarPresentationState(.expanded, animated: true)
        XCTAssertEqual(controller.tabBar.bounds.height, intermediate, accuracy: 1)
        // restoreDuration 預設 0.22，原本等 0.25 秒只留 30ms 餘裕，而那段 runloop
        // 還要處理 layout 與 provider 回呼。改成等狀態真的落定——幾何與 provider 進度
        // 不是同時到的：高度先收斂，provider 還會再收到最後一筆 0。
        waitUntil("恢復動畫落定") {
            abs(controller.tabBar.bounds.height - height) < 0.1 && provider.samples.last?.0 == 0
        }
        XCTAssertEqual(controller.tabBar.bounds.height, height, accuracy: 0.1)
        XCTAssertEqual(provider.samples.last?.0, 0)
    }

    func test_minimizeAndSelectionResizeFinishOnSameItem() throws {
        guard #available(iOS 26, *) else { throw XCTSkip() }
        let controller = setup()
        controller.selectTab(withIdentifier: "t2", animated: true)
        controller.setTabBarPresentationState(.minimized, animated: true)
        advance(0.08)
        window.frame.size.width = 320
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        advance(0.7)
        let item = try XCTUnwrap(tabBarControl(for: "t2", in: controller))
        let selection = try XCTUnwrap(item.superview?.subviews.compactMap { $0 as? TeroTabSelectionIndicatorView }.first)
        XCTAssertEqual(selection.frame.midX, item.frame.midX, accuracy: 1)
        XCTAssertEqual(controller.tabBar.bounds.height, controller.currentConfiguration().floatingGlassAppearance.minimizedHeight, accuracy: 1)
        XCTAssertEqual(controller.tabBar.transform, .identity)
    }

    func test_compactHitTargetExtendsVerticallyAndHiddenNeverHits() throws {
        guard #available(iOS 26, *) else { throw XCTSkip() }
        let controller = setup()
        controller.setTabBarPresentationState(.minimized, animated: false)
        let item = try XCTUnwrap(tabBarControl(for: "t0", in: controller))
        let rect = item.convert(item.bounds, to: controller.tabBar)
        let point = CGPoint(x: rect.midX, y: rect.midY - 21)
        XCTAssertIdentical(controller.tabBar.hitTest(point, with: nil), item)
        XCTAssertTrue(item.point(inside: controller.tabBar.convert(point, to: item), with: nil))
        controller.setTabBarPresentationState(.hidden, animated: false)
        XCTAssertNil(controller.tabBar.hitTest(point, with: nil))
    }

    func test_reduceMotionSettlesVisibilityAndStopsProviderAnimation() throws {
        guard #available(iOS 26, *) else { throw XCTSkip() }
        let provider = PresentationProgressProvider()
        let controller = setup(provider: provider)
        controller.setTabBarPresentationState(.minimized, animated: true)
        advance(0.06)
        overrideAccessibility(reduceMotion: true)
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        XCTAssertEqual(controller.tabBar.minimizationProgress, 1)
        XCTAssertEqual(provider.samples.last?.1, false)
    }

    func test_providerCanReplaceTabsDuringProgressWithoutOldWrites() throws {
        guard #available(iOS 26, *) else { throw XCTSkip() }
        let provider = PresentationProgressProvider()
        let controller = setup(provider: provider)
        provider.onProgress = { [weak controller, weak provider] in
            guard let controller else { return }
            provider?.onProgress = nil
            controller.setTabs([self.makeTab("replacement")], selectedIdentifier: nil, animated: false)
        }
        controller.setTabBarPresentationState(.minimized, animated: true)
        advance(0.4)
        XCTAssertEqual(controller.selectedTab?.identifier, "replacement")
        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_hiddenAndRestoreHaveContinuousIndependentVisibility() {
        let controller = setup()
        let y = controller.tabBar.frame.minY
        controller.setTabBarPresentationState(.hidden, animated: true)
        XCTAssertEqual(controller.tabBar.frame.minY, y, accuracy: 1)
        advance(0.06)
        XCTAssertGreaterThan(controller.tabBar.frame.minY, y)
        controller.setTabBarPresentationState(.expanded, animated: true)
        advance(0.3)
        XCTAssertEqual(controller.tabBar.frame.minY, y, accuracy: 1)
    }

    func test_reduceMotionDuringHideImmediatelySettlesVisibility() {
        let controller = setup()
        controller.setTabBarPresentationState(.hidden, animated: true)
        advance(0.04)
        overrideAccessibility(reduceMotion: true)
        NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        XCTAssertGreaterThanOrEqual(controller.tabBar.frame.minY, controller.view.bounds.maxY)
    }

    func test_addingTallActionUpdatesGeometryAndReservedInset() throws {
        guard #available(iOS 26, *) else { throw XCTSkip() }
        let controller = setup()
        let config = controller.currentConfiguration()
        config.floatingGlassAppearance.actionSize = CGSize(width: 56, height: 80)
        controller.applyConfiguration(config, animated: false)
        controller.setActionItem(TeroTabActionItem(identifier: "compose", image: nil), animated: false)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.tabBar.bounds.height, 80, accuracy: 1)
        // Bar 落在 home indicator 帶子裡的那一段已經在視窗的 safe area 裡，要扣掉。
        let reserved = 80 + config.floatingGlassAppearance.bottomInset
        XCTAssertEqual(controller.children[0].additionalSafeAreaInsets.bottom,
                       max(0, reserved - controller.view.safeAreaInsets.bottom), accuracy: 1)
    }

    func test_sameHiddenRequestStillRemovesScrollReservedInset() {
        let controller = setup()
        controller.applyScrollDrivenPresentationState(.hidden, animated: false)
        XCTAssertGreaterThan(controller.children[0].additionalSafeAreaInsets.bottom, 0)
        controller.setTabBarPresentationState(.hidden, animated: false)
        XCTAssertEqual(controller.children[0].additionalSafeAreaInsets.bottom, 0)
    }
}
