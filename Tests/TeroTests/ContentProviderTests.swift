import XCTest
@testable import Tero

/// 對應 ticket #25。Provider 是公開 protocol，因此測試用的 provider 不需要任何內部存取。
final class ContentProviderTests: TeroTabBarControllerTestCase {

    /// 記錄呼叫次數與收到的狀態的假 provider。
    final class SpyProvider: NSObject, TeroTabContentProvider {
        private(set) var madeViews: [UIView] = []
        private(set) var updates: [(view: UIView, selected: Bool, state: TeroTabBarPresentationState, animated: Bool)] = []
        var makeCount: Int { madeViews.count }

        func makeContentView() -> UIView {
            let view = UIView()
            view.tag = madeViews.count + 1
            madeViews.append(view)
            return view
        }

        func updateContentView(
            _ contentView: UIView,
            selected: Bool,
            presentationState: TeroTabBarPresentationState,
            animated: Bool
        ) {
            updates.append((contentView, selected, presentationState, animated))
        }

        func reset() { updates.removeAll() }
    }

    private func makeTab(_ identifier: String, provider: TeroTabContentProvider?) -> TeroTab {
        let item = TeroTabItem(title: identifier, image: UIImage(systemName: "circle"), selectedImage: nil)
        item.accessibilityIdentifier = "tab.\(identifier)"
        item.contentProvider = provider
        return TeroTab(identifier: identifier, viewController: UIViewController(), item: item)
    }

    // MARK: 所有權

    func test_itemStronglyHoldsItsProvider() {
        let item = TeroTabItem(title: nil, image: nil, selectedImage: nil)

        // 最自然的寫法：直接指派一個新建立的 provider，不另外保留參考
        item.contentProvider = SpyProvider()

        XCTAssertNotNil(item.contentProvider, "Item 必須強持有 Provider，否則會是無聲失敗")
    }

    // MARK: 建立時機與數量

    func test_contentViewIsNotCreatedUntilTheTabNeedsToShow() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)

        XCTAssertEqual(provider.makeCount, 0, "setTabs 當下還不需要顯示")

        present(controller)

        XCTAssertEqual(provider.makeCount, 1)
    }

    func test_sharedProviderGivesEachItemItsOwnView() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs(
            [makeTab("a", provider: provider), makeTab("b", provider: provider)],
            selectedIdentifier: "a",
            animated: false
        )
        present(controller)

        XCTAssertEqual(provider.makeCount, 2)
        XCTAssertFalse(provider.madeViews[0] === provider.madeViews[1])
    }

    func test_repeatedLayoutDoesNotRecreateTheView() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)
        present(controller)

        controller.view.layoutIfNeeded()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(provider.makeCount, 1)
    }

    // MARK: reload 的重建規則

    func test_reloadTabWithUnchangedProviderDoesNotRebuildTheView() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)
        present(controller)
        provider.reset()

        controller.tabs[0].item.title = "改過的標題"
        controller.reloadTab(withIdentifier: "a", animated: false)

        XCTAssertEqual(provider.makeCount, 1, "只有 provider 參考變更才重建")
        XCTAssertFalse(provider.updates.isEmpty, "但應該收到 update")
    }

    func test_changingProviderReferenceRebuildsTheView() {
        let first = SpyProvider()
        let second = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: first)], selectedIdentifier: nil, animated: false)
        present(controller)

        controller.tabs[0].item.contentProvider = second
        controller.reloadTab(withIdentifier: "a", animated: false)

        XCTAssertEqual(first.makeCount, 1)
        XCTAssertEqual(second.makeCount, 1)
    }

    func test_settingBadgeDoesNotRebuildTheContentView() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)
        present(controller)

        controller.setBadge(.value("3"), forTabWithIdentifier: "a", animated: false)

        XCTAssertEqual(provider.makeCount, 1, "順手更新 badge 不該打斷播放中的動畫")
    }

    // MARK: 狀態傳遞

    func test_providerReceivesSelectionState() {
        let providerA = SpyProvider()
        let providerB = SpyProvider()
        let controller = makeController()
        controller.setTabs(
            [makeTab("a", provider: providerA), makeTab("b", provider: providerB)],
            selectedIdentifier: "a",
            animated: false
        )
        present(controller)
        providerA.reset()
        providerB.reset()

        controller.selectTab(withIdentifier: "b", animated: false)

        XCTAssertEqual(providerA.updates.last?.selected, false)
        XCTAssertEqual(providerB.updates.last?.selected, true)
    }

    func test_providerReceivesPresentationState() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)
        present(controller)

        XCTAssertEqual(provider.updates.last?.state, .expanded)
    }

    func test_providerReceivesAnimatedFlag() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs(
            [makeTab("a", provider: provider), makeTab("b", provider: provider)],
            selectedIdentifier: "a",
            animated: false
        )
        present(controller)
        provider.reset()

        controller.selectTab(withIdentifier: "b", animated: true)
        XCTAssertEqual(provider.updates.last?.animated, true)

        provider.reset()
        controller.selectTab(withIdentifier: "a", animated: false)
        XCTAssertEqual(provider.updates.last?.animated, false)
    }

    // MARK: Overflow 與移除

    func test_contentViewSurvivesGoingIntoOverflow() {
        let provider = SpyProvider()
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.compact.maximumVisibleItems = 2
        configuration.regular.maximumVisibleItems = 2
        let controller = makeController(configuration: configuration)
        controller.setTabs(
            [makeTab("a", provider: provider), makeTab("b", provider: provider), makeTab("c", provider: provider)],
            selectedIdentifier: "a",
            animated: false
        )
        present(controller)
        let createdWhileVisible = provider.makeCount

        // a 仍可見；b、c 進 Overflow。回到可見時不該重新載入。
        controller.selectTab(withIdentifier: "a", animated: false)
        controller.reloadAllTabs(animated: false)

        XCTAssertEqual(provider.makeCount, createdWhileVisible, "Overflow 期間應保留自訂內容")
    }

    func test_contentViewIsDestroyedWhenTabIsRemoved() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs(
            [makeTab("a", provider: provider), makeTab("b", provider: provider)],
            selectedIdentifier: "a",
            animated: false
        )
        present(controller)
        XCTAssertEqual(provider.makeCount, 2)

        // 移除 b，再重新加入：因為快取已被清掉，會重新建立
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)
        controller.setTabs(
            [makeTab("a", provider: provider), makeTab("b", provider: provider)],
            selectedIdentifier: "a",
            animated: false
        )

        XCTAssertGreaterThan(provider.makeCount, 2, "被移除的 Tab 其自訂內容應已銷毀")
    }

    func test_removingProviderFallsBackToImage() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)
        present(controller)

        controller.tabs[0].item.contentProvider = nil
        controller.reloadTab(withIdentifier: "a", animated: false)
        controller.view.layoutIfNeeded()

        guard let control = tabBarControl(for: "a", in: controller) else { return XCTFail() }
        let visibleIcons = control.subviews.compactMap { $0 as? UIImageView }.filter { !$0.isHidden }
        XCTAssertFalse(visibleIcons.isEmpty, "移除 provider 後應退回 image")
    }

    // MARK: 與 Badge 共存

    func test_badgeStaysInsideBoundsWithCustomContent() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)
        present(controller)
        controller.setBadge(.value("99+"), forTabWithIdentifier: "a", animated: false)
        controller.view.layoutIfNeeded()

        guard let control = tabBarControl(for: "a", in: controller) else { return XCTFail() }
        for subview in control.subviews where !subview.isHidden {
            XCTAssertTrue(
                control.bounds.insetBy(dx: -0.5, dy: -0.5).contains(subview.frame),
                "\(type(of: subview)) 溢出：\(subview.frame) vs \(control.bounds)"
            )
        }
    }

    func test_customContentIsPlacedWhereTheIconWouldBe() {
        let provider = SpyProvider()
        let controller = makeController()
        controller.setTabs([makeTab("a", provider: provider)], selectedIdentifier: nil, animated: false)
        present(controller)
        controller.view.layoutIfNeeded()

        let contentSize = controller.currentConfiguration().itemAppearance.contentSize
        guard let hosted = provider.madeViews.first else { return XCTFail("provider 應已建立 view") }
        XCTAssertEqual(hosted.bounds.width, contentSize.width, accuracy: 0.5)
        XCTAssertEqual(hosted.bounds.height, contentSize.height, accuracy: 0.5)
        XCTAssertFalse(hosted.isUserInteractionEnabled, "點擊仍應由 Item 控制項處理")
    }
}
