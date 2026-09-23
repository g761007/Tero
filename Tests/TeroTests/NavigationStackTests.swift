import XCTest
@testable import Tero

/// 對應計畫書 §45：離開再回到某個 Tab，其 push 堆疊必須維持原樣。
final class NavigationStackTests: TeroTabBarControllerTestCase {

    func test_navigationStackIsPreservedAcrossTabSwitches() {
        let controller = makeController()

        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        let homeTab = TeroTab(
            identifier: "home",
            viewController: navigation,
            item: TeroTabItem(title: "Home", image: nil, selectedImage: nil)
        )
        let profileTab = makeTab("profile")

        controller.setTabs([homeTab, profileTab], selectedIdentifier: "home", animated: false)
        present(controller)

        let pushed = UIViewController()
        navigation.pushViewController(pushed, animated: false)
        XCTAssertEqual(navigation.viewControllers.count, 2)

        controller.selectTab(withIdentifier: "profile", animated: false)
        controller.selectTab(withIdentifier: "home", animated: false)

        XCTAssertEqual(navigation.viewControllers.count, 2, "navigation stack 不應被重建")
        XCTAssertIdentical(navigation.topViewController, pushed)
        XCTAssertIdentical(navigation.viewControllers.first, root)
    }

    func test_detachedTabKeepsItsNavigationStack() {
        let controller = makeController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        let homeTab = TeroTab(
            identifier: "home",
            viewController: navigation,
            item: TeroTabItem(title: "Home", image: nil, selectedImage: nil)
        )
        controller.setTabs([homeTab, makeTab("profile")], selectedIdentifier: "home", animated: false)
        present(controller)
        navigation.pushViewController(UIViewController(), animated: false)

        // 從 Tab 列表移除 home
        controller.setTabs([makeTab("profile")], selectedIdentifier: nil, animated: false)

        XCTAssertNil(navigation.parent, "已移除的 Tab 應脫離 containment")
        XCTAssertEqual(navigation.viewControllers.count, 2, "但它自己的堆疊不該被清掉")
    }
    // MARK: - popToViewController

    func test_popToViewController_removesEverythingAboveItAndReturnsThem() {
        let root = UIViewController(), middle = UIViewController(), top = UIViewController()
        let container = TeroNavigationContainer(rootViewController: root)
        container.setViewControllers([root, middle, top], animated: false)

        let removed = container.popToViewController(middle, animated: false)

        XCTAssertEqual(container.viewControllers, [root, middle])
        XCTAssertEqual(removed, [top], "回傳被移除的那些，由底到頂")
        XCTAssertNil(top.parent, "移除的要離開 containment")
    }

    func test_popToViewController_onTheTopChangesNothing() {
        let root = UIViewController(), top = UIViewController()
        let container = TeroNavigationContainer(rootViewController: root)
        container.setViewControllers([root, top], animated: false)

        let removed = container.popToViewController(top, animated: false)

        XCTAssertEqual(container.viewControllers, [root, top])
        XCTAssertEqual(removed, [])
    }

    func test_popToViewController_withAStrangerReportsAndChangesNothing() {
        let root = UIViewController(), top = UIViewController()
        let container = TeroNavigationContainer(rootViewController: root)
        container.setViewControllers([root, top], animated: false)
        var reported: [String] = []
        let previous = TeroDiagnostics.reportHandler
        TeroDiagnostics.reportHandler = { message, _, _ in reported.append(message) }
        defer { TeroDiagnostics.reportHandler = previous }

        let removed = container.popToViewController(UIViewController(), animated: false)

        XCTAssertEqual(container.viewControllers, [root, top], "stack 不動")
        XCTAssertEqual(removed, [])
        XCTAssertEqual(reported.count, 1, "安靜地什麼都不做會讓呼叫端的錯留到跑進那條路徑才爆")
    }

    func test_popToViewController_acrossSeveralEntriesRemovesThemAllInOrder() {
        let pages = (0..<5).map { _ in UIViewController() }
        let container = TeroNavigationContainer(rootViewController: pages[0])
        container.setViewControllers(pages, animated: false)

        let removed = container.popToViewController(pages[1], animated: false)

        XCTAssertEqual(container.viewControllers, Array(pages.prefix(2)))
        XCTAssertEqual(removed, Array(pages.suffix(3)), "由底到頂")
    }

}
