import XCTest
@testable import Tero

/// 對應 ticket #41 的插補運算。純函式，直接驗曲線而不必去螢幕上取樣。
final class SelectionInterpolationTests: XCTestCase {

    private let light = UITraitCollection(userInterfaceStyle: .light)

    func test_valueInterpolatesLinearly() {
        XCTAssertEqual(TeroTabSelectionInterpolation.value(from: 10, to: 20, progress: 0), 10)
        XCTAssertEqual(TeroTabSelectionInterpolation.value(from: 10, to: 20, progress: 0.5), 15)
        XCTAssertEqual(TeroTabSelectionInterpolation.value(from: 10, to: 20, progress: 1), 20)
    }

    func test_valueClampsOutOfRangeProgress() {
        XCTAssertEqual(TeroTabSelectionInterpolation.value(from: 10, to: 20, progress: -1), 10)
        XCTAssertEqual(TeroTabSelectionInterpolation.value(from: 10, to: 20, progress: 3), 20)
    }

    func test_colourAtTheEndsIsTheEndColour() {
        let start = TeroTabSelectionInterpolation.color(from: .black, to: .white, progress: 0, traits: light)
        let end = TeroTabSelectionInterpolation.color(from: .black, to: .white, progress: 1, traits: light)

        XCTAssertEqual(components(start).red, 0, accuracy: 0.001)
        XCTAssertEqual(components(end).red, 1, accuracy: 0.001)
    }

    func test_colourMidpointIsHalfway() {
        let mid = TeroTabSelectionInterpolation.color(from: .black, to: .white, progress: 0.5, traits: light)

        XCTAssertEqual(components(mid).red, 0.5, accuracy: 0.001)
        XCTAssertEqual(components(mid).alpha, 1, accuracy: 0.001)
    }

    func test_colourInterpolatesAlphaToo() {
        let transparent = UIColor.white.withAlphaComponent(0)
        let mid = TeroTabSelectionInterpolation.color(from: transparent, to: .white, progress: 0.25, traits: light)

        XCTAssertEqual(components(mid).alpha, 0.25, accuracy: 0.001)
    }

    func test_dynamicColoursAreResolvedBeforeInterpolating() {
        // 不先解析的話，動態顏色取不到分量，整段會退化成其中一端。
        let dynamic = UIColor { $0.userInterfaceStyle == .dark ? .white : .black }
        let dark = UITraitCollection(userInterfaceStyle: .dark)

        let inLight = TeroTabSelectionInterpolation.color(from: dynamic, to: .red, progress: 0, traits: light)
        let inDark = TeroTabSelectionInterpolation.color(from: dynamic, to: .red, progress: 0, traits: dark)

        XCTAssertEqual(components(inLight).red, 0, accuracy: 0.001)
        XCTAssertEqual(components(inDark).red, 1, accuracy: 0.001)
    }

    func test_scaleSettlesAtOneOnBothEnds() {
        for bump in [-0.08, 0, 0.09] as [CGFloat] {
            XCTAssertEqual(
                TeroTabSelectionInterpolation.scale(transition: 1, rest: 0.92, bump: bump),
                1, accuracy: 0.0001
            )
        }
    }

    func test_incomingScaleStartsSmallAndOvershoots() {
        let start = TeroTabSelectionInterpolation.scale(transition: 0, rest: 0.92, bump: 0.09)
        let middle = TeroTabSelectionInterpolation.scale(transition: 0.5, rest: 0.92, bump: 0.09)
        let end = TeroTabSelectionInterpolation.scale(transition: 1, rest: 0.92, bump: 0.09)

        XCTAssertEqual(start, 0.92, accuracy: 0.0001, "由小開始")
        XCTAssertGreaterThan(middle, 1, "中途略微過衝")
        XCTAssertEqual(end, 1, accuracy: 0.0001, "收在原尺寸")
    }

    func test_outgoingScaleDipsAndReturns() {
        let start = TeroTabSelectionInterpolation.scale(transition: 0, rest: 1, bump: -0.08)
        let middle = TeroTabSelectionInterpolation.scale(transition: 0.5, rest: 1, bump: -0.08)
        let end = TeroTabSelectionInterpolation.scale(transition: 1, rest: 1, bump: -0.08)

        XCTAssertEqual(start, 1, accuracy: 0.0001)
        XCTAssertEqual(middle, 0.92, accuracy: 0.0001, "原地略縮")
        XCTAssertEqual(end, 1, accuracy: 0.0001, "回到原尺寸")
    }

    func test_zeroBumpMeansNoOvershoot() {
        for t in stride(from: CGFloat(0), through: 1, by: 0.1) {
            let scale = TeroTabSelectionInterpolation.scale(transition: t, rest: 1, bump: 0)
            XCTAssertEqual(scale, 1, accuracy: 0.0001)
        }
    }

    private func components(_ color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}


/// 對應 ticket #41 的連續 Icon 轉場，透過 controller 的公開 API 驅動。
final class SelectionProgressTests: TeroTabBarControllerTestCase {

    private func makeIconTab(_ identifier: String, distinctSelectedImage: Bool) -> TeroTab {
        let normal = UIImage(systemName: "circle")!
        let item = TeroTabItem(
            title: identifier,
            image: normal,
            selectedImage: distinctSelectedImage ? UIImage(systemName: "circle.fill")! : nil
        )
        item.accessibilityIdentifier = "tab.\(identifier)"
        return TeroTab(
            identifier: identifier,
            viewController: LifecycleSpyViewController(name: identifier, log: log),
            item: item
        )
    }

    private func makeIconController(
        distinctSelectedImage: Bool = false,
        tabCount: Int = 3,
        mutate: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.itemAppearance.normalTintColor = .black
        configuration.itemAppearance.selectedTintColor = .white
        mutate(configuration)
        let controller = makeController(configuration: configuration)
        controller.setTabs(
            (0..<tabCount).map { makeIconTab("t\($0)", distinctSelectedImage: distinctSelectedImage) },
            selectedIdentifier: "t0",
            animated: false
        )
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func itemView(_ identifier: String, in controller: TeroTabBarController) -> TeroTabItemView? {
        tabBarControl(for: identifier, in: controller) as? TeroTabItemView
    }

    private func caption(_ identifier: String, in controller: TeroTabBarController) -> UILabel? {
        tabBarControl(for: identifier, in: controller)?.subviews.compactMap { $0 as? UILabel }.first
    }

    private func icons(_ identifier: String, in controller: TeroTabBarController) -> [UIImageView] {
        tabBarControl(for: identifier, in: controller)?.subviews.compactMap { $0 as? UIImageView } ?? []
    }

    // MARK: 靜止狀態

    func test_restingProgressIsExactlyZeroOrOne() {
        let controller = makeIconController()

        XCTAssertEqual(itemView("t0", in: controller)?.selectionProgress, 1)
        XCTAssertEqual(itemView("t1", in: controller)?.selectionProgress, 0)
        XCTAssertEqual(itemView("t2", in: controller)?.selectionProgress, 0)
    }

    func test_restingScaleIsIdentity() {
        let controller = makeIconController()

        for identifier in ["t0", "t1", "t2"] {
            for icon in icons(identifier, in: controller) {
                XCTAssertEqual(icon.transform, .identity, "\(identifier) 靜止時不應帶著縮放")
            }
        }
    }

    func test_selectedCaptionUsesTheSelectedTint() {
        let controller = makeIconController()

        assertSameColor(caption("t0", in: controller)?.textColor, .white)
        assertSameColor(caption("t1", in: controller)?.textColor, .black)
    }

    func test_progressFollowsAnUnanimatedSelection() {
        let controller = makeIconController()

        controller.selectTab(withIdentifier: "t2", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(itemView("t0", in: controller)?.selectionProgress, 0)
        XCTAssertEqual(itemView("t2", in: controller)?.selectionProgress, 1)
        assertSameColor(caption("t2", in: controller)?.textColor, .white)
    }

    // MARK: 轉場途中

    /// 讓轉場停在中途，才驗得到「連續」而不只是「到站後正確」。
    private func runPartway(_ controller: TeroTabBarController, response: TimeInterval = 1.2) {
        let update = controller.currentConfiguration()
        update.motion.selectionResponse = response
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        controller.selectTab(withIdentifier: "t2", animated: true)
        // 這個 suite 的每個測試都要在轉場「進行中」量值。等固定秒數的話，
        // 字型與版面的一次性初始化會在較慢的機器上吃掉整個預算，量到的是起點。
        waitUntil("轉場推進到中間") {
            guard let progress = itemView("t2", in: controller)?.selectionProgress else { return false }
            return progress > 0 && progress < 1
        }
    }

    func test_progressIsContinuousDuringATransition() {
        let controller = makeIconController()

        runPartway(controller)

        guard let leaving = itemView("t0", in: controller)?.selectionProgress,
              let arriving = itemView("t2", in: controller)?.selectionProgress else {
            return XCTFail("找不到項目")
        }
        XCTAssertGreaterThan(arriving, 0, "新選取已經開始往上走")
        XCTAssertLessThan(arriving, 1, "但還沒到")
        XCTAssertEqual(leaving, 1 - arriving, accuracy: 0.001, "舊選取同步往下走")
    }

    func test_captionColourIsBetweenTheTwoTintsDuringATransition() {
        let controller = makeIconController()

        runPartway(controller)

        guard let colour = caption("t2", in: controller)?.textColor else { return XCTFail() }
        var white: CGFloat = 0, alpha: CGFloat = 0
        XCTAssertTrue(colour.getWhite(&white, alpha: &alpha))
        XCTAssertGreaterThan(white, 0, "已經離開 normalTintColor")
        XCTAssertLessThan(white, 1, "還沒到 selectedTintColor")
    }

    func test_iconIsScaledDuringATransition() {
        let controller = makeIconController()

        runPartway(controller)

        guard let icon = icons("t2", in: controller).first else { return XCTFail() }
        XCTAssertNotEqual(icon.transform, .identity, "接手選取的 Icon 在轉場中帶著縮放")
    }

    func test_interruptionContinuesFromTheCurrentProgress() {
        let controller = makeIconController(tabCount: 4)

        runPartway(controller)
        guard let midway = itemView("t2", in: controller)?.selectionProgress else { return XCTFail() }
        XCTAssertGreaterThan(midway, 0)

        controller.selectTab(withIdentifier: "t3", animated: true)

        // 被中斷的那一格從當下的值往 0 走，不會先跳回 1 或 0。
        guard let afterInterrupt = itemView("t2", in: controller)?.selectionProgress else { return XCTFail() }
        XCTAssertEqual(afterInterrupt, midway, accuracy: 0.05, "接手的那一段從畫面上的狀態繼續")
    }

    func test_transitionEventuallySettlesAtExactlyZeroAndOne() {
        let controller = makeIconController {
            $0.motion.selectionResponse = 0.08
        }

        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        XCTAssertEqual(itemView("t0", in: controller)?.selectionProgress, 0)
        XCTAssertEqual(itemView("t2", in: controller)?.selectionProgress, 1)
        for icon in icons("t2", in: controller) {
            XCTAssertEqual(icon.transform, .identity, "落定之後回到原尺寸")
        }
    }

    // MARK: 兩張圖不同時的交棒

    func test_distinctSelectedImageUsesTwoLayers() {
        let controller = makeIconController(distinctSelectedImage: true)

        XCTAssertEqual(icons("t0", in: controller).count, 2, "正常與選取各一層才能交叉淡入")
    }

    func test_selectedItemShowsTheSelectedLayer() {
        let controller = makeIconController(distinctSelectedImage: true)

        let selected = icons("t0", in: controller)
        let unselected = icons("t1", in: controller)
        XCTAssertEqual(selected[0].alpha, 0, accuracy: 0.001)
        XCTAssertEqual(selected[1].alpha, 1, accuracy: 0.001)
        XCTAssertEqual(unselected[0].alpha, 1, accuracy: 0.001)
        XCTAssertEqual(unselected[1].alpha, 0, accuracy: 0.001)
    }

    func test_layersCrossfadeDuringATransition() {
        let controller = makeIconController(distinctSelectedImage: true)

        runPartway(controller)

        let arriving = icons("t2", in: controller)
        XCTAssertEqual(arriving[0].alpha + arriving[1].alpha, 1, accuracy: 0.001, "兩層的不透明度互補")
        XCTAssertGreaterThan(arriving[1].alpha, 0)
        XCTAssertLessThan(arriving[1].alpha, 1)
    }

    func test_sharedImageKeepsASingleVisibleLayer() {
        let controller = makeIconController(distinctSelectedImage: false)

        let selected = icons("t0", in: controller)
        XCTAssertEqual(selected[0].alpha, 1, accuracy: 0.001)
        XCTAssertTrue(selected[1].isHidden, "沒有第二張圖就不需要第二層")
    }

    // MARK: 標題字重

    func test_titleFontSwitchesAtTheMidpoint() {
        let controller = makeIconController {
            $0.itemAppearance.titleFont = .systemFont(ofSize: 10, weight: .regular)
            $0.itemAppearance.selectedTitleFont = .systemFont(ofSize: 10, weight: .bold)
        }

        XCTAssertEqual(caption("t0", in: controller)?.font.fontDescriptor.symbolicTraits.contains(.traitBold), true)
        XCTAssertEqual(caption("t1", in: controller)?.font.fontDescriptor.symbolicTraits.contains(.traitBold), false)
    }

    func test_titleHeightDoesNotJumpWhenTheFontChanges() {
        let controller = makeIconController {
            $0.itemAppearance.titleFont = .systemFont(ofSize: 10, weight: .regular)
            $0.itemAppearance.selectedTitleFont = .systemFont(ofSize: 20, weight: .bold)
        }

        let selectedHeight = caption("t0", in: controller)?.frame.height
        let unselectedHeight = caption("t1", in: controller)?.frame.height
        XCTAssertEqual(selectedHeight, unselectedHeight, "版面高度一律以 titleFont 為準，換字重不改變佔位")
    }
}
