import XCTest
@testable import Tero

/// 對應 ticket #30。透過真實的 `UIScrollView` 驅動——`contentOffset` 的 KVO 是同步的，
/// 因此不需要等動畫或計時，測試是確定的。
final class ScrollDrivenStateTests: TeroTabBarControllerTestCase {

    /// 提供捲動視圖的畫面。刻意也設定自己的 delegate，用來驗證套件不會搶走它。
    ///
    /// **不實作** `preferredTeroTabBarScrollBehavior`：在 `@objc optional` 的語意下，
    /// 實作了就等於表達偏好（`.none` 也是一種偏好），會覆蓋設定中的行為。
    class ScrollingViewController: UIViewController, TeroScrollProviding, UIScrollViewDelegate {
        final class TestScrollView: UIScrollView {
            var simulatesDragging = false
            override var isDragging: Bool { simulatesDragging || super.isDragging }
        }
        let scrollView = TestScrollView()
        private(set) var ownDelegateCallbacks = 0

        var teroTrackingScrollView: UIScrollView? { scrollView }

        override func viewDidLoad() {
            super.viewDidLoad()
            scrollView.delegate = self
            scrollView.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
            scrollView.contentSize = CGSize(width: 390, height: 5000)
            view.addSubview(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            ownDelegateCallbacks += 1
        }
    }

    /// 明確表達偏好的畫面。
    final class PreferringScrollingViewController: ScrollingViewController,
                                                    TeroTabBarScrollBehaviorProviding {
        var behavior: TeroTabBarScrollBehavior = .none
        // 父類別沒有宣告這個成員（它來自 protocol 的 optional），因此不是 override。
        @objc var preferredTeroTabBarScrollBehavior: TeroTabBarScrollBehavior { behavior }
    }

    final class PlainViewController: UIViewController {}

    private func makeFloatingConfiguration(
        behavior: TeroTabBarScrollBehavior
    ) -> TeroTabBarConfiguration {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.scrollConfiguration.behavior = behavior
        configuration.scrollConfiguration.downwardTranslationThreshold = 40
        configuration.scrollConfiguration.upwardTranslationThreshold = 24
        configuration.scrollConfiguration.velocityThreshold = 10_000  // 測試無真實手勢，關掉速度路徑
        return configuration
    }

    private func makeSetup(
        behavior: TeroTabBarScrollBehavior = .minimizeOnScrollDown,
        wrapInNavigation: Bool = false
    ) -> (TeroTabBarController, ScrollingViewController) {
        let scrolling = ScrollingViewController()
        let hosted: UIViewController = wrapInNavigation
            ? UINavigationController(rootViewController: scrolling)
            : scrolling
        let item = TeroTabItem(title: "feed", image: nil, selectedImage: nil)
        item.accessibilityIdentifier = "tab.feed"

        let controller = makeController(configuration: makeFloatingConfiguration(behavior: behavior))
        controller.setTabs(
            [
                TeroTab(identifier: "feed", viewController: hosted, item: item),
                makeTab("other")
            ],
            selectedIdentifier: "feed",
            animated: false
        )
        present(controller)
        controller.view.layoutIfNeeded()
        scrolling.loadViewIfNeeded()
        controller.refreshScrollTracking()
        return (controller, scrolling)
    }

    /// 位移相對於「靜止在頂部」的位置。
    ///
    /// 捲動視圖的靜止 `contentOffset.y` 是 `-adjustedContentInset.top`（安全區造成），
    /// 直接設定絕對值會讓「捲 20 點」實際上變成捲 79 點。
    private func scroll(_ scrolling: ScrollingViewController, to offset: CGFloat) {
        let top = -scrolling.scrollView.adjustedContentInset.top
        scrolling.scrollView.simulatesDragging = true
        scrolling.scrollView.contentOffset = CGPoint(x: 0, y: top + offset)
        scrolling.scrollView.simulatesDragging = false
    }

    /// 與追蹤器同一套算法：可捲動的最大位移。
    private func maximumOffset(_ scrolling: ScrollingViewController) -> CGFloat {
        let scrollView = scrolling.scrollView
        let visible = scrollView.bounds.height
            - scrollView.adjustedContentInset.top
            - scrollView.adjustedContentInset.bottom
        return max(0, scrollView.contentSize.height - visible)
    }

    private var isFloatingAvailable: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    // MARK: 不搶 delegate

    func test_packageNeverTakesOverTheScrollViewDelegate() {
        let (_, scrolling) = makeSetup()

        XCTAssertIdentical(scrolling.scrollView.delegate, scrolling, "delegate 必須仍是 consumer 自己")

        scroll(scrolling, to: 100)

        XCTAssertGreaterThan(scrolling.ownDelegateCallbacks, 0, "consumer 的 delegate 回呼仍應被呼叫")
    }

    // MARK: 收合與展開

    func test_scrollingDownMinimizes() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let (controller, scrolling) = makeSetup(behavior: .minimizeOnScrollDown)

        scroll(scrolling, to: 20)
        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
        scroll(scrolling, to: 60)

        XCTAssertEqual(controller.tabBarPresentationState, .minimized)
    }

    func test_scrollingDownHides() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)

        scroll(scrolling, to: 60)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden)
    }

    func test_scrollingBackUpExpands() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        scroll(scrolling, to: 300)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)

        scroll(scrolling, to: 260)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_returningToTopExpands() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        scroll(scrolling, to: 300)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)

        scroll(scrolling, to: 0)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_reboundAtBottomDoesNotFlicker() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        let maximum = maximumOffset(scrolling)
        scroll(scrolling, to: maximum)
        let settled = controller.tabBarPresentationState

        scroll(scrolling, to: maximum + 60)
        scroll(scrolling, to: maximum + 90)

        XCTAssertEqual(controller.tabBarPresentationState, settled, "拉過底部不該改變狀態")
    }

    func test_noneBehaviorKeepsExpanded() {
        let (controller, scrolling) = makeSetup(behavior: TeroTabBarScrollBehavior.none)

        scroll(scrolling, to: 500)
        scroll(scrolling, to: 0)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    // MARK: 行為解析

    func test_visibleViewControllerPreferenceOverridesConfiguration() {
        let scrolling = PreferringScrollingViewController()
        scrolling.behavior = .hideOnScrollDown
        let item = TeroTabItem(title: "feed", image: nil, selectedImage: nil)
        item.accessibilityIdentifier = "tab.feed"

        // 設定裡是 .none，但畫面表達了 .hideOnScrollDown
        let controller = makeController(configuration: makeFloatingConfiguration(behavior: TeroTabBarScrollBehavior.none))
        controller.setTabs(
            [TeroTab(identifier: "feed", viewController: scrolling, item: item)],
            selectedIdentifier: nil,
            animated: false
        )
        present(controller)
        scrolling.loadViewIfNeeded()
        controller.refreshScrollTracking()

        scroll(scrolling, to: 60)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "畫面偏好應覆蓋設定")
    }

    func test_viewControllerPreferenceOfNoneSuppressesScrolling() {
        let scrolling = PreferringScrollingViewController()
        scrolling.behavior = .none
        let item = TeroTabItem(title: "feed", image: nil, selectedImage: nil)
        item.accessibilityIdentifier = "tab.feed"

        // 設定裡是 .hideOnScrollDown，但畫面明確表達不參與
        let controller = makeController(configuration: makeFloatingConfiguration(behavior: .hideOnScrollDown))
        controller.setTabs(
            [TeroTab(identifier: "feed", viewController: scrolling, item: item)],
            selectedIdentifier: nil,
            animated: false
        )
        present(controller)
        scrolling.loadViewIfNeeded()
        controller.refreshScrollTracking()

        scroll(scrolling, to: 300)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded, "`.none` 也是一種偏好")
    }

    func test_classicDowngradesMinimizeToHide() {
        let configuration = makeFloatingConfiguration(behavior: .minimizeOnScrollDown)
        configuration.style = .classic
        let scrolling = ScrollingViewController()
        let item = TeroTabItem(title: "feed", image: nil, selectedImage: nil)
        item.accessibilityIdentifier = "tab.feed"
        let controller = makeController(configuration: configuration)
        controller.setTabs(
            [TeroTab(identifier: "feed", viewController: scrolling, item: item)],
            selectedIdentifier: nil,
            animated: false
        )
        present(controller)
        scrolling.loadViewIfNeeded()
        controller.refreshScrollTracking()

        scroll(scrolling, to: 60)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "Classic 不支援最小化，應降級為隱藏")
    }

    // MARK: 追蹤對象解析

    func test_navigationControllerUsesItsVisibleViewController() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown, wrapInNavigation: true)

        scroll(scrolling, to: 60)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "應追蹤 visibleViewController 而非容器")
    }

    func test_noProviderKeepsBarExpanded() {
        let controller = makeController(configuration: makeFloatingConfiguration(behavior: .hideOnScrollDown))
        let item = TeroTabItem(title: "plain", image: nil, selectedImage: nil)
        item.accessibilityIdentifier = "tab.plain"
        controller.setTabs(
            [TeroTab(identifier: "plain", viewController: PlainViewController(), item: item)],
            selectedIdentifier: nil,
            animated: false
        )
        present(controller)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_refreshScrollTrackingPicksUpANewScrollView() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        scroll(scrolling, to: 300)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)

        // 換掉追蹤對象：重新解析後應回到展開
        controller.refreshScrollTracking()

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    // MARK: 切換 Tab

    func test_switchingTabResetsToExpanded() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        scroll(scrolling, to: 300)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)

        controller.selectTab(withIdentifier: "other", animated: false)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded, "新 Tab 預設展開")
    }

    // MARK: 鎖定

    func test_programmaticHideLocksOutScrolling() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        XCTAssertTrue(controller.setTabBarPresentationState(.hidden, animated: false))

        scroll(scrolling, to: 300)
        scroll(scrolling, to: 0)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "鎖定期間連回到頂部也不展開")
    }

    func test_lockSurvivesTabSwitching() {
        let (controller, _) = makeSetup(behavior: .hideOnScrollDown)
        controller.setTabBarPresentationState(.hidden, animated: false)

        controller.selectTab(withIdentifier: "other", animated: false)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "鎖定優先於切換 Tab 的重置")
    }

    func test_expandingReleasesTheLock() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        controller.setTabBarPresentationState(.hidden, animated: false)
        XCTAssertTrue(controller.setTabBarPresentationState(.expanded, animated: false))

        scroll(scrolling, to: 60)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "解鎖後捲動應重新生效")
    }

    // MARK: Safe area 依驅動來源分流

    func test_scrollDrivenChangeDoesNotTouchSafeArea() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        let before = controller.children.map(\.additionalSafeAreaInsets.bottom)

        scroll(scrolling, to: 300)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)

        let after = controller.children.map(\.additionalSafeAreaInsets.bottom)
        XCTAssertEqual(before, after, "捲動驅動的變更不得更動 safe area，否則會形成回授迴圈")
        XCTAssertTrue(after.allSatisfy { $0 > 0 })
    }

    func test_programmaticHideDoesTouchSafeArea() {
        let (controller, _) = makeSetup(behavior: .hideOnScrollDown)
        XCTAssertTrue(controller.children.allSatisfy { $0.additionalSafeAreaInsets.bottom > 0 })

        controller.setTabBarPresentationState(.hidden, animated: false)

        XCTAssertTrue(controller.children.allSatisfy { $0.additionalSafeAreaInsets.bottom == 0 })
    }

    // MARK: 事件

    func test_scrollDrivenChangeEmitsWillAndDid() {
        final class StateRecorder: NSObject, TeroTabBarControllerDelegate {
            var events: [String] = []
            func teroTabBarController(_ c: TeroTabBarController, willChangeTabBarPresentationState s: TeroTabBarPresentationState) {
                events.append("will(\(s.rawValue))")
            }
            func teroTabBarController(_ c: TeroTabBarController, didChangeTabBarPresentationState s: TeroTabBarPresentationState) {
                events.append("did(\(s.rawValue))")
            }
        }
        let states = StateRecorder()
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        controller.delegate = states

        scroll(scrolling, to: 300)

        XCTAssertEqual(states.events, ["will(2)", "did(2)"])
    }

    // MARK: 快速來回

    func test_rapidBackAndForthDoesNotOscillateBelowThresholds() {
        let (controller, scrolling) = makeSetup(behavior: .hideOnScrollDown)
        scroll(scrolling, to: 300)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)

        // 每次都不到門檻的來回抖動
        for offset in [295, 300, 296, 301, 297] as [CGFloat] {
            scroll(scrolling, to: offset)
        }

        XCTAssertEqual(controller.tabBarPresentationState, .hidden, "小幅抖動不該改變狀態")
    }
}
