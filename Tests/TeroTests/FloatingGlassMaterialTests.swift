import XCTest
@testable import Tero

/// 對應 issue #13：FloatingGlass 的模糊材質、內緣亮邊、外陰影與項目區內距。
///
/// 四組設定各自開關，預設值維持 2.1 的外觀。
final class FloatingGlassMaterialTests: TeroTabBarControllerTestCase {

    private func makeFloatingController(
        tabCount: Int = 4,
        withAction: Bool = true,
        configure: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.compact.maximumVisibleItems = 6
        configuration.motion.minimizeDuration = 0.25
        configure(configuration)
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

    private func advance(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    private func tabsCapsule(in controller: TeroTabBarController) throws -> UIVisualEffectView {
        let control = try XCTUnwrap(tabBarControl(for: "t0", in: controller))
        return try XCTUnwrap(capsule(containing: control, in: controller))
    }

    private func actionCapsule(in controller: TeroTabBarController) throws -> UIVisualEffectView {
        let control = try XCTUnwrap(tabBarControl(for: "compose", in: controller))
        return try XCTUnwrap(capsule(containing: control, in: controller))
    }

    /// 畫在畫面上的亮邊；沒有或藏起來都回 nil。
    private func rim(in capsule: UIVisualEffectView) -> TeroCapsuleRimView? {
        capsule.contentView.subviews
            .compactMap { $0 as? TeroCapsuleRimView }
            .first { !$0.isHidden && $0.alpha > 0 }
    }

    /// 畫在畫面上的陰影；沒有或藏起來都回 nil。
    private func shadow(in controller: TeroTabBarController) -> TeroCapsuleShadowView? {
        controller.tabBar.subviews
            .compactMap { $0 as? TeroCapsuleShadowView }
            .first { !$0.isHidden && $0.layer.shadowOpacity > 0 }
    }

    private var rimColors: [UIColor] {
        [UIColor.white.withAlphaComponent(0.7), UIColor.white.withAlphaComponent(0.1), UIColor.white.withAlphaComponent(0.45)]
    }

    private func configureRim(_ configuration: TeroTabBarConfiguration) {
        configuration.floatingGlassAppearance.rimWidth = 1
        configuration.floatingGlassAppearance.rimColors = rimColors
        configuration.floatingGlassAppearance.rimStartPoint = CGPoint(x: 0, y: 0)
        configuration.floatingGlassAppearance.rimEndPoint = CGPoint(x: 1, y: 1)
    }

    private func configureShadow(_ configuration: TeroTabBarConfiguration) {
        configuration.floatingGlassAppearance.shadowOpacity = 0.2
        configuration.floatingGlassAppearance.shadowColor = .systemIndigo
        configuration.floatingGlassAppearance.shadowOffset = CGSize(width: 0, height: 4)
        configuration.floatingGlassAppearance.shadowRadius = 10
    }

    /// 圓弧組成的 path，外框會有 1e-14 等級的浮點誤差。
    private func assertEqualRects(_ actual: CGRect, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }

    /// 亮邊要畫在 `contentView` 裡所有東西之上，只佔邊緣那一圈。
    private func assertDrawsAboveItsSiblings(_ rim: UIView, file: StaticString = #filePath, line: UInt = #line) {
        guard let siblings = rim.superview?.subviews else { return XCTFail("亮邊不在畫面上", file: file, line: line) }
        let rimIndex = siblings.firstIndex(of: rim) ?? -1
        for (index, sibling) in siblings.enumerated() where sibling !== rim {
            let above = rim.layer.zPosition > sibling.layer.zPosition
                || (rim.layer.zPosition == sibling.layer.zPosition && rimIndex > index)
            XCTAssertTrue(above, "亮邊被 \(type(of: sibling)) 蓋住", file: file, line: line)
        }
    }

    // MARK: 預設值

    func test_byDefault_theBarKeepsLiquidGlassWithoutRimShadowOrInsets() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController()
        let tabs = try tabsCapsule(in: controller)
        let action = try actionCapsule(in: controller)

        let appearance = TeroFloatingGlassAppearance()
        XCTAssertEqual(appearance.material, .liquidGlass)
        XCTAssertEqual(appearance.contentInsets, .zero)
        XCTAssertTrue(tabs.effect is UIGlassEffect)
        XCTAssertTrue(action.effect is UIGlassEffect)
        XCTAssertNil(rim(in: tabs))
        XCTAssertNil(rim(in: action))
        XCTAssertNil(shadow(in: controller))

        let first = try XCTUnwrap(tabBarControl(for: "t0", in: controller))
        let last = try XCTUnwrap(tabBarControl(for: "t3", in: controller))
        XCTAssertEqual(first.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(last.frame.maxX, tabs.bounds.width, accuracy: 0.5)
        XCTAssertEqual(first.frame.height, tabs.bounds.height, accuracy: 0.5)
    }

    // MARK: 材質

    func test_blurMaterial_putsTheBlurStyleAndTheFillOnBothCapsules() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let fill = UIColor.white.withAlphaComponent(0.3)
        let controller = makeFloatingController {
            $0.floatingGlassAppearance.material = .blur
            $0.floatingGlassAppearance.blurEffectStyle = .systemUltraThinMaterialLight
            $0.floatingGlassAppearance.blurFillColor = fill
        }

        for capsule in [try tabsCapsule(in: controller), try actionCapsule(in: controller)] {
            let blur = try XCTUnwrap(capsule.effect as? UIBlurEffect, "膠囊應是模糊，不是玻璃")
            XCTAssertEqual(blur, UIBlurEffect(style: .systemUltraThinMaterialLight))
            assertSameColor(capsule.contentView.backgroundColor, fill)
        }
        let container = try XCTUnwrap(glassContainer(around: try tabsCapsule(in: controller), in: controller))
        XCTAssertNil(container.effect, "模糊材質不融合，外面不該再套玻璃容器")
    }

    func test_blurMaterial_withoutAFill_leavesTheBlurUncovered() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController { $0.floatingGlassAppearance.material = .blur }

        let capsule = try tabsCapsule(in: controller)
        XCTAssertEqual(capsule.effect, UIBlurEffect(style: TeroFloatingGlassAppearance().blurEffectStyle))
        XCTAssertEqual(capsule.contentView.backgroundColor?.cgColor.alpha ?? 0, 0)
    }

    func test_switchingBackToLiquidGlass_dropsTheBlurFill() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController {
            $0.floatingGlassAppearance.material = .blur
            $0.floatingGlassAppearance.blurFillColor = .white
        }

        let update = controller.currentConfiguration()
        update.floatingGlassAppearance.material = .liquidGlass
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        let capsule = try tabsCapsule(in: controller)
        XCTAssertTrue(capsule.effect is UIGlassEffect)
        XCTAssertEqual(capsule.contentView.backgroundColor?.cgColor.alpha ?? 0, 0, "玻璃上不能留著模糊的填色")
        let container = try XCTUnwrap(glassContainer(around: capsule, in: controller))
        XCTAssertTrue(container.effect is UIGlassContainerEffect)
    }

    // MARK: 降低透明度

    func test_reducedTransparency_blurFallsBackToTheOpaqueFill() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        overrideAccessibility(reduceTransparency: true)
        let controller = makeFloatingController {
            $0.floatingGlassAppearance.material = .blur
            $0.floatingGlassAppearance.blurFillColor = UIColor.systemTeal.withAlphaComponent(0.3)
            $0.floatingGlassAppearance.glassTintMode = .tinted
            $0.floatingGlassAppearance.glassTintColor = .systemPink
        }

        for capsule in [try tabsCapsule(in: controller), try actionCapsule(in: controller)] {
            XCTAssertNil(capsule.effect)
            assertSameColor(capsule.contentView.backgroundColor, .systemTeal)
        }
    }

    func test_reducedTransparency_blurWithoutAFillFallsBackToTheSystemBackground() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        overrideAccessibility(reduceTransparency: true)
        let controller = makeFloatingController { $0.floatingGlassAppearance.material = .blur }

        let capsule = try tabsCapsule(in: controller)
        XCTAssertNil(capsule.effect)
        assertSameColor(capsule.contentView.backgroundColor, .systemBackground)
    }

    func test_reducedTransparency_keepsTheRimAndTheShadow() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        overrideAccessibility(reduceTransparency: true)
        let controller = makeFloatingController {
            $0.floatingGlassAppearance.material = .blur
            self.configureRim($0)
            self.configureShadow($0)
        }

        XCTAssertNotNil(rim(in: try tabsCapsule(in: controller)))
        XCTAssertNotNil(shadow(in: controller))
    }

    // MARK: 亮邊

    func test_rim_runsInsideTheEdgeOfBothCapsulesWithTheConfiguredGradient() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureRim)

        for capsule in [try tabsCapsule(in: controller), try actionCapsule(in: controller)] {
            let rim = try XCTUnwrap(rim(in: capsule), "兩顆膠囊都要有亮邊")
            XCTAssertEqual(rim.frame, capsule.contentView.bounds)
            XCTAssertEqual(rim.edgeWidth, 1)
            XCTAssertEqual(rim.edgeCornerRadius, capsule.layer.cornerRadius, accuracy: 0.01)
            let gradient = rim.gradientLayer
            let colors = try XCTUnwrap(gradient.colors as? [CGColor])
            XCTAssertEqual(colors.count, 3)
            for (actual, expected) in zip(colors, rimColors) {
                assertSameColor(UIColor(cgColor: actual), expected)
            }
            XCTAssertEqual(gradient.startPoint, CGPoint(x: 0, y: 0))
            XCTAssertEqual(gradient.endPoint, CGPoint(x: 1, y: 1))
            XCTAssertFalse(rim.isUserInteractionEnabled, "亮邊不能吃掉點擊")
            assertDrawsAboveItsSiblings(rim)
        }
    }

    func test_rim_masksTheGradientToABorderOfItsWidth() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController {
            self.configureRim($0)
            $0.floatingGlassAppearance.rimWidth = 1.5
        }

        let capsule = try tabsCapsule(in: controller)
        let rim = try XCTUnwrap(rim(in: capsule))
        let mask = try XCTUnwrap(rim.mask, "沒有遮罩就是整顆膠囊塗滿漸層")
        XCTAssertEqual(mask.frame, rim.bounds)
        XCTAssertEqual(mask.layer.borderWidth, 1.5)
        XCTAssertEqual(mask.layer.cornerRadius, capsule.layer.cornerRadius, accuracy: 0.01)
        XCTAssertEqual(mask.layer.cornerCurve, capsule.layer.cornerCurve)
        XCTAssertEqual(mask.backgroundColor?.cgColor.alpha ?? 0, 0, "遮罩的內部要是空的，只留邊框")
    }

    func test_rim_withASingleColour_isSolid() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController {
            $0.floatingGlassAppearance.rimWidth = 1
            $0.floatingGlassAppearance.rimColors = [.white]
        }

        let rim = try XCTUnwrap(rim(in: try tabsCapsule(in: controller)))
        let colors = try XCTUnwrap(rim.gradientLayer.colors as? [CGColor])
        XCTAssertGreaterThanOrEqual(colors.count, 2, "CAGradientLayer 只有一個顏色時什麼都不畫")
        for color in colors { assertSameColor(UIColor(cgColor: color), .white) }
    }

    func test_rim_withoutAWidthOrColours_isNotDrawn() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let noWidth = makeFloatingController {
            $0.floatingGlassAppearance.rimColors = [.white, .gray]
        }
        XCTAssertNil(rim(in: try tabsCapsule(in: noWidth)))

        let noColours = makeFloatingController {
            $0.floatingGlassAppearance.rimWidth = 1
        }
        XCTAssertNil(rim(in: try tabsCapsule(in: noColours)))
    }

    func test_rim_followsTheCapsuleWhileItMinimizes() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureRim)

        controller.setTabBarPresentationState(.minimized, animated: true)
        advance(0.1)
        let progress = controller.tabBar.minimizationProgress
        XCTAssertGreaterThan(progress, 0)
        XCTAssertLessThan(progress, 1)

        for capsule in [try tabsCapsule(in: controller), try actionCapsule(in: controller)] {
            let rim = try XCTUnwrap(rim(in: capsule))
            XCTAssertEqual(rim.frame, capsule.contentView.bounds)
            XCTAssertEqual(rim.edgeCornerRadius, capsule.layer.cornerRadius, accuracy: 0.01)
            XCTAssertEqual(rim.mask?.frame, rim.bounds)
        }
    }

    func test_rim_isRemovedWhenTheWidthGoesBackToZero() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureRim)

        let update = controller.currentConfiguration()
        update.floatingGlassAppearance.rimWidth = 0
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNil(rim(in: try tabsCapsule(in: controller)))
        XCTAssertNil(rim(in: try actionCapsule(in: controller)))
    }

    func test_rim_appliesToLiquidGlassToo() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureRim)

        let capsule = try tabsCapsule(in: controller)
        XCTAssertTrue(capsule.effect is UIGlassEffect)
        XCTAssertNotNil(rim(in: capsule), "亮邊與材質各自獨立")
    }

    // MARK: 外陰影

    func test_shadow_hasTheConfiguredParameters() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureShadow)

        let shadow = try XCTUnwrap(shadow(in: controller))
        XCTAssertEqual(shadow.layer.shadowOpacity, 0.2)
        assertSameColor(shadow.layer.shadowColor.map(UIColor.init(cgColor:)), .systemIndigo)
        XCTAssertEqual(shadow.layer.shadowOffset, CGSize(width: 0, height: 4))
        XCTAssertEqual(shadow.layer.shadowRadius, 10)
        XCTAssertFalse(shadow.isUserInteractionEnabled)
    }

    func test_shadow_isCastByBothCapsulesFromBehindThem() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureShadow)
        let tabs = try tabsCapsule(in: controller)
        let action = try actionCapsule(in: controller)

        let shadow = try XCTUnwrap(shadow(in: controller))
        let path = try XCTUnwrap(shadow.layer.shadowPath)
        let tabsFrame = tabs.convert(tabs.bounds, to: shadow)
        let actionFrame = action.convert(action.bounds, to: shadow)
        assertEqualRects(path.boundingBoxOfPath, tabsFrame.union(actionFrame))
        XCTAssertTrue(path.contains(CGPoint(x: tabsFrame.midX, y: tabsFrame.midY)))
        XCTAssertTrue(path.contains(CGPoint(x: actionFrame.midX, y: actionFrame.midY)))

        let container = try XCTUnwrap(glassContainer(around: tabs, in: controller))
        let subviews = controller.tabBar.subviews
        XCTAssertLessThan(try XCTUnwrap(subviews.firstIndex(of: shadow)), try XCTUnwrap(subviews.firstIndex(of: container)),
                          "陰影要在膠囊後面")
    }

    /// 只畫在膠囊外面，跟設計工具的外陰影一樣。半透明的膠囊底下如果也有陰影，
    /// 整顆膠囊會被染灰。
    func test_shadow_isNotDrawnUnderTheTranslucentCapsules() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureShadow)
        let tabs = try tabsCapsule(in: controller)

        let shadow = try XCTUnwrap(shadow(in: controller))
        let mask = try XCTUnwrap(shadow.layer.mask as? CAShapeLayer, "沒有遮罩，陰影會鋪在膠囊底下")
        let maskPath = try XCTUnwrap(mask.path)
        let rule: CGPathFillRule = mask.fillRule == .evenOdd ? .evenOdd : .winding
        let frame = tabs.convert(tabs.bounds, to: shadow)
        let center = shadow.layer.convert(CGPoint(x: frame.midX, y: frame.midY), to: mask)
        let below = shadow.layer.convert(CGPoint(x: frame.midX, y: frame.maxY + 6), to: mask)
        XCTAssertFalse(maskPath.contains(center, using: rule), "膠囊裡面不能有陰影")
        XCTAssertTrue(maskPath.contains(below, using: rule), "膠囊下緣外面要看得到陰影")
    }

    func test_shadow_withoutAnAction_isCastByTheTabsAlone() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(withAction: false, configure: configureShadow)
        let tabs = try tabsCapsule(in: controller)

        let shadow = try XCTUnwrap(shadow(in: controller))
        assertEqualRects(try XCTUnwrap(shadow.layer.shadowPath?.boundingBoxOfPath), tabs.convert(tabs.bounds, to: shadow))
    }

    func test_shadow_followsTheCapsulesWhileTheyMinimize() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureShadow)

        controller.setTabBarPresentationState(.minimized, animated: true)
        advance(0.1)
        let progress = controller.tabBar.minimizationProgress
        XCTAssertGreaterThan(progress, 0)
        XCTAssertLessThan(progress, 1)

        let tabs = try tabsCapsule(in: controller)
        let action = try actionCapsule(in: controller)
        let shadow = try XCTUnwrap(shadow(in: controller))
        let expected = tabs.convert(tabs.bounds, to: shadow).union(action.convert(action.bounds, to: shadow))
        let actual = try XCTUnwrap(shadow.layer.shadowPath?.boundingBoxOfPath)
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.01)
        XCTAssertEqual(actual.maxX, expected.maxX, accuracy: 0.01)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.01)
    }

    /// 一開始沒有陰影，執行中才打開：path 要立刻畫出來，不能等下一次碰巧的排版。
    func test_shadow_turnedOnAtRuntime_isCastStraightAway() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController()
        XCTAssertNil(shadow(in: controller))

        let update = controller.currentConfiguration()
        update.floatingGlassAppearance.shadowOpacity = 0.2
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        let tabs = try tabsCapsule(in: controller)
        let shadow = try XCTUnwrap(shadow(in: controller))
        let path = try XCTUnwrap(shadow.layer.shadowPath, "陰影打開了，path 卻還沒畫")
        let tabsFrame = tabs.convert(tabs.bounds, to: shadow)
        XCTAssertTrue(path.contains(CGPoint(x: tabsFrame.midX, y: tabsFrame.midY)))
    }

    func test_shadow_isRemovedWhenTheOpacityGoesBackToZero() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(configure: configureShadow)

        let update = controller.currentConfiguration()
        update.floatingGlassAppearance.shadowOpacity = 0
        controller.applyConfiguration(update, animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertNil(shadow(in: controller))
    }

    // MARK: 深淺色

    /// 亮邊與陰影的顏色要變成 CGColor 才畫得出來，動態顏色得自己在深淺色切換時重新解析。
    func test_rimAndShadow_followTheInterfaceStyle() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let dynamic = UIColor { $0.userInterfaceStyle == .dark ? .red : .blue }
        let controller = makeFloatingController {
            $0.floatingGlassAppearance.rimWidth = 1
            $0.floatingGlassAppearance.rimColors = [dynamic]
            $0.floatingGlassAppearance.shadowOpacity = 0.3
            $0.floatingGlassAppearance.shadowColor = dynamic
        }
        window.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        let rim = try XCTUnwrap(rim(in: try tabsCapsule(in: controller)))
        let shadow = try XCTUnwrap(shadow(in: controller))
        assertSameColor((rim.gradientLayer.colors?.first).map { UIColor(cgColor: $0 as! CGColor) }, .blue)
        assertSameColor(shadow.layer.shadowColor.map(UIColor.init(cgColor:)), .blue)

        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()

        assertSameColor((rim.gradientLayer.colors?.first).map { UIColor(cgColor: $0 as! CGColor) }, .red)
        assertSameColor(shadow.layer.shadowColor.map(UIColor.init(cgColor:)), .red)
    }

    // MARK: Classic

    func test_classic_drawsNeitherRimNorShadow() throws {
        let controller = makeController(configuration: {
            let configuration = TeroTabBarConfiguration.defaultConfiguration()
            configuration.style = .classic
            configureRim(configuration)
            configureShadow(configuration)
            return configuration
        }())
        controller.setTabs((0..<3).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()

        XCTAssertNil(shadow(in: controller))
        let capsule = try tabsCapsule(in: controller)
        XCTAssertNil(rim(in: capsule), "亮邊與陰影是 FloatingGlass 的外觀")
    }

    // MARK: 項目區內距

    func test_contentInsets_insetTheItemsInsideTheTabsCapsule() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let insets = UIEdgeInsets(top: 4, left: 2, bottom: 6, right: 10)
        let controller = makeFloatingController(withAction: false) {
            $0.floatingGlassAppearance.contentInsets = insets
        }
        let capsule = try tabsCapsule(in: controller)
        let items = try (0..<4).map { try XCTUnwrap(tabBarControl(for: "t\($0)", in: controller)) }

        let width = (capsule.bounds.width - insets.left - insets.right) / 4
        XCTAssertEqual(items[0].frame.minX, insets.left, accuracy: 1)
        XCTAssertEqual(items[3].frame.maxX, capsule.bounds.width - insets.right, accuracy: 1)
        for item in items {
            XCTAssertEqual(item.frame.width, width, accuracy: 1)
            XCTAssertEqual(item.frame.minY, insets.top, accuracy: 0.5)
            XCTAssertEqual(item.frame.height, capsule.bounds.height - insets.top - insets.bottom, accuracy: 0.5)
        }
    }

    func test_contentInsets_keepTheSelectionInsideTheSelectedItem() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(withAction: false) {
            $0.floatingGlassAppearance.contentInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        }
        let item = try XCTUnwrap(tabBarControl(for: "t0", in: controller))
        let selection = try XCTUnwrap(item.superview?.subviews.compactMap { $0 as? TeroTabSelectionIndicatorView }.first)

        XCTAssertTrue(item.frame.insetBy(dx: -0.5, dy: -0.5).contains(selection.frame),
                      "選取外框 \(selection.frame) 超出了格位 \(item.frame)")
        XCTAssertEqual(selection.frame.midX, item.frame.midX, accuracy: 1)
        let selectionInsets = controller.currentConfiguration().itemAppearance.selectionIndicatorInsets
        XCTAssertEqual(selection.frame.height, item.frame.height - selectionInsets.top - selectionInsets.bottom,
                       accuracy: 0.5, "選取外框的上下內縮從格位量起，不是從膠囊")
    }

    func test_contentInsets_scaleWithTheBarWhenUniformlyMinimized() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let insets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        let controller = makeFloatingController(withAction: false) {
            $0.floatingGlassAppearance.contentInsets = insets
        }
        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        let appearance = controller.currentConfiguration().floatingGlassAppearance
        let scale = appearance.minimizedHeight / appearance.expandedHeight
        let capsule = try tabsCapsule(in: controller)
        let first = try XCTUnwrap(tabBarControl(for: "t0", in: controller))
        let last = try XCTUnwrap(tabBarControl(for: "t3", in: controller))
        XCTAssertEqual(first.frame.minX, insets.left * scale, accuracy: 1)
        XCTAssertEqual(last.frame.maxX, capsule.bounds.width - insets.right * scale, accuracy: 1)
    }

    func test_contentInsets_scaleWithThePillWhenMinimizedToTheSelectedItem() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let insets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        // 6 格：4 格時膠囊寬會被夾在高度的 1.6 倍，看不出它有沒有算進內距。
        let tabCount = 6
        let controller = makeFloatingController(tabCount: tabCount, withAction: false) {
            $0.floatingGlassAppearance.contentInsets = insets
            $0.floatingGlassAppearance.minimizedLayout = .selectedOnly
        }
        let expandedWidth = try tabsCapsule(in: controller).bounds.width
        controller.setTabBarPresentationState(.minimized, animated: false)
        controller.view.layoutIfNeeded()

        let appearance = controller.currentConfiguration().floatingGlassAppearance
        let scale = appearance.minimizedHeight / appearance.expandedHeight
        let capsule = try tabsCapsule(in: controller)
        let slot = (expandedWidth - insets.left - insets.right) / CGFloat(tabCount)
        XCTAssertEqual(capsule.bounds.width, ((slot + insets.left + insets.right) * scale).rounded(), accuracy: 1,
                       "膠囊是展開時的一格連同左右內距，等比縮小")
        let selected = try XCTUnwrap(tabBarControl(for: "t0", in: controller))
        XCTAssertEqual(selected.frame.minX, insets.left * scale, accuracy: 1)
        XCTAssertEqual(selected.frame.maxX, capsule.bounds.width - insets.right * scale, accuracy: 1)
        XCTAssertEqual(selected.frame.minY, insets.top * scale, accuracy: 1)

        let selection = try XCTUnwrap(selected.superview?.subviews.compactMap { $0 as? TeroTabSelectionIndicatorView }.first)
        let selectionInsets = controller.currentConfiguration().itemAppearance.selectionIndicatorInsets
        let expected = (appearance.expandedHeight - insets.top - insets.bottom
                        - selectionInsets.top - selectionInsets.bottom) * scale
        XCTAssertEqual(selection.frame.height, expected, accuracy: 0.5)
    }

    /// 與 Classic 的 `contentInsets` 相同：左右是實體的左右，RTL 不對調。
    func test_contentInsets_arePhysicalInRightToLeft() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let insets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 10)
        let controller = makeFloatingController(withAction: false) {
            $0.floatingGlassAppearance.contentInsets = insets
        }
        controller.view.semanticContentAttribute = .forceRightToLeft
        controller.tabBar.semanticContentAttribute = .forceRightToLeft
        controller.tabBar.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let capsule = try tabsCapsule(in: controller)
        let first = try XCTUnwrap(tabBarControl(for: "t0", in: controller))
        let last = try XCTUnwrap(tabBarControl(for: "t3", in: controller))
        XCTAssertEqual(first.frame.maxX, capsule.bounds.width - insets.right, accuracy: 1, "RTL 的第一格在最右邊")
        XCTAssertEqual(last.frame.minX, insets.left, accuracy: 1)
    }

    func test_contentInsets_tappingAnItemStillSelectsIt() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(withAction: false) {
            $0.floatingGlassAppearance.contentInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        }
        let item = try XCTUnwrap(tabBarControl(for: "t3", in: controller))
        let point = item.convert(CGPoint(x: item.bounds.midX, y: item.bounds.midY), to: controller.tabBar)

        XCTAssertIdentical(controller.tabBar.hitTest(point, with: nil), item)
    }

    /// 內距那一段不屬於任何一格，但它還是看得到的膠囊：點在那裡不能穿過 Bar
    /// 點到後面的頁面，算最近的那一格。
    func test_contentInsets_aTapOnTheCapsuleEdgeGoesToTheNearestItem() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(withAction: false) {
            $0.floatingGlassAppearance.contentInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        }
        let capsule = try tabsCapsule(in: controller)
        let frame = capsule.convert(capsule.bounds, to: controller.tabBar)

        let leftEdge = CGPoint(x: frame.minX + 4, y: frame.midY)
        let rightEdge = CGPoint(x: frame.maxX - 4, y: frame.midY)
        XCTAssertIdentical(controller.tabBar.hitTest(leftEdge, with: nil), tabBarControl(for: "t0", in: controller))
        XCTAssertIdentical(controller.tabBar.hitTest(rightEdge, with: nil), tabBarControl(for: "t3", in: controller))
        XCTAssertNil(controller.tabBar.hitTest(CGPoint(x: frame.minX - 4, y: frame.midY), with: nil),
                     "膠囊外面仍然穿透")
    }

    func test_aTapOnADisabledItemIsNotHandedToItsNeighbour() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("需要 iOS 26") }
        let controller = makeFloatingController(withAction: false) {
            $0.floatingGlassAppearance.contentInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        }
        controller.setTabs([makeTab("t0"), makeTab("t1", enabled: false), makeTab("t2")],
                           selectedIdentifier: "t0", animated: false)
        controller.view.layoutIfNeeded()
        let disabled = try XCTUnwrap(tabBarControl(for: "t1", in: controller))
        let point = disabled.convert(CGPoint(x: disabled.bounds.midX, y: disabled.bounds.midY), to: controller.tabBar)

        XCTAssertNil(controller.tabBar.hitTest(point, with: nil))
    }

    // MARK: 設定物件

    func test_theNewSettingsSurviveTheConfigurationDeepCopy() throws {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.floatingGlassAppearance.material = .blur
        configuration.floatingGlassAppearance.rimColors = [.white, .black]
        configuration.floatingGlassAppearance.contentInsets = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)

        let copy = try XCTUnwrap(configuration.copy() as? TeroTabBarConfiguration)
        configuration.floatingGlassAppearance.material = .liquidGlass
        configuration.floatingGlassAppearance.rimColors = []

        XCTAssertEqual(copy.floatingGlassAppearance.material, .blur)
        XCTAssertEqual(copy.floatingGlassAppearance.rimColors, [.white, .black])
        XCTAssertEqual(copy.floatingGlassAppearance.contentInsets, UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4))
    }
}
