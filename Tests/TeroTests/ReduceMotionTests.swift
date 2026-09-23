import XCTest
@testable import Tero

/// 記錄 `animated` 旗標的自訂內容。
private final class AnimatedFlagProvider: NSObject, TeroTabInteractiveContentProvider {
    private(set) var boolFlags: [Bool] = []
    private(set) var progressFlags: [Bool] = []
    let view = UIView()

    func makeContentView() -> UIView { view }

    func updateContentView(
        _ contentView: UIView,
        selected: Bool,
        presentationState: TeroTabBarPresentationState,
        animated: Bool
    ) {
        boolFlags.append(animated)
    }

    func updateContentView(_ contentView: UIView, selectionProgress: CGFloat, animated: Bool) {
        progressFlags.append(animated)
    }

    func reset() {
        boolFlags = []
        progressFlags = []
    }
}


/// 對應 ticket #45。以注入點模擬設定，不依賴真的開啟系統設定。
final class ReduceMotionTests: TeroTabBarControllerTestCase {

    private func makeReduceMotionController(
        behavior: TeroTabReduceMotionBehavior = .crossFade,
        provider: TeroTabContentProvider? = nil
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.itemAppearance.selectionIndicatorStyle = .always
        configuration.motion.reduceMotionBehavior = behavior
        configuration.motion.selectionResponse = 0.8
        let controller = makeController(configuration: configuration)
        let tabs = (0..<4).map { index -> TeroTab in
            let tab = makeTab("t\(index)")
            if index == 2 { tab.item.contentProvider = provider }
            return tab
        }
        controller.setTabs(tabs, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func indicator(in controller: TeroTabBarController) -> TeroTabSelectionIndicatorView? {
        func search(_ view: UIView) -> TeroTabSelectionIndicatorView? {
            if let found = view as? TeroTabSelectionIndicatorView { return found }
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

    // MARK: 不做彈簧位移

    func test_indicatorDoesNotSlideWhenReduceMotionIsOn() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let controller = makeReduceMotionController()

        controller.selectTab(withIdentifier: "t3", animated: true)

        // 就地就位：沒有中途狀態可言。
        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t3", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, item.frame.midX, accuracy: 1.0)
    }

    func test_selectionStateSurvivesReduceMotion() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let controller = makeReduceMotionController()

        controller.selectTab(withIdentifier: "t2", animated: true)
        controller.view.layoutIfNeeded()

        guard let view = indicator(in: controller) else { return XCTFail() }
        XCTAssertFalse(view.isHidden, "選取狀態仍然看得出來")
        XCTAssertEqual(view.alpha, 1)
    }

    func test_reduceMotionDropsTheLensButKeepsTheSelection() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let controller = makeReduceMotionController()

        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        // 透鏡是動態效果的一部分，減少動態時不該出現；
        // 但選取本身仍然要看得見——降級的是動態，不是狀態。
        let lens = controller.tabBar.subviews.compactMap { $0 as? TeroTabSelectionIndicatorView }.first
        XCTAssertTrue(lens?.isHidden ?? true, "減少動態時不出現透鏡")
        guard let view = indicator(in: controller) else { return XCTFail() }
        XCTAssertFalse(view.isHidden, "選取狀態仍然看得出來")
        XCTAssertEqual(view.alpha, 1)
    }

    func test_progressJumpsStraightToTheEnds() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let controller = makeReduceMotionController()

        controller.selectTab(withIdentifier: "t2", animated: true)

        let leaving = tabBarControl(for: "t0", in: controller) as? TeroTabItemView
        let arriving = tabBarControl(for: "t2", in: controller) as? TeroTabItemView
        XCTAssertEqual(leaving?.selectionProgress, 0)
        XCTAssertEqual(arriving?.selectionProgress, 1)
    }

    // MARK: 兩種降級方式

    func test_crossFadeRunsATransitionOnTheItemsContainer() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let controller = makeReduceMotionController(behavior: .crossFade)
        guard let container = indicator(in: controller)?.superview else { return XCTFail() }

        controller.selectTab(withIdentifier: "t3", animated: true)

        XCTAssertFalse(
            container.layer.animationKeys()?.isEmpty ?? true,
            "交叉淡入作用在整個 items 容器上，外框與 Icon 一起交棒"
        )
    }

    func test_instantRunsNoTransitionAtAll() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let controller = makeReduceMotionController(behavior: .instant)
        guard let container = indicator(in: controller)?.superview else { return XCTFail() }

        controller.selectTab(withIdentifier: "t3", animated: true)

        XCTAssertTrue(container.layer.animationKeys()?.isEmpty ?? true, "直接換狀態，沒有轉場")
    }

    func test_bothBehavioursLandOnTheSamePlace() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)

        var frames: [CGRect] = []
        for behavior in [TeroTabReduceMotionBehavior.crossFade, .instant] {
            let controller = makeReduceMotionController(behavior: behavior)
            controller.selectTab(withIdentifier: "t3", animated: true)
            controller.view.layoutIfNeeded()
            guard let frame = indicator(in: controller)?.frame else { return XCTFail() }
            frames.append(frame)
        }
        XCTAssertEqual(frames[0], frames[1])
    }

    // MARK: Provider 的 animated 旗標

    func test_providerIsToldNotToAnimate() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let provider = AnimatedFlagProvider()
        let controller = makeReduceMotionController(provider: provider)
        provider.reset()

        controller.selectTab(withIdentifier: "t2", animated: true)

        XCTAssertEqual(provider.progressFlags.last, false, "減少動態效果時應停止播放")
        XCTAssertEqual(provider.boolFlags.last, false)
    }

    func test_providerIsToldToAnimateWhenMotionIsAllowed() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: false)
        let provider = AnimatedFlagProvider()
        let controller = makeReduceMotionController(provider: provider)
        provider.reset()

        controller.selectTab(withIdentifier: "t2", animated: true)

        XCTAssertEqual(provider.progressFlags.last, true)
    }

    // MARK: Runtime 變更

    func test_turningReduceMotionOnMidTransitionSettlesImmediately() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: false)
        let controller = makeReduceMotionController()

        controller.selectTab(withIdentifier: "t3", animated: true)
        overrideAccessibility(reduceMotion: true)
        NotificationCenter.default.post(
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        RunLoop.current.run(until: Date())

        let arriving = tabBarControl(for: "t3", in: controller) as? TeroTabItemView
        XCTAssertEqual(arriving?.selectionProgress, 1, "剛打開設定就立刻落定，不必等下一次切換")
        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t3", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, item.frame.midX, accuracy: 1.0)
    }

    func test_turningReduceMotionOffRestoresTheSpring() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let controller = makeReduceMotionController()
        controller.selectTab(withIdentifier: "t1", animated: true)

        overrideAccessibility(reduceMotion: false)
        controller.selectTab(withIdentifier: "t3", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        let arriving = tabBarControl(for: "t3", in: controller) as? TeroTabItemView
        guard let progress = arriving?.selectionProgress else { return XCTFail() }
        XCTAssertGreaterThan(progress, 0)
        XCTAssertLessThan(progress, 1, "又回到有中間狀態的轉場")
    }
}
