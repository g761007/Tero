import XCTest
import UIKit
@testable import Tero

/// 宣告自己要暗色 Tab Bar 的頁面（Instagram 的 Reels）。
private final class DarkBarPage: UIViewController, TeroTabBarAppearanceProviding {
    var preferredTeroTabBarUserInterfaceStyle: UIUserInterfaceStyle { .dark }
}

/// issue #95：頁面可宣告 Tab Bar 的介面風格。
final class TabBarAppearanceProvidingTests: TeroTabBarControllerTestCase {

    private func tab(_ identifier: String, _ viewController: UIViewController) -> TeroTab {
        TeroTab(identifier: identifier, viewController: viewController,
                item: TeroTabItem(title: identifier, image: nil, selectedImage: nil))
    }

    func test_aPageThatDeclaresDark_turnsTheBarDark() {
        let controller = makeController()
        controller.setTabs([tab("feed", UIViewController()), tab("reels", DarkBarPage())],
                           selectedIdentifier: "feed", animated: false)
        present(controller)
        XCTAssertEqual(controller.tabBar.overrideUserInterfaceStyle, .unspecified, "前提：feed 沒表態")

        controller.selectTab(withIdentifier: "reels", animated: false)

        XCTAssertEqual(controller.tabBar.overrideUserInterfaceStyle, .dark)
    }

    func test_switchingBackToAPageWithoutADeclaration_followsTheSystemAgain() {
        let controller = makeController()
        controller.setTabs([tab("feed", UIViewController()), tab("reels", DarkBarPage())],
                           selectedIdentifier: "reels", animated: false)
        present(controller)
        XCTAssertEqual(controller.tabBar.overrideUserInterfaceStyle, .dark, "前提")

        controller.selectTab(withIdentifier: "feed", animated: false)

        XCTAssertEqual(controller.tabBar.overrideUserInterfaceStyle, .unspecified,
                       "沒有宣告就是跟隨系統，不是留著上一頁的")
    }

    func test_theDeclarationIsResolvedThroughANavigationContainer() {
        let container = TeroNavigationContainer(rootViewController: UIViewController())
        let controller = makeController()
        controller.setTabs([tab("feed", container)], selectedIdentifier: "feed", animated: false)
        present(controller)

        container.pushViewController(DarkBarPage(), animated: false)
        XCTAssertEqual(controller.tabBar.overrideUserInterfaceStyle, .dark, "push 之後跟著 top 走")

        container.popViewController(animated: false)
        XCTAssertEqual(controller.tabBar.overrideUserInterfaceStyle, .unspecified, "pop 回來恢復")
    }

    func test_theContainerForwardsTheTopPagesDeclaration() {
        let container = TeroNavigationContainer(rootViewController: UIViewController())
        XCTAssertEqual(container.preferredTeroTabBarUserInterfaceStyle, .unspecified, "root 沒表態")

        container.pushViewController(DarkBarPage(), animated: false)

        XCTAssertEqual(container.preferredTeroTabBarUserInterfaceStyle, .dark, "原封轉發 top 的宣告")
    }
}
