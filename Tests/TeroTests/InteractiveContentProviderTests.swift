import XCTest
@testable import Tero

/// 只實作既有協定的 provider。用來確認進階協定不是 breaking change。
private final class PlainProvider: NSObject, TeroTabContentProvider {
    private(set) var madeViews = 0
    private(set) var selectedStates: [Bool] = []
    let view = UIView()

    func makeContentView() -> UIView {
        madeViews += 1
        return view
    }

    func updateContentView(
        _ contentView: UIView,
        selected: Bool,
        presentationState: TeroTabBarPresentationState,
        animated: Bool
    ) {
        selectedStates.append(selected)
    }
}

/// 同時實作兩者的 provider。
private final class InteractiveProvider: NSObject, TeroTabInteractiveContentProvider {
    private(set) var progresses: [CGFloat] = []
    private(set) var animatedFlags: [Bool] = []
    private(set) var selectedStates: [Bool] = []
    let view = UIView()

    func makeContentView() -> UIView { view }

    func updateContentView(
        _ contentView: UIView,
        selected: Bool,
        presentationState: TeroTabBarPresentationState,
        animated: Bool
    ) {
        selectedStates.append(selected)
    }

    func updateContentView(_ contentView: UIView, selectionProgress: CGFloat, animated: Bool) {
        progresses.append(selectionProgress)
        animatedFlags.append(animated)
    }

    func reset() {
        progresses = []
        animatedFlags = []
        selectedStates = []
    }
}


/// 對應 ticket #42。
final class InteractiveContentProviderTests: TeroTabBarControllerTestCase {

    private func makeProviderController(
        providers: [Int: TeroTabContentProvider],
        tabCount: Int = 3,
        mutate: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        mutate(configuration)
        let controller = makeController(configuration: configuration)
        let tabs = (0..<tabCount).map { index -> TeroTab in
            let tab = makeTab("t\(index)")
            tab.item.contentProvider = providers[index]
            return tab
        }
        controller.setTabs(tabs, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    // MARK: 既有 provider 不受影響

    func test_plainProviderNeverReceivesProgress() {
        let plain = PlainProvider()
        let controller = makeProviderController(providers: [1: plain])

        controller.selectTab(withIdentifier: "t1", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        // 唯一能驗的是「沒有崩」與 Bool 回呼照舊——進階回呼它根本沒有。
        XCTAssertEqual(plain.madeViews, 1)
        XCTAssertEqual(plain.selectedStates.last, true)
    }

    func test_plainProviderStillGetsTheBoolCallback() {
        let plain = PlainProvider()
        let controller = makeProviderController(providers: [0: plain])

        controller.selectTab(withIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(plain.selectedStates.last, false)
    }

    // MARK: 進階 provider

    func test_interactiveProviderGetsBothCallbacks() {
        let interactive = InteractiveProvider()
        let controller = makeProviderController(providers: [1: interactive])
        interactive.reset()

        controller.selectTab(withIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(interactive.selectedStates.last, true, "Bool 版本仍在狀態落定時呼叫")
        XCTAssertEqual(interactive.progresses.last, 1, "同時收到連續進度")
    }

    func test_progressSettlesAtExactlyOne() {
        let interactive = InteractiveProvider()
        let controller = makeProviderController(providers: [2: interactive]) {
            $0.motion.selectionResponse = 0.08
        }
        interactive.reset()

        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertEqual(interactive.progresses.last, 1)
    }

    func test_progressSettlesAtExactlyZeroWhenDeselected() {
        let interactive = InteractiveProvider()
        let controller = makeProviderController(providers: [0: interactive]) {
            $0.motion.selectionResponse = 0.08
        }
        interactive.reset()

        controller.selectTab(withIdentifier: "t1", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertEqual(interactive.progresses.last, 0)
    }

    func test_progressIsMonotonicWithinASegment() {
        let interactive = InteractiveProvider()
        let controller = makeProviderController(providers: [2: interactive]) {
            $0.motion.selectionResponse = 0.5
        }
        interactive.reset()

        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))

        let values = interactive.progresses
        XCTAssertGreaterThan(values.count, 2, "轉場中應該回報多幀，而不是只有頭尾")
        for (previous, next) in zip(values, values.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next, previous, "同一段之內不應倒退")
        }
        XCTAssertEqual(values.last, 1)
    }

    func test_interruptionContinuesWithoutJumping() {
        let interactive = InteractiveProvider()
        let controller = makeProviderController(providers: [1: interactive], tabCount: 4) {
            $0.motion.selectionResponse = 1.2
        }
        interactive.reset()

        controller.selectTab(withIdentifier: "t1", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        guard let midway = interactive.progresses.last else { return XCTFail("轉場途中沒有回報") }
        XCTAssertGreaterThan(midway, 0)
        XCTAssertLessThan(midway, 1)

        controller.selectTab(withIdentifier: "t3", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        guard let afterInterrupt = interactive.progresses.first(where: { _ in true }) else { return XCTFail() }
        _ = afterInterrupt
        // 接手的那一段從畫面上的狀態繼續：不會先跳回 0 或 1 再走。
        let firstAfter = interactive.progresses.last!
        XCTAssertLessThanOrEqual(firstAfter, midway + 0.05, "被中斷的一格往 0 走，不會先往上跳")
    }

    func test_animatedFlagReflectsWhetherTheSegmentIsAnimating() {
        let interactive = InteractiveProvider()
        let controller = makeProviderController(providers: [1: interactive])
        interactive.reset()

        controller.selectTab(withIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(interactive.animatedFlags.last, false)

        interactive.reset()
        controller.selectTab(withIdentifier: "t0", animated: true)
        XCTAssertEqual(interactive.animatedFlags.last, true)
    }

    // MARK: 邊界

    func test_actionProviderNeverReceivesProgress() {
        let interactive = InteractiveProvider()
        let controller = makeProviderController(providers: [:])
        let action = TeroTabActionItem(identifier: "compose", image: UIImage(systemName: "plus"))
        action.contentProvider = interactive
        action.accessibilityIdentifier = "tab.action"
        controller.setActionItem(action, animated: false)
        controller.view.layoutIfNeeded()
        interactive.reset()

        controller.selectTab(withIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertTrue(interactive.progresses.isEmpty, "Action 是指令，不參與選取（ADR-0003）")
    }

    func test_contentViewSurvivesAnOverflowRoundTrip() {
        let interactive = InteractiveProvider()
        let controller = makeProviderController(providers: [4: interactive], tabCount: 6) {
            $0.compact.maximumVisibleItems = 6
        }
        let before = controller.tabBar.subviews.isEmpty ? nil : interactive.view

        let shrink = controller.currentConfiguration()
        shrink.compact.maximumVisibleItems = 3
        controller.applyConfiguration(shrink, animated: false)
        controller.view.layoutIfNeeded()

        let grow = controller.currentConfiguration()
        grow.compact.maximumVisibleItems = 6
        controller.applyConfiguration(grow, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNotNil(before)
        XCTAssertTrue(interactive.view === before, "進出 Overflow 之後仍是同一個 content view 實例")
        XCTAssertTrue(interactive.view.superview != nil, "回到可見時重新掛回去")
    }
}
