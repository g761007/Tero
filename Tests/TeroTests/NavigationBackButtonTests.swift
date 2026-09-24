import XCTest
import UIKit
@testable import Tero

/// 鏡射的返回鍵看的是 stack 的位置：root 沒有返回鍵，與 UIKit 相同。
///
/// 這個答案只有容器知道。chrome 在 stack 提交之前就建立，建好之後也不重建，
/// 所以頁面在 `makeTeroNavigationChromeView()` 裡自己判斷 root，會在換 root、
/// 空容器 push、root 被拿掉這幾種情況答錯。這裡的頁面一律照傳 `backAction`，由容器決定。
final class NavigationBackButtonTests: TeroTabBarControllerTestCase {

    private final class MirrorPage: UIViewController, TeroNavigationChromeProviding {
        let name: String
        /// true 時把 bar 包在自己的 view 裡，模擬自訂 chrome 內含 `TeroNavigationBar`。
        let wrapsTheBar: Bool
        private(set) var bar: TeroNavigationBar?

        init(_ name: String, wrapsTheBar: Bool = false) {
            self.name = name
            self.wrapsTheBar = wrapsTheBar
            super.init(nibName: nil, bundle: nil)
            navigationItem.title = name
        }
        required init?(coder: NSCoder) { fatalError() }

        func makeTeroNavigationChromeView() -> UIView {
            let bar = TeroNavigationBar(frame: .zero)
            bar.bind(to: navigationItem, backAction: {})
            self.bar = bar
            guard wrapsTheBar else { return bar }
            let wrapper = UIView()
            bar.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(bar)
            return wrapper
        }

        var teroNavigationChromeHeight: CGFloat { TeroNavigationBar.primaryHeight }

        /// 沒有設 left items，所以 leading 側有東西就是合成的返回鍵。
        var showsBackButton: Bool { !(bar?.leadingItems.isEmpty ?? true) }
    }

    private func presented(_ container: TeroNavigationContainer) -> TeroNavigationContainer {
        container.transitionDuration = 0.2
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        return container
    }

    func test_theRootHasNoBackButtonAndAPushedPageHasOne() {
        let root = MirrorPage("root")
        let container = presented(TeroNavigationContainer(rootViewController: root))
        XCTAssertFalse(root.showsBackButton, "root 沒有上一頁")
        let detail = MirrorPage("detail")

        container.pushViewController(detail, animated: false)

        XCTAssertFalse(root.showsBackButton, "push 之後 root 仍然沒有")
        XCTAssertTrue(detail.showsBackButton)
    }

    func test_aNewRootFromSetViewControllersHasNoBackButton() {
        let container = presented(TeroNavigationContainer(rootViewController: MirrorPage("a")))
        container.pushViewController(MirrorPage("b"), animated: false)
        let x = MirrorPage("x")

        container.setViewControllers([x], animated: false)

        XCTAssertIdentical(container.rootViewController, x)
        XCTAssertFalse(x.showsBackButton, "x 的 chrome 在提交前建立，那時它看起來不是 root")
    }

    func test_theFirstPageOnAnEmptyContainerHasNoBackButton() {
        let container = presented(TeroNavigationContainer())
        let first = MirrorPage("first")

        container.pushViewController(first, animated: false)

        XCTAssertIdentical(container.rootViewController, first)
        XCTAssertFalse(first.showsBackButton)
    }

    func test_aPageThatBecomesTheRootLosesItsBackButton() {
        let container = presented(TeroNavigationContainer(rootViewController: MirrorPage("login")))
        let home = MirrorPage("home")
        container.pushViewController(home, animated: false)
        XCTAssertTrue(home.showsBackButton, "前置條件：push 上來時有返回鍵")

        container.setViewControllers([home], animated: false)

        XCTAssertFalse(home.showsBackButton, "底下那頁被拿掉之後，home 就是 root")
    }

    func test_aRootThatGetsAPageBelowItGainsABackButton() {
        let root = MirrorPage("root")
        let container = presented(TeroNavigationContainer(rootViewController: root))
        XCTAssertFalse(root.showsBackButton, "前置條件")

        container.setViewControllers([MirrorPage("below"), root], animated: false)

        XCTAssertTrue(root.showsBackButton)
    }

    /// 互動式返回把還沒顯示過的 root 拉出來，它的 chrome 在手勢開始時才建立。
    func test_aRootFirstShownByAnInteractivePopHasNoBackButton() {
        let container = presented(TeroNavigationContainer())
        let root = MirrorPage("root"), top = MirrorPage("top")
        container.setViewControllers([root, top], animated: false)
        XCTAssertNil(root.bar, "前置條件：root 還沒顯示過，還沒有 chrome")

        XCTAssertTrue(container.beginInteractivePop())

        XCTAssertNotNil(root.bar)
        XCTAssertFalse(root.showsBackButton)
        container.endInteractivePop(progress: 0, velocity: 0)
        waitUntil("取消的手勢結算") { container.transitionState == .idle }
    }

    /// pop 提交之後，離開的那一頁還在畫面上淡出；它的返回鍵不能在那一刻消失。
    func test_thePageThatIsPoppedKeepsItsBackButtonWhileItAnimatesAway() {
        let container = presented(TeroNavigationContainer(rootViewController: MirrorPage("root")))
        let detail = MirrorPage("detail")
        container.pushViewController(detail, animated: false)

        container.popViewController(animated: true)

        XCTAssertEqual(container.transitionState, .popping, "前置條件：轉場還在跑")
        XCTAssertTrue(detail.showsBackButton)
        waitUntil("pop 結算") { container.transitionState == .idle }
    }

    func test_aBarWrappedInACustomChromeViewIsUpdatedToo() {
        let root = MirrorPage("root", wrapsTheBar: true)
        let container = presented(TeroNavigationContainer(rootViewController: root))
        let detail = MirrorPage("detail", wrapsTheBar: true)

        container.pushViewController(detail, animated: false)

        XCTAssertFalse(root.showsBackButton)
        XCTAssertTrue(detail.showsBackButton)
    }
}
