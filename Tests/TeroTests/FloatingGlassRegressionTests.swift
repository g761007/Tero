import XCTest
import UIKit
@testable import Tero

/// 會回報連續進度的自訂內容（§35）。
private final class ProgressProvider: NSObject, TeroTabInteractiveContentProvider {
    private(set) var selectionSamples: [CGFloat] = []
    private(set) var presentationSamples: [CGFloat] = []
    func resetPresentationSamples() { presentationSamples.removeAll() }
    func makeContentView() -> UIView { UIView() }
    func updateContentView(_ contentView: UIView, selectionProgress: CGFloat, animated: Bool) {
        selectionSamples.append(selectionProgress)
    }
    func updateContentView(_ contentView: UIView, presentationProgress: CGFloat, animated: Bool) {
        presentationSamples.append(presentationProgress)
    }
}

/// Phase 10：FloatingGlass 的互動行為在兩層容器下不回歸。
///
/// §33 列的項目 1.1.0 與 alpha.0 就有，71 個既有測試涵蓋它們——但那些測試都只跑
/// **單獨的 TeroTabBarController**。Phase 9 才把 Tab Bar 與 stack 容器疊起來，
/// 而那一次就抓到一個只有整合視角看得見的缺口。這裡是同樣的重驗。
final class FloatingGlassRegressionTests: TeroTabBarControllerTestCase {

    private func nested(
        provider: TeroTabContentProvider? = nil
    ) -> (TeroTabBarController, [TeroNavigationContainer]) {
        let containers = (0..<3).map { _ in TeroNavigationContainer(rootViewController: UIViewController()) }
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        let controller = TeroTabBarController(configuration: configuration)
        let tabs = containers.enumerated().map { index, container -> TeroTab in
            let item = TeroTabItem(title: "T\(index)", image: nil, selectedImage: nil)
            item.accessibilityIdentifier = "tab.t\(index)"
            if index == 1, let provider { item.contentProvider = provider }
            return TeroTab(identifier: "t\(index)", viewController: container, item: item)
        }
        controller.setTabs(tabs, selectedIdentifier: "t0", animated: false)
        present(controller)
        return (controller, containers)
    }

    // MARK: - 選取轉場

    func test_selectionStillMovesWhenTabsHoldStackContainers() {
        let (controller, _) = nested()

        XCTAssertTrue(controller.selectTab(withIdentifier: "t2", animated: false))

        XCTAssertEqual(controller.selectedIndex, 2)
        XCTAssertEqual(controller.selectedTab?.identifier, "t2")
    }

    func test_reselectingATabWithAStackDoesNotPopIt() {
        let (controller, containers) = nested()
        let detail = UIViewController()
        containers[0].pushViewController(detail, animated: false)

        controller.selectTab(withIdentifier: "t0", animated: false)

        XCTAssertIdentical(containers[0].topViewController, detail,
                           "didReselect 不自動 popToRoot——那是 consumer 的決定（1.x 既有契約）")
    }

    func test_interruptedSelectionStillEndsOnTheLastRequestedTab() {
        let (controller, _) = nested()

        controller.selectTab(withIdentifier: "t1", animated: true)
        controller.selectTab(withIdentifier: "t2", animated: true)
        controller.selectTab(withIdentifier: "t0", animated: true)

        XCTAssertEqual(controller.selectedIndex, 0, "連續請求只有最後一個算數")
    }

    // MARK: - 自訂內容的連續進度（§35）

    func test_theContentProviderStillReceivesSelectionProgress() {
        let provider = ProgressProvider()
        let (controller, _) = nested(provider: provider)

        controller.selectTab(withIdentifier: "t1", animated: true)
        waitUntil("轉場推進") { provider.selectionSamples.contains { $0 > 0 && $0 < 1 } }

        XCTAssertTrue(provider.selectionSamples.contains { $0 > 0 && $0 < 1 },
                      "連續進度要一路送到 provider，不是只給端點")
    }

    func test_theContentProviderStillReceivesPresentationProgress() {
        let provider = ProgressProvider()
        let (controller, _) = nested(provider: provider)
        controller.selectTab(withIdentifier: "t1", animated: false)
        provider.resetPresentationSamples()

        controller.setTabBarPresentationState(.minimized, animated: true)
        waitUntil("收合推進") { !provider.presentationSamples.isEmpty }

        XCTAssertFalse(provider.presentationSamples.isEmpty)
    }

    // MARK: - §33 明確不做的那一項

    func test_badgeDoesNotFollowTheIconScale() throws {
        let (controller, _) = nested()
        controller.setBadge(TeroTabBadge.value("999+"), forTabWithIdentifier: "t1", animated: false)
        controller.view.layoutIfNeeded()

        // 兩端都先解包。找不到控制項時兩邊同為 nil，XCTAssertEqual 會綠——
        // 那種綠燈代表「什麼都沒比對到」，不代表 Badge 沒跟著縮放。
        let control = try XCTUnwrap(tabBarControl(for: "t1", in: controller))
        let badgeBefore = try XCTUnwrap(control.subviews.first { $0 is TeroTabBadgeView }?.frame)

        controller.selectTab(withIdentifier: "t1", animated: true)
        controller.view.layoutIfNeeded()
        let badgeDuring = try XCTUnwrap(control.subviews.first { $0 is TeroTabBadgeView }?.frame)

        XCTAssertEqual(badgeBefore, badgeDuring,
                       "Badge 錨在未縮放的版面矩形上——跟著縮放會讓長 Badge 每次切換都抖一下")
    }

    // MARK: - 收合與 stack 同時作用

    func test_minimizingWhileAStackIsDeepKeepsBothStates() {
        let (controller, containers) = nested()
        let detail = UIViewController()
        containers[0].pushViewController(detail, animated: false)

        controller.setTabBarPresentationState(.minimized, animated: false)

        XCTAssertEqual(controller.tabBarPresentationState, .minimized)
        XCTAssertIdentical(containers[0].topViewController, detail, "兩層各自的狀態互不干擾")
    }

    func test_switchingTabsKeepsEachStackAndRestoresSelection() {
        let (controller, containers) = nested()
        let first = UIViewController()
        let second = UIViewController()
        containers[0].pushViewController(first, animated: false)
        controller.selectTab(withIdentifier: "t1", animated: false)
        containers[1].pushViewController(second, animated: false)

        controller.selectTab(withIdentifier: "t0", animated: false)

        XCTAssertIdentical(containers[0].topViewController, first)
        XCTAssertIdentical(containers[1].topViewController, second)
        XCTAssertEqual(controller.selectedIndex, 0)
    }
}
