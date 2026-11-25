import XCTest
import UIKit
@testable import Tero

/// 宣告自己要隱藏 Tab Bar 的頁面（§37）。
private final class HidingPage: UIViewController, TeroTabVisibilityProviding {
    var preferredTeroTabVisibilityPolicy: TeroTabVisibilityPolicy { .hidden }
}

/// 有頂部 chrome、也交出捲動輸入的頁面。
private final class ScrollingChromePage: UIViewController,
                                         TeroNavigationChromeProviding,
                                         TeroScrollProviding {
    /// 收合只吃使用者驅動的捲動；程式設定 offset 不算，否則 Tero 自己造成的
    /// inset 變動就會把 chrome 收掉。
    final class DraggingScrollView: UIScrollView {
        var simulatesDragging = false
        override var isDragging: Bool { simulatesDragging || super.isDragging }
    }
    let scrollView = DraggingScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        scrollView.contentSize = CGSize(width: 390, height: 4000)
        view.addSubview(scrollView)
    }

    func drag(to offset: CGFloat) {
        scrollView.simulatesDragging = true
        scrollView.contentOffset = CGPoint(x: 0, y: offset)
        scrollView.simulatesDragging = false
    }

    var teroTrackingScrollView: UIScrollView? { scrollView }
    func makeTeroNavigationChromeView() -> UIView { UIView() }
    var teroNavigationChromeHeight: CGFloat { 96 }
    var teroNavigationChromeCollapsedHeight: CGFloat { 44 }
}

/// Phase 9：Tab 與 Navigation 的整合。
///
/// 兩層容器真的疊起來之後才驗得到的東西：各 tab 的 stack 獨立、push 到 detail 時
/// Tab Bar 隱藏、互動式返回取消後完整復原。
final class TabNavigationIntegrationTests: TeroTabBarControllerTestCase {

    private func makeController(
        containers: [TeroNavigationContainer],
        configuration: TeroTabBarConfiguration = .defaultConfiguration()
    ) -> TeroTabBarController {
        let controller = TeroTabBarController(configuration: configuration)
        let tabs = containers.enumerated().map { index, container in
            TeroTab(
                identifier: "t\(index)",
                viewController: container,
                item: TeroTabItem(title: "T\(index)", image: nil, selectedImage: nil)
            )
        }
        controller.setTabs(tabs, selectedIdentifier: "t0", animated: false)
        present(controller)
        return controller
    }

    // MARK: - 捲動樣本要一路走到頂部 chrome

    /// 這條線斷過：政策型別、設定、測試都在，但 `Sources/` 裡沒有任何一處把樣本
    /// 交給容器——功能在單元測試裡全綠，在真的 App 裡完全不會動。
    func test_scrollingCollapsesTheChromeOfTheSelectedTab() {
        let page = ScrollingChromePage()
        let container = TeroNavigationContainer(rootViewController: page)
        _ = makeController(containers: [container])
        page.loadViewIfNeeded()

        page.drag(to: 400)

        XCTAssertGreaterThan(container.chromeCollapseProgress, 0,
                             "Tab Bar 的追蹤路徑要把樣本轉給容器，否則 chrome 永遠不收")
    }

    /// issue #97：單獨使用的容器自己追蹤 top 的 scroll view。
    func test_aStandaloneContainerCollapsesItsChromeFromItsOwnTracking() {
        let page = ScrollingChromePage()
        let container = TeroNavigationContainer(rootViewController: page)
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        page.loadViewIfNeeded()
        XCTAssertTrue(container.isTrackingScrollViewItself, "沒有上層餵樣本，就自己觀察")

        page.drag(to: 400)

        XCTAssertGreaterThan(container.chromeCollapseProgress, 0,
                             "不在 Tab Bar 底下也要能收合——這正是欠條 4 的缺口")
    }

    /// 兩條路徑互斥：Tab Bar 餵樣本時，容器自己的追蹤器不觀察同一個 scroll view。
    func test_aContainerUnderATabBarDoesNotAlsoTrackTheScrollViewItself() {
        let page = ScrollingChromePage()
        let container = TeroNavigationContainer(rootViewController: page)
        let controller = makeController(containers: [container])
        page.loadViewIfNeeded()

        XCTAssertTrue(container.receivesExternalScrollSamples)
        XCTAssertFalse(container.isTrackingScrollViewItself,
                       "同一個 scroll view 兩個觀察者會各算一套方向鎖")

        controller.setTabs([], selectedIdentifier: nil, animated: false)
        XCTAssertFalse(container.receivesExternalScrollSamples, "離開 Tab Bar 之後把權責交回容器")
    }

    func test_chromeOfAnUnselectedTabIsNotDrivenByTheOtherTabsScrolling() {
        let visible = ScrollingChromePage()
        let hidden = ScrollingChromePage()
        let first = TeroNavigationContainer(rootViewController: visible)
        let second = TeroNavigationContainer(rootViewController: hidden)
        _ = makeController(containers: [first, second])
        visible.loadViewIfNeeded()

        visible.drag(to: 400)

        XCTAssertEqual(second.chromeCollapseProgress, 0, "樣本只走到選取的那一個")
    }

    // MARK: - issue #102：Tab Bar 的邊緣互動只在有追蹤對象時才裝

    /// 裝著沒事做的互動會讓 iOS 26 的 observation tracking 把 `TeroTabBar` 的
    /// `updateProperties` 判成回饋迴圈——完整測試日誌 1144 則警告，拆掉就歸零。
    func test_theTabBarInstallsTheScrollEdgeInteractionOnlyWhileAScrollViewIsTracked() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("UIScrollEdgeElementContainerInteraction 是 iOS 26 API") }
        let page = ScrollingChromePage()
        let scrolling = TeroNavigationContainer(rootViewController: page)
        let plain = TeroNavigationContainer(rootViewController: UIViewController())
        let controller = makeController(containers: [scrolling, plain])
        page.loadViewIfNeeded()
        XCTAssertTrue(controller.tabBar.hasScrollEdgeInteraction, "有追蹤對象就裝")

        controller.selectTab(withIdentifier: "t1", animated: false)

        XCTAssertFalse(controller.tabBar.hasScrollEdgeInteraction, "沒有就拆，不留一顆沒事做的")
    }

    // MARK: - §36：各 tab 的 stack 獨立

    func test_eachTabKeepsItsOwnStack() {
        let first = TeroNavigationContainer(rootViewController: UIViewController())
        let second = TeroNavigationContainer(rootViewController: UIViewController())
        let controller = makeController(containers: [first, second])

        let detail = UIViewController()
        first.pushViewController(detail, animated: false)
        controller.selectTab(withIdentifier: "t1", animated: false)
        controller.selectTab(withIdentifier: "t0", animated: false)

        XCTAssertIdentical(first.topViewController, detail, "切走再回來，stack 要留著")
        XCTAssertEqual(second.viewControllers.count, 1, "另一個 tab 不受影響")
    }

    // MARK: - §37／§39：push 到宣告隱藏的頁面

    func test_pushingAHidingPageHidesTheTabBar() {
        let container = TeroNavigationContainer(rootViewController: UIViewController())
        let controller = makeController(containers: [container])
        XCTAssertEqual(controller.tabBarPresentationState, .expanded)

        container.pushViewController(HidingPage(), animated: false)

        XCTAssertEqual(controller.tabBarPresentationState, .hidden)
    }

    func test_poppingBackRestoresTheTabBar() {
        let container = TeroNavigationContainer(rootViewController: UIViewController())
        let controller = makeController(containers: [container])
        container.pushViewController(HidingPage(), animated: false)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)

        container.popViewController(animated: false)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_aContainerThatIsNotSelectedDoesNotMoveTheTabBar() {
        let first = TeroNavigationContainer(rootViewController: UIViewController())
        let second = TeroNavigationContainer(rootViewController: UIViewController())
        let controller = makeController(containers: [first, second])

        // 第二個 tab 沒有被選取，它的轉場不該動到 Tab Bar。
        second.pushViewController(HidingPage(), animated: false)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    // MARK: - 互動式返回

    func test_cancellingAnInteractivePopLeavesTheTabBarHidden() {
        let container = TeroNavigationContainer(rootViewController: UIViewController())
        container.transitionDuration = 0.1
        let controller = makeController(containers: [container])
        container.pushViewController(HidingPage(), animated: false)
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)

        container.beginInteractivePop()
        container.endInteractivePop(progress: 0.1, velocity: 0)
        waitUntil("手勢結算") { container.transitionState == .idle }

        XCTAssertEqual(controller.tabBarPresentationState, .hidden,
                       "取消之後 stack 沒變，Tab Bar 也要回到隱藏")
        XCTAssertTrue(container.topViewController is HidingPage)
    }

    func test_finishingAnInteractivePopRestoresTheTabBar() {
        let container = TeroNavigationContainer(rootViewController: UIViewController())
        container.transitionDuration = 0.1
        let controller = makeController(containers: [container])
        container.pushViewController(HidingPage(), animated: false)

        container.beginInteractivePop()
        container.endInteractivePop(progress: 0.9, velocity: 0)
        waitUntil("手勢結算") { container.transitionState == .idle }

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_aStackChangeDuringAGestureStillSettlesTheTabBar() {
        let container = TeroNavigationContainer(rootViewController: UIViewController())
        container.transitionDuration = 0.1
        let controller = makeController(containers: [container])
        container.pushViewController(HidingPage(), animated: false)

        container.beginInteractivePop()
        container.pushViewController(UIViewController(), animated: false)
        waitUntil("轉場結算") { container.transitionState == .idle }

        XCTAssertEqual(controller.tabBarPresentationState, .expanded,
                       "手勢被打斷也要結算——否則 Tab Bar 會卡在 preview 狀態")
    }

    // MARK: - B20：容器是導管

    func test_theContainerReportsTheTopPagePolicy() {
        let container = TeroNavigationContainer(rootViewController: UIViewController())

        XCTAssertEqual(container.preferredTeroTabVisibilityPolicy, .inherit, "root 沒表態")

        container.pushViewController(HidingPage(), animated: false)

        XCTAssertEqual(container.preferredTeroTabVisibilityPolicy, .hidden, "原封轉發 top 的宣告")
    }

    // MARK: - 每一頁各自讓出 Tab Bar（ADR-0004 修訂）

    // 轉場中兩頁同時在畫面上：底部保留寫在整個容器上的話，兩頁只能共用一個值，
    // 轉場中是來源頁的、結算時一次換成目的頁的，其中一頁的底部一定會跳。

    private func bottom(of page: UIViewController, in controller: TeroTabBarController) -> CGFloat {
        controller.view.layoutIfNeeded()
        return page.view.safeAreaInsets.bottom
    }

    func test_duringAnInteractivePop_thePageBelowKeepsTheBottomItHadBeforeThePush() {
        let root = UIViewController()
        let container = TeroNavigationContainer(rootViewController: root)
        let controller = makeController(containers: [container])
        let before = bottom(of: root, in: controller)
        XCTAssertGreaterThan(before, controller.view.safeAreaInsets.bottom, "前提：root 讓出了 Tab Bar")
        container.pushViewController(HidingPage(), animated: false)

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.3)

        XCTAssertEqual(bottom(of: root, in: controller), before, accuracy: 0.5,
                       "Tab Bar 會跟著回來的那一頁，整段手勢都要讓出它，不是等 finish 才跳")
        container.endInteractivePop(progress: 0.3, velocity: 0)
        waitUntil("手勢結算") { container.transitionState == .idle }
    }

    func test_duringAnAnimatedPush_aPageThatHidesTheTabBarIsLaidOutWithoutItFromTheStart() {
        let root = UIViewController()
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = 1.0
        let controller = makeController(containers: [container])
        let rootBottom = bottom(of: root, in: controller)
        let hiding = HidingPage()

        container.pushViewController(hiding, animated: true)

        XCTAssertEqual(bottom(of: hiding, in: controller), controller.view.safeAreaInsets.bottom, accuracy: 0.5,
                       "不顯示 Tab Bar 的頁不替它留位；等結算才收回，底部的輸入列會在結束那一刻往下跳")
        XCTAssertEqual(bottom(of: root, in: controller), rootBottom, accuracy: 0.5, "被蓋住的那一頁不變")
        waitUntil("轉場結算") { container.transitionState == .idle }
        XCTAssertEqual(bottom(of: hiding, in: controller), controller.view.safeAreaInsets.bottom, accuracy: 0.5)
    }

    func test_duringAnAnimatedPop_bothPagesKeepTheirOwnBottom() {
        let root = UIViewController()
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = 1.0
        let controller = makeController(containers: [container])
        let rootBottom = bottom(of: root, in: controller)
        let hiding = HidingPage()
        container.pushViewController(hiding, animated: false)

        container.popViewController(animated: true)

        XCTAssertEqual(bottom(of: root, in: controller), rootBottom, accuracy: 0.5, "回來的那一頁不必等結算")
        XCTAssertEqual(bottom(of: hiding, in: controller), controller.view.safeAreaInsets.bottom, accuracy: 0.5,
                       "滑出去的那一頁也不變")
        waitUntil("轉場結算") { container.transitionState == .idle }
        XCTAssertEqual(bottom(of: root, in: controller), rootBottom, accuracy: 0.5)
    }

    func test_underTheProgrammaticLock_aPageDraggedBackReservesNothing() {
        let root = UIViewController()
        let container = TeroNavigationContainer(rootViewController: root)
        let controller = makeController(containers: [container])
        controller.setTabBarPresentationState(.hidden, animated: false)
        container.pushViewController(UIViewController(), animated: false)

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.3)

        XCTAssertEqual(bottom(of: root, in: controller), controller.view.safeAreaInsets.bottom, accuracy: 0.5,
                       "鎖定期間 Tab Bar 不會出現，拉回來的那一頁不該替它留位")
        container.endInteractivePop(progress: 0.3, velocity: 0)
        waitUntil("手勢結算") { container.transitionState == .idle }
    }

    /// 程式最小化讓出的是最小化的高度（ADR-0004：程式驅動才動 inset）。這只屬於當時在上面的
    /// 那一頁；push 時它被蓋住，仍要維持離開時的樣子。
    func test_aProgrammaticMinimizeStaysWithThePageItWasSetOn() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("FloatingGlass 需要 iOS 26+") }
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        let root = UIViewController()
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = 1.0
        let controller = makeController(containers: [container], configuration: configuration)
        let expanded = bottom(of: root, in: controller)
        XCTAssertTrue(controller.setTabBarPresentationState(.minimized, animated: false))
        let minimized = bottom(of: root, in: controller)
        XCTAssertLessThan(minimized, expanded, "前提：最小化讓出的比較少")

        container.pushViewController(UIViewController(), animated: true)

        XCTAssertEqual(bottom(of: root, in: controller), minimized, accuracy: 0.5)
        waitUntil("轉場結算") { container.transitionState == .idle }
    }
}
