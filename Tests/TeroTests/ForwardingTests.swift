import XCTest
import UIKit
@testable import Tero

/// 對應計畫書 §46。
final class ForwardingTests: TeroTabBarControllerTestCase {

    private final class StyledViewController: UIViewController {
        var style: UIStatusBarStyle = .default
        var hidesStatusBar = false
        var hidesHomeIndicator = false
        var deferredEdges: UIRectEdge = []
        var orientations: UIInterfaceOrientationMask = .all
        var presentationOrientation: UIInterfaceOrientation = .portrait
        override var preferredStatusBarStyle: UIStatusBarStyle { style }
        override var prefersStatusBarHidden: Bool { hidesStatusBar }
        override var prefersHomeIndicatorAutoHidden: Bool { hidesHomeIndicator }
        override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { deferredEdges }
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { orientations }
        override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
            presentationOrientation
        }
    }

    func test_statusBarAndHomeIndicatorAreForwardedToSelectedChild() {
        let controller = makeController()

        let light = StyledViewController()
        light.style = .lightContent
        light.hidesStatusBar = true
        light.hidesHomeIndicator = true

        let dark = StyledViewController()
        dark.style = .darkContent

        let tabs = [
            TeroTab(identifier: "light", viewController: light,
                    item: TeroTabItem(title: nil, image: nil, selectedImage: nil)),
            TeroTab(identifier: "dark", viewController: dark,
                    item: TeroTabItem(title: nil, image: nil, selectedImage: nil))
        ]
        controller.setTabs(tabs, selectedIdentifier: "light", animated: false)
        present(controller)

        XCTAssertIdentical(controller.childForStatusBarStyle, light)
        XCTAssertIdentical(controller.childForStatusBarHidden, light)
        XCTAssertIdentical(controller.childForHomeIndicatorAutoHidden, light)
        XCTAssertEqual(controller.childForStatusBarStyle?.preferredStatusBarStyle, .lightContent)
        XCTAssertEqual(controller.childForStatusBarHidden?.prefersStatusBarHidden, true)
        XCTAssertEqual(controller.childForHomeIndicatorAutoHidden?.prefersHomeIndicatorAutoHidden, true)

        controller.selectTab(withIdentifier: "dark", animated: false)

        XCTAssertIdentical(controller.childForStatusBarStyle, dark)
        XCTAssertEqual(controller.childForStatusBarStyle?.preferredStatusBarStyle, .darkContent)
        XCTAssertEqual(controller.childForStatusBarHidden?.prefersStatusBarHidden, false)
    }

    func test_withNoTabs_forwardingTargetsAreNil() {
        let controller = makeController()
        present(controller)

        XCTAssertNil(controller.childForStatusBarStyle)
        XCTAssertNil(controller.childForHomeIndicatorAutoHidden)
    }

    // MARK: - 兩層鏈（2.0 計畫書 §41–§43）

    /// UIKit 會一路往下問到 `childFor…` 回 nil 為止，這裡照同樣的方式解析。
    ///
    /// 只斷言某一層的欄位不夠：兩層各自轉發正確、中間卻接不起來，單層測試照樣全綠。
    private func resolved(
        from root: UIViewController,
        _ keyPath: KeyPath<UIViewController, UIViewController?>
    ) -> UIViewController {
        var current = root
        while let next = current[keyPath: keyPath] { current = next }
        return current
    }

    private func nestedController(
        detail: UIViewController,
        root: UIViewController = UIViewController(),
        other: UIViewController = UIViewController()
    ) -> TeroTabBarController {
        let first = TeroNavigationContainer(rootViewController: root)
        let second = TeroNavigationContainer(rootViewController: other)
        let controller = makeController()
        controller.setTabs([
            TeroTab(identifier: "a", viewController: first,
                    item: TeroTabItem(title: nil, image: nil, selectedImage: nil)),
            TeroTab(identifier: "b", viewController: second,
                    item: TeroTabItem(title: nil, image: nil, selectedImage: nil))
        ], selectedIdentifier: "a", animated: false)
        present(controller)
        first.pushViewController(detail, animated: false)
        return controller
    }

    func test_statusBarResolvesThroughBothLayersToTheTopViewController() {
        let detail = StyledViewController()
        detail.style = .lightContent
        detail.hidesStatusBar = true
        let controller = nestedController(detail: detail)

        XCTAssertIdentical(resolved(from: controller, \.childForStatusBarStyle), detail)
        XCTAssertIdentical(resolved(from: controller, \.childForStatusBarHidden), detail)
        XCTAssertEqual(resolved(from: controller, \.childForStatusBarStyle).preferredStatusBarStyle,
                       .lightContent)
        XCTAssertEqual(resolved(from: controller, \.childForStatusBarHidden).prefersStatusBarHidden,
                       true)
    }

    func test_homeIndicatorResolvesThroughBothLayersToTheTopViewController() {
        let detail = StyledViewController()
        detail.hidesHomeIndicator = true
        let controller = nestedController(detail: detail)

        XCTAssertIdentical(resolved(from: controller, \.childForHomeIndicatorAutoHidden), detail)
        XCTAssertEqual(
            resolved(from: controller, \.childForHomeIndicatorAutoHidden).prefersHomeIndicatorAutoHidden,
            true
        )
    }

    /// 這一項在 Phase 11 之前是斷的：容器有轉發，Tab 這層沒有，
    /// 於是最上層 VC 的邊緣手勢延後宣告永遠到不了系統。
    func test_screenEdgeDeferralResolvesThroughBothLayersToTheTopViewController() {
        let detail = StyledViewController()
        detail.deferredEdges = .left
        let controller = nestedController(detail: detail)

        XCTAssertIdentical(resolved(from: controller, \.childForScreenEdgesDeferringSystemGestures),
                           detail)
        XCTAssertEqual(
            resolved(from: controller, \.childForScreenEdgesDeferringSystemGestures)
                .preferredScreenEdgesDeferringSystemGestures,
            .left
        )
    }

    func test_supportedOrientationsFollowTheTopOfTheSelectedTab() {
        let detail = StyledViewController()
        detail.orientations = .portrait
        let controller = nestedController(detail: detail)

        XCTAssertEqual(controller.supportedInterfaceOrientations, .portrait,
                       "方向宣告由最上層可見 VC 決定，不是由容器自己決定")
    }

    func test_poppingRestoresTheOrientationOfTheViewControllerBelow() throws {
        // 兩端都給明確的值。若只斷言「不再是 portrait」，沒接上轉發時拿到的預設值
        // 本來就不是 portrait——那種測試修不修都綠。
        let root = StyledViewController()
        root.orientations = .landscape
        let detail = StyledViewController()
        detail.orientations = .portrait
        let controller = nestedController(detail: detail, root: root)
        let container = try XCTUnwrap(controller.selectedViewController as? TeroNavigationContainer)

        XCTAssertEqual(controller.supportedInterfaceOrientations, .portrait)

        container.popViewController(animated: false)

        XCTAssertEqual(controller.supportedInterfaceOrientations, .landscape,
                       "限制隨著它的 VC 一起離開，換成下面那一個的宣告")
    }

    func test_switchingTabsChangesTheResolvedOrientation() {
        let detail = StyledViewController()
        detail.orientations = .portrait
        let other = StyledViewController()
        other.orientations = .landscape
        let controller = nestedController(detail: detail, other: other)

        controller.selectTab(withIdentifier: "b", animated: false)

        XCTAssertEqual(controller.supportedInterfaceOrientations, .landscape)
    }

    func test_preferredPresentationOrientationFollowsTheSameChain() {
        let detail = StyledViewController()
        detail.presentationOrientation = .landscapeLeft
        let controller = nestedController(detail: detail)

        XCTAssertEqual(controller.preferredInterfaceOrientationForPresentation, .landscapeLeft)
    }
}
