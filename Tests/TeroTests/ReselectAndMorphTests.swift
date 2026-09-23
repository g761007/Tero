import XCTest
@testable import Tero

/// 會記錄重播通知的自訂內容。
private final class ReplayRecordingProvider: NSObject, TeroTabContentProvider {
    private(set) var updates: [Bool] = []
    let view = UIView()

    func makeContentView() -> UIView { view }

    func updateContentView(
        _ contentView: UIView,
        selected: Bool,
        presentationState: TeroTabBarPresentationState,
        animated: Bool
    ) {
        updates.append(selected)
    }

    func reset() { updates = [] }
}


/// 對應 ticket #44：重複點擊回饋、最小化 morph、尺寸改變。
final class ReselectAndMorphTests: TeroTabBarControllerTestCase {

    private func makeMorphController(
        tabCount: Int = 4,
        provider: TeroTabContentProvider? = nil,
        mutate: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.compact.maximumVisibleItems = 6
        configuration.itemAppearance.selectionIndicatorStyle = .always
        mutate(configuration)
        let controller = makeController(configuration: configuration)
        let tabs = (0..<tabCount).map { index -> TeroTab in
            let tab = makeTab("t\(index)")
            if index == 0 { tab.item.contentProvider = provider }
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

    // MARK: 重複點擊

    func test_reselectDoesNotChangeTheSelection() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController()
        let before = indicator(in: controller)?.center

        tapTabBarItem("t0", in: controller)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.selectedTab?.identifier, "t0")
        XCTAssertEqual(controller.selectedIndex, 0)
        XCTAssertEqual(indicator(in: controller)?.center, before, "選取沒變，外框就不該移動")
    }

    func test_reselectStillReportsTheDelegateEvent() {
        let controller = makeMorphController()
        recorder.didReselectCalls = []

        tapTabBarItem("t0", in: controller)

        XCTAssertEqual(recorder.didReselectCalls, ["t0"])
        XCTAssertTrue(recorder.didSelectCalls.filter { $0.identifier == "t0" && $0.source == .user }.isEmpty)
    }

    func test_programmaticReselectGivesNoFeedbackAndNoEvent() {
        let controller = makeMorphController()
        recorder.didReselectCalls = []

        controller.selectTab(withIdentifier: "t0", animated: true)

        XCTAssertTrue(recorder.didReselectCalls.isEmpty, "程式呼叫不觸發重複點擊語意")
    }

    func test_reselectPulsesTheIndicator() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController {
            $0.motion.reselectDuration = 0.8
        }

        tapTabBarItem("t0", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        guard let scale = indicator(in: controller)?.layer.presentation()?.transform else {
            throw XCTSkip("模擬器沒有提供 presentation layer")
        }
        XCTAssertGreaterThan(scale.m11, 1.0, "膠囊在回饋中脹了一下")
    }

    func test_pulseSettlesBackToIdentity() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController {
            $0.motion.reselectDuration = 0.2
        }

        tapTabBarItem("t0", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        XCTAssertEqual(indicator(in: controller)?.transform, .identity)
    }

    func test_reselectLetsCustomContentReplay() {
        let provider = ReplayRecordingProvider()
        let controller = makeMorphController(provider: provider)
        provider.reset()

        tapTabBarItem("t0", in: controller)

        XCTAssertEqual(provider.updates, [true], "自訂內容收到一次重播機會")
    }

    func test_reduceMotionSkipsTheFeedbackButKeepsTheEvent() throws {
        try XCTSkipUnless(isFloatingAvailable)
        overrideAccessibility(reduceMotion: true)
        let controller = makeMorphController()
        recorder.didReselectCalls = []

        tapTabBarItem("t0", in: controller)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(indicator(in: controller)?.transform, .identity)
        XCTAssertEqual(recorder.didReselectCalls, ["t0"])
    }

    // MARK: 最小化 morph

    func test_indicatorStaysVisibleAcrossMinimize() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController()

        controller.setTabBarPresentationState(.minimized, animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(indicator(in: controller)?.isHidden, false, "不能消失再出現")
        XCTAssertEqual(indicator(in: controller)?.alpha, 1)
    }

    func test_minimizeShrinksTheIndicatorAndItsCorner() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController()
        guard let expanded = indicator(in: controller) else { return XCTFail() }
        let expandedHeight = expanded.frame.height
        let expandedRadius = expanded.layer.cornerRadius

        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertLessThan(expanded.frame.height, expandedHeight)
        XCTAssertLessThan(expanded.layer.cornerRadius, expandedRadius, "圓角跟著高度一起變")
        XCTAssertEqual(expanded.transform, .identity, "重新排版，不是縮放變形")
    }

    func test_expandingRestoresTheIndicator() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController()
        guard let view = indicator(in: controller) else { return XCTFail() }
        let expanded = view.frame

        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()
        controller.setTabBarPresentationState(.expanded, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(view.frame, expanded)
    }

    func test_expandedAndMinimizedShareTheSameItemViews() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController()
        let before = (0..<4).map { tabBarControl(for: "t\($0)", in: controller) }

        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        let after = (0..<4).map { tabBarControl(for: "t\($0)", in: controller) }
        for (lhs, rhs) in zip(before, after) {
            XCTAssertTrue(lhs === rhs, "同一組 Item 實例重新排版，不是兩套視圖互換（補充規格 §22）")
        }
    }

    func test_indicatorTracksSelectionWhileMinimized() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController()
        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        controller.selectTab(withIdentifier: "t2", animated: false)
        controller.view.layoutIfNeeded()

        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t2", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, item.frame.midX, accuracy: 1.0)
    }

    // MARK: 尺寸改變

    func test_rotationKeepsTheIndicatorOnTheSelectedItem() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController()
        controller.selectTab(withIdentifier: "t2", animated: false)
        controller.view.layoutIfNeeded()

        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t2", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, item.frame.midX, accuracy: 1.0)
    }

    func test_resizeDuringATransitionLandsOnTheNewGeometry() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController {
            $0.motion.selectionResponse = 0.6
        }

        controller.selectTab(withIdentifier: "t3", animated: true)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 844)
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t3", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, item.frame.midX, accuracy: 1.0, "不能飛到舊版面算出來的位置")
    }

    // MARK: 動態增減 Tab

    func test_addingATabKeepsTheIndicatorOnTheSelectedTab() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController(tabCount: 4)
        controller.selectTab(withIdentifier: "t2", animated: false)

        var tabs = controller.tabs
        tabs.append(makeTab("extra"))
        controller.setTabs(tabs, selectedIdentifier: "t2", animated: false)
        controller.view.layoutIfNeeded()

        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t2", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, item.frame.midX, accuracy: 1.0)
    }

    func test_selectedTabFallingIntoMoreMovesTheIndicatorToMore() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController(tabCount: 6)
        controller.selectTab(withIdentifier: "t5", animated: false)
        controller.view.layoutIfNeeded()

        let update = controller.currentConfiguration()
        update.compact.maximumVisibleItems = 3
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.selectedTab?.identifier, "t5")
        guard let frame = indicator(in: controller)?.frame,
              let more = tabBarControl(for: "more", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, more.frame.midX, accuracy: 1.0, "選取落進 More 時外框跟過去")
    }

    func test_removingTheSelectedTabRelocatesTheIndicator() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMorphController(tabCount: 4)
        controller.selectTab(withIdentifier: "t3", animated: false)
        controller.view.layoutIfNeeded()

        controller.setTabs(Array(controller.tabs.prefix(3)), selectedIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        guard let frame = indicator(in: controller)?.frame,
              let item = tabBarControl(for: "t1", in: controller) else { return XCTFail() }
        XCTAssertEqual(frame.midX, item.frame.midX, accuracy: 1.0)
    }
}
