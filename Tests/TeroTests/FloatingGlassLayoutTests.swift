import XCTest
@testable import Tero

/// 對應 ticket #27。玻璃材質屬於下一個切片，這裡驗的是版面與狀態。
final class FloatingGlassLayoutTests: TeroTabBarControllerTestCase {

    private func makeFloatingController(
        tabCount: Int = 4,
        withAction: Bool = false
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.compact.maximumVisibleItems = 6
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<tabCount).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        if withAction {
            let action = TeroTabActionItem(identifier: "compose", image: UIImage(systemName: "plus"))
            action.accessibilityIdentifier = "tab.compose"
            controller.setActionItem(action, animated: false)
        }
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    private var isFloatingAvailable: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    // MARK: 前提

    func test_floatingIsOnlyEffectiveOnSupportedOS() throws {
        let controller = makeFloatingController()
        if isFloatingAvailable {
            XCTAssertEqual(controller.tabBarStyle, .floatingGlass)
        } else {
            XCTAssertEqual(controller.tabBarStyle, .classic, "iOS 26 以下應降級")
        }
        XCTAssertEqual(controller.requestedStyle, .floatingGlass)
    }

    // MARK: 版面

    func test_barFloatsAboveTheBottomEdge() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()

        let appearance = controller.currentConfiguration().floatingGlassAppearance
        XCTAssertEqual(
            controller.view.bounds.maxY - controller.tabBar.frame.maxY,
            appearance.bottomInset,
            accuracy: 1.0,
            "`bottomInset` 從螢幕邊緣量起，不疊在安全區之上——疊加的話 Bar 永遠落在 "
            + "home indicator 帶子外面，而且設成 0 也追不到帶子裡面"
        )
    }

    func test_tabsCapsuleRespectsHorizontalInsetAndCornerRadius() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()
        let appearance = controller.currentConfiguration().floatingGlassAppearance

        // Tab 控制項落在膠囊內，膠囊本身左右內縮
        guard let first = tabBarControl(for: "t0", in: controller),
              let capsule = capsule(containing: first, in: controller) else {
            return XCTFail("找不到膠囊")
        }
        let capsuleFrameInBar = capsule.convert(capsule.bounds, to: controller.tabBar)
        XCTAssertEqual(capsuleFrameInBar.minX, appearance.horizontalInset, accuracy: 1.0)
        XCTAssertEqual(
            controller.tabBar.bounds.maxX - capsuleFrameInBar.maxX,
            appearance.horizontalInset,
            accuracy: 1.0
        )
        XCTAssertEqual(capsule.layer.cornerRadius, appearance.cornerRadius, accuracy: 0.5)
    }

    func test_expandedHeightComesFromAppearance() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()
        let appearance = controller.currentConfiguration().floatingGlassAppearance

        XCTAssertEqual(
            controller.tabBar.frame.height,
            max(appearance.expandedHeight, appearance.actionSize.height),
            accuracy: 1.0
        )
    }

    func test_actionSitsOutsideTheTabsCapsule() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController(withAction: true)

        guard let tab = tabBarControl(for: "t0", in: controller),
              let action = tabBarControl(for: "compose", in: controller),
              let tabsCapsule = capsule(containing: tab, in: controller) else {
            return XCTFail()
        }
        let tabsInBar = tabsCapsule.convert(tabsCapsule.bounds, to: controller.tabBar)
        let actionInBar = action.convert(action.bounds, to: controller.tabBar)

        XCTAssertFalse(tabsInBar.intersects(actionInBar.insetBy(dx: 1, dy: 1)), "Action 應在 Tabs 膠囊之外")
        XCTAssertGreaterThan(actionInBar.minX, tabsInBar.maxX - 1, "Action 應在 Tabs 右側")
    }

    func test_actionSpacingComesFromAppearance() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController(withAction: true)
        let appearance = controller.currentConfiguration().floatingGlassAppearance

        guard let tab = tabBarControl(for: "t0", in: controller),
              let action = tabBarControl(for: "compose", in: controller),
              let tabsCapsule = capsule(containing: tab, in: controller) else {
            return XCTFail()
        }
        let tabsInBar = tabsCapsule.convert(tabsCapsule.bounds, to: controller.tabBar)
        let actionInBar = action.convert(action.bounds, to: controller.tabBar)
        XCTAssertEqual(actionInBar.minX - tabsInBar.maxX, appearance.actionSpacing, accuracy: 1.5)
    }

    // MARK: 最小化是重新排版

    func test_minimizedRelayoutsRatherThanScaling() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()
        let appearance = controller.currentConfiguration().floatingGlassAppearance
        let expandedHeight = controller.tabBar.frame.height

        XCTAssertTrue(controller.setTabBarPresentationState(.minimized, animated: false))
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.tabBar.frame.height, appearance.minimizedHeight, accuracy: 1.0)
        XCTAssertLessThan(controller.tabBar.frame.height, expandedHeight)
        XCTAssertEqual(controller.tabBar.transform, .identity, "不得以 transform 縮放模擬")
        XCTAssertEqual(controller.tabBar.subviews.first?.transform, .identity)
    }

    func test_minimizedHidesTitlesAndShrinksContent() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()

        guard let control = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        let expandedLabels = control.subviews.compactMap { $0 as? UILabel }.filter { !$0.isHidden }.count
        XCTAssertGreaterThan(expandedLabels, 0)

        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        guard let minimized = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        let minimizedLabels = minimized.subviews.compactMap { $0 as? UILabel }.filter { !$0.isHidden }.count
        XCTAssertEqual(minimizedLabels, 0, "hidesTitlesWhenMinimized 為 true")
    }

    func test_minimizedUsesMinimizedCornerRadius() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()
        let appearance = controller.currentConfiguration().floatingGlassAppearance

        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        guard let tab = tabBarControl(for: "t0", in: controller),
              let capsule = capsule(containing: tab, in: controller) else { return XCTFail() }
        XCTAssertEqual(capsule.layer.cornerRadius, appearance.minimizedCornerRadius, accuracy: 0.5)
    }

    func test_minimizedShrinksTheAction() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController(withAction: true)
        guard let action = tabBarControl(for: "compose", in: controller),
              let expanded = capsule(containing: action, in: controller)?.frame else {
            return XCTFail()
        }

        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        guard let minimizedAction = tabBarControl(for: "compose", in: controller),
              let minimized = capsule(containing: minimizedAction, in: controller)?.frame else {
            return XCTFail()
        }
        XCTAssertLessThan(minimized.height, expanded.height)
        XCTAssertLessThan(minimized.width, expanded.width)
    }

    // MARK: 隱藏

    func test_hiddenMovesTheBarOffScreen() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()

        XCTAssertTrue(controller.setTabBarPresentationState(.hidden, animated: false))
        controller.view.layoutIfNeeded()

        XCTAssertGreaterThanOrEqual(
            controller.tabBar.frame.minY,
            controller.view.bounds.maxY - 1,
            "隱藏應把整條推到畫面之外"
        )
        XCTAssertEqual(controller.tabBar.alpha, 1, "不是靠改 alpha")
    }

    func test_hiddenClearsChildSafeAreaInset() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()

        controller.setTabBarPresentationState(.hidden, animated: false)

        for child in controller.children {
            XCTAssertEqual(child.additionalSafeAreaInsets.bottom, 0, accuracy: 0.5)
        }
    }

    func test_expandingAgainRestoresLayoutAndInsets() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()
        controller.setTabBarPresentationState(.hidden, animated: false)

        controller.setTabBarPresentationState(.expanded, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertLessThan(controller.tabBar.frame.minY, controller.view.bounds.maxY)
        for child in controller.children {
            XCTAssertGreaterThan(child.additionalSafeAreaInsets.bottom, 0)
        }
    }

    // MARK: 互動內容避開 Bar

    func test_interactiveContentAvoidsTheFloatingBar() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()
        let appearance = controller.currentConfiguration().floatingGlassAppearance

        guard let child = controller.selectedViewController else { return XCTFail() }
        child.view.layoutIfNeeded()

        // 子畫面的內容底邊要貼齊 Bar 的頂邊。Bar 有一段落在 home indicator 帶子裡面，
        // 那一段已經在視窗自己的 safe area 裡，不能重複加——否則會空出一段死空間。
        let reserved = max(appearance.expandedHeight, appearance.actionSize.height)
            + appearance.bottomInset
        let expected = max(reserved, controller.view.safeAreaInsets.bottom)
        XCTAssertEqual(child.view.safeAreaInsets.bottom, expected, accuracy: 1.0)

        XCTAssertEqual(child.view.safeAreaInsets.bottom,
                       controller.view.bounds.maxY - controller.tabBar.frame.minY,
                       accuracy: 1.0,
                       "換個說法：內容讓開的量就是 Bar 頂邊距螢幕底的距離")
    }

    // MARK: 狀態 API 的回傳值與事件

    func test_classicRejectsMinimized() {
        let controller = makeController()
        controller.setTabs([makeTab("a")], selectedIdentifier: nil, animated: false)
        present(controller)

        XCTAssertFalse(controller.setTabBarPresentationState(.minimized, animated: false))
        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_classicAcceptsExpandedAndHidden() {
        let controller = makeController()
        controller.setTabs([makeTab("a")], selectedIdentifier: nil, animated: false)
        present(controller)

        XCTAssertTrue(controller.setTabBarPresentationState(.hidden, animated: false))
        XCTAssertEqual(controller.tabBarPresentationState, .hidden)
        XCTAssertTrue(controller.setTabBarPresentationState(.expanded, animated: false))
        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
    }

    func test_floatingAcceptsAllThreeStates() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()

        XCTAssertTrue(controller.setTabBarPresentationState(.minimized, animated: false))
        XCTAssertTrue(controller.setTabBarPresentationState(.hidden, animated: false))
        XCTAssertTrue(controller.setTabBarPresentationState(.expanded, animated: false))
    }

    func test_stateChangeEmitsWillAndDidOnce() {
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
        let controller = makeController()
        controller.delegate = states
        controller.setTabs([makeTab("a")], selectedIdentifier: nil, animated: false)
        present(controller)

        controller.setTabBarPresentationState(.hidden, animated: false)

        XCTAssertEqual(states.events, ["will(2)", "did(2)"])
    }

    func test_settingTheSameStateEmitsNothing() {
        final class StateRecorder: NSObject, TeroTabBarControllerDelegate {
            var count = 0
            func teroTabBarController(_ c: TeroTabBarController, willChangeTabBarPresentationState s: TeroTabBarPresentationState) {
                count += 1
            }
        }
        let states = StateRecorder()
        let controller = makeController()
        controller.delegate = states
        controller.setTabs([makeTab("a")], selectedIdentifier: nil, animated: false)
        present(controller)

        XCTAssertTrue(controller.setTabBarPresentationState(.expanded, animated: false))

        XCTAssertEqual(states.count, 0, "狀態沒變就沒有事件")
    }

    func test_barMirrorsPresentationState() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeFloatingController()

        controller.setTabBarPresentationState(.minimized, animated: false)

        XCTAssertEqual(controller.tabBar.presentationState, .minimized)
        XCTAssertEqual(controller.tabBarPresentationState, .minimized)
    }

    // MARK: Provider 收到狀態

    func test_providerReceivesPresentationStateChange() throws {
        try XCTSkipUnless(isFloatingAvailable)
        final class Provider: NSObject, TeroTabContentProvider {
            var states: [TeroTabBarPresentationState] = []
            func makeContentView() -> UIView { UIView() }
            func updateContentView(
                _ contentView: UIView,
                selected: Bool,
                presentationState: TeroTabBarPresentationState,
                animated: Bool
            ) { states.append(presentationState) }
        }
        let provider = Provider()
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        let controller = makeController(configuration: configuration)
        let item = TeroTabItem(title: "a", image: nil, selectedImage: nil)
        item.accessibilityIdentifier = "tab.a"
        item.contentProvider = provider
        controller.setTabs(
            [TeroTab(identifier: "a", viewController: UIViewController(), item: item)],
            selectedIdentifier: nil,
            animated: false
        )
        present(controller)
        provider.states.removeAll()

        controller.setTabBarPresentationState(.minimized, animated: false)

        XCTAssertEqual(provider.states.last, .minimized)
    }
    // MARK: - 選取框在 minimized 的形狀

    private func floatingSnapshots(
        heightScale: CGFloat, itemCount: Int, hasAction: Bool
    ) -> (expanded: TeroFloatingGlassLayoutEngine.Layout, minimized: TeroFloatingGlassLayoutEngine.Layout) {
        var appearance = TeroFloatingGlassAppearance()
        appearance.minimizedHeight = appearance.expandedHeight * heightScale
        let insets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        let engine = TeroFloatingGlassLayoutEngine()
        func snapshot(_ state: TeroTabBarPresentationState) -> TeroFloatingGlassLayoutEngine.Layout {
            engine.layout(
                itemCount: itemCount, hasAction: hasAction, state: state,
                in: CGRect(x: 0, y: 0, width: 402, height: 56),
                appearance: appearance, selectionInsets: insets,
                selectionSizes: Array(repeating: nil, count: itemCount),
                layoutDirection: .leftToRight
            )
        }
        return (snapshot(.expanded), snapshot(.minimized))
    }

    /// 選取框是**等比縮放**，不是跟著格位縮。
    ///
    /// 這條規則現在是**全稱的**，沒有例外。原本膠囊的寬是 `itemCount × 48` 夾出來的、
    /// 與高度比無關，於是格位容不下等比縮放後的外框時只能夾住它——預設設定（3 格 ＋
    /// Action）就落在那一支。膠囊的寬改用同一個比例之後，每一種組合都塞得下。
    ///
    /// **0.8 附近兩種做法幾乎無法區分**（高度比 0.8、寬度比 0.774，只差 3.6%），
    /// 所以只用 0.8 寫的測試會過但東西是壞的。這裡必須涵蓋 0.9 與 1.0。
    func test_theSelectionKeepsItsOwnAspectRatioWhenMinimized() {
        for heightScale: CGFloat in [0.8, 0.9, 1.0] {
            for count in 3...6 {
                for hasAction in [false, true] {
                    let (expanded, minimized) = floatingSnapshots(
                        heightScale: heightScale, itemCount: count, hasAction: hasAction
                    )
                    let expandedSelection = expanded.selectionFrames[0]
                    let minimizedSelection = minimized.selectionFrames[0]
                    let minimizedSlot = minimized.itemFrames[0]
                    let label = "scale=\(heightScale) count=\(count) action=\(hasAction)"

                    XCTAssertLessThanOrEqual(
                        expandedSelection.width * heightScale, minimizedSlot.width + 1,
                        "\(label)：等比縮放後一定要塞得進格位，不該有被夾住的組合"
                    )

                    XCTAssertEqual(
                        minimizedSelection.width / minimizedSelection.height,
                        expandedSelection.width / expandedSelection.height,
                        accuracy: 0.05,
                        "\(label)：膠囊的形狀要保住"
                    )
                    XCTAssertEqual(
                        minimizedSelection.height, expandedSelection.height * heightScale,
                        accuracy: 1.5,
                        "\(label)：高度等比縮"
                    )
                    XCTAssertEqual(
                        minimizedSelection.width, expandedSelection.width * heightScale,
                        accuracy: 1.5,
                        "\(label)：寬度用同一個比例，不是格位的寬度比"
                    )
                }
            }
        }
    }

    /// 展開態必須與原本完全等價——這個修正不得讓展開的版面位移。
    func test_theExpandedSelectionIsUnchangedByTheScalingRule() {
        let (expanded, _) = floatingSnapshots(heightScale: 0.8, itemCount: 5, hasAction: true)
        let slot = expanded.itemFrames[0]

        XCTAssertEqual(expanded.selectionFrames[0],
                       slot.inset(by: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)),
                       "scale = 1 時應該就是原本的絕對內縮")
    }

    // MARK: - 只留選取格（issue #93）

    private func selectedOnlyLayout(itemCount: Int, selected: Int?, hasAction: Bool = true) -> TeroFloatingGlassLayoutEngine.Layout {
        var appearance = TeroFloatingGlassAppearance()
        appearance.minimizedLayout = .selectedOnly
        return TeroFloatingGlassLayoutEngine().layout(
            itemCount: itemCount, hasAction: hasAction, state: .minimized,
            in: CGRect(x: 0, y: 0, width: 402, height: 56),
            appearance: appearance, selectionInsets: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6),
            selectionSizes: Array(repeating: nil, count: itemCount), layoutDirection: .leftToRight,
            selectedIndex: selected
        )
    }

    func test_selectedOnlyMinimizedLayoutKeepsOnlyTheSelectedSlot() {
        let layout = selectedOnlyLayout(itemCount: 5, selected: 2)
        let appearance = TeroFloatingGlassAppearance()

        XCTAssertEqual(layout.itemFrames.filter { $0.width > 0 }.count, 1, "只有選取格有寬度")
        XCTAssertEqual(layout.itemFrames[2].width, layout.tabsCapsule.width, accuracy: 1, "選取格佔滿膠囊")
        XCTAssertEqual(layout.selectionFrames.filter { $0.width > 0 }.count, 1)
        XCTAssertGreaterThanOrEqual(layout.tabsCapsule.width, appearance.minimizedHeight - 1)
        XCTAssertLessThanOrEqual(layout.tabsCapsule.width, appearance.minimizedHeight * 1.6 + 1,
                                 "膠囊寬夾在高度的 1…1.6 倍：太寬看不出只剩一格")
    }

    func test_selectedOnlyIsNarrowerThanUniform() {
        let uniform = floatingSnapshots(heightScale: 36.0 / 56.0, itemCount: 5, hasAction: true).minimized
        let selectedOnly = selectedOnlyLayout(itemCount: 5, selected: 0)

        XCTAssertLessThan(selectedOnly.tabsCapsule.width, uniform.tabsCapsule.width)
    }

    func test_selectedOnlyWithoutASelectionFallsBackToTheFirstSlot() {
        let layout = selectedOnlyLayout(itemCount: 3, selected: nil)

        XCTAssertGreaterThan(layout.itemFrames[0].width, 0)
        XCTAssertEqual(layout.itemFrames[1].width, 0)
    }

    func test_uniformIsUnchangedByTheMinimizedLayoutOption() {
        let (_, minimized) = floatingSnapshots(heightScale: 0.8, itemCount: 4, hasAction: false)

        XCTAssertTrue(minimized.itemFrames.allSatisfy { $0.width > 0 }, "預設 .uniform 所有格都留著")
    }

    func test_tappingTheSelectedOnlyPillExpandsWithoutReselecting() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.floatingGlassAppearance.minimizedLayout = .selectedOnly
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<4).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        XCTAssertTrue(controller.setTabBarPresentationState(.minimized, animated: false))
        controller.view.layoutIfNeeded()

        XCTAssertTrue(try XCTUnwrap(tabBarControl(for: "t1", in: controller)).isHidden, "非選取格摸不到")
        XCTAssertFalse(try XCTUnwrap(tabBarControl(for: "t0", in: controller)).isHidden)

        tapTabBarItem("t0", in: controller)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded, "點膠囊是展開")
        XCTAssertEqual(controller.selectedTab?.identifier, "t0", "選取不變")
        XCTAssertTrue(recorder.didReselectCalls.isEmpty, "不是重選")
        // 展開有動畫：非選取格隨進度淡回來，等它到，不猜幾秒。
        let other = try XCTUnwrap(tabBarControl(for: "t1", in: controller))
        waitUntil("展開後全部回來") { !other.isHidden && other.alpha > 0.99 }
    }

    /// 非對稱內縮不得被縮放硬拉成置中。
    func test_asymmetricInsetsKeepTheirProportionWhenMinimized() {
        var appearance = TeroFloatingGlassAppearance()
        appearance.minimizedHeight = appearance.expandedHeight * 0.9
        let insets = UIEdgeInsets(top: 4, left: 18, bottom: 4, right: 2)
        let engine = TeroFloatingGlassLayoutEngine()
        let minimized = engine.layout(
            itemCount: 5, hasAction: true, state: .minimized,
            in: CGRect(x: 0, y: 0, width: 402, height: 56),
            appearance: appearance, selectionInsets: insets,
            selectionSizes: Array(repeating: nil, count: 5), layoutDirection: .leftToRight
        )
        let slot = minimized.itemFrames[0]
        let selection = minimized.selectionFrames[0]
        let leading = selection.minX - slot.minX
        let trailing = slot.maxX - selection.maxX

        XCTAssertEqual(leading / trailing, insets.left / insets.right, accuracy: 0.05,
                       "左右剩餘量要按原比例分配，不是對半")
    }

}
