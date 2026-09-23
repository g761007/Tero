import XCTest
@testable import Tero

/// 對應 ticket #43 的選取幾何。純運算，兩個 layout engine 共用同一組規則。
final class SelectionGeometryTests: XCTestCase {

    private let slot = CGRect(x: 100, y: 0, width: 80, height: 56)

    func test_unspecifiedSizeFallsBackToInsets() {
        let insets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        let frame = TeroTabSelectionGeometry.frame(inSlot: slot, requestedSize: nil, insets: insets)

        XCTAssertEqual(frame, slot.inset(by: insets))
    }

    func test_zeroSizeIsTreatedAsUnspecified() {
        let insets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        let frame = TeroTabSelectionGeometry.frame(inSlot: slot, requestedSize: .zero, insets: insets)

        XCTAssertEqual(frame, slot.inset(by: insets))
    }

    func test_requestedSizeIsCentredInTheSlot() {
        let frame = TeroTabSelectionGeometry.frame(
            inSlot: slot,
            requestedSize: CGSize(width: 40, height: 30),
            insets: .zero
        )

        XCTAssertEqual(frame.width, 40)
        XCTAssertEqual(frame.height, 30)
        XCTAssertEqual(frame.midX, slot.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, slot.midY, accuracy: 0.5)
    }

    func test_requestedSizeIsClampedToTheSlot() {
        let frame = TeroTabSelectionGeometry.frame(
            inSlot: slot,
            requestedSize: CGSize(width: 500, height: 500),
            insets: .zero
        )

        XCTAssertEqual(frame.width, slot.width)
        XCTAssertEqual(frame.height, slot.height)
    }

    func test_requestedSizeIgnoresInsets() {
        // 指定尺寸就是指定尺寸，不該再被內縮削一次。
        let frame = TeroTabSelectionGeometry.frame(
            inSlot: slot,
            requestedSize: CGSize(width: 40, height: 30),
            insets: UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        )

        XCTAssertEqual(frame.width, 40)
    }

    func test_framesAlignOneToOneWithSlots() {
        let slots = [slot, slot.offsetBy(dx: 80, dy: 0), slot.offsetBy(dx: 160, dy: 0)]

        let frames = TeroTabSelectionGeometry.frames(
            inSlots: slots,
            requestedSizes: [nil, CGSize(width: 40, height: 30), nil],
            insets: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        )

        XCTAssertEqual(frames.count, slots.count)
        XCTAssertEqual(frames[0].width, slot.width - 12)
        XCTAssertEqual(frames[1].width, 40)
        XCTAssertEqual(frames[2].width, slot.width - 12)
    }

    func test_missingSizesAreTreatedAsUnspecified() {
        let slots = [slot, slot.offsetBy(dx: 80, dy: 0)]

        let frames = TeroTabSelectionGeometry.frames(inSlots: slots, requestedSizes: [], insets: .zero)

        XCTAssertEqual(frames, slots)
    }
}


/// Layout engine 是「選取外框在哪」的單一答案來源（補充規格 §26）。
final class LayoutEngineSelectionFrameTests: XCTestCase {

    private let insets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

    func test_classicEngineEmitsOneSelectionFramePerItem() {
        let layout = TeroClassicLayoutEngine().layout(
            itemCount: 4,
            hasCenterAction: false,
            in: CGRect(x: 0, y: 0, width: 400, height: 49),
            contentInsets: .zero,
            selectionInsets: insets,
            selectionSizes: [],
            layoutDirection: .leftToRight
        )

        XCTAssertEqual(layout.selectionFrames.count, layout.itemFrames.count)
        for (item, selection) in zip(layout.itemFrames, layout.selectionFrames) {
            XCTAssertEqual(selection, item.inset(by: insets))
        }
    }

    func test_classicEngineKeepsSelectionFramesAlignedWhenAnActionSplitsTheRow() {
        let layout = TeroClassicLayoutEngine().layout(
            itemCount: 4,
            hasCenterAction: true,
            in: CGRect(x: 0, y: 0, width: 500, height: 49),
            contentInsets: .zero,
            selectionInsets: insets,
            selectionSizes: [],
            layoutDirection: .leftToRight
        )

        XCTAssertEqual(layout.selectionFrames.count, 4)
        for (item, selection) in zip(layout.itemFrames, layout.selectionFrames) {
            XCTAssertEqual(selection.midX, item.midX, accuracy: 0.5)
        }
        // Action 那一欄不該出現在選取外框裡。
        if let action = layout.actionFrame {
            XCTAssertFalse(layout.selectionFrames.contains { $0.midX == action.midX })
        }
    }

    func test_floatingEngineEmitsOneSelectionFramePerItem() {
        let layout = TeroFloatingGlassLayoutEngine().layout(
            itemCount: 5,
            hasAction: false,
            state: .expanded,
            in: CGRect(x: 0, y: 0, width: 390, height: 56),
            appearance: TeroFloatingGlassAppearance(),
            selectionInsets: insets,
            selectionSizes: [],
            layoutDirection: .leftToRight
        )

        XCTAssertEqual(layout.selectionFrames.count, 5)
        for (item, selection) in zip(layout.itemFrames, layout.selectionFrames) {
            XCTAssertEqual(selection, item.inset(by: insets))
        }
    }

    func test_floatingEngineHonoursPerItemSelectionSizes() {
        let layout = TeroFloatingGlassLayoutEngine().layout(
            itemCount: 4,
            hasAction: false,
            state: .expanded,
            in: CGRect(x: 0, y: 0, width: 390, height: 56),
            appearance: TeroFloatingGlassAppearance(),
            selectionInsets: insets,
            selectionSizes: [nil, CGSize(width: 30, height: 30), nil, nil],
            layoutDirection: .leftToRight
        )

        XCTAssertEqual(layout.selectionFrames[1].width, 30)
        XCTAssertNotEqual(layout.selectionFrames[0].width, 30)
    }

    func test_minimizedStateStillProducesSelectionFrames() {
        let layout = TeroFloatingGlassLayoutEngine().layout(
            itemCount: 3,
            hasAction: true,
            state: .minimized,
            in: CGRect(x: 0, y: 0, width: 390, height: 36),
            appearance: TeroFloatingGlassAppearance(),
            selectionInsets: insets,
            selectionSizes: [],
            layoutDirection: .leftToRight
        )

        XCTAssertEqual(layout.selectionFrames.count, 3)
        XCTAssertTrue(layout.selectionFrames.allSatisfy { $0.height > 0 })
    }
}


/// 選取外框與 Badge、Action、裁切之間的邊界（補充規格 §10、§11、§20）。
final class SelectionBoundaryTests: TeroTabBarControllerTestCase {

    private func makeBoundaryController(
        floating: Bool = true,
        mutate: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        if floating { configuration.style = .floatingGlass }
        configuration.itemAppearance.selectionIndicatorStyle = .always
        mutate(configuration)
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<4).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func indicator(in controller: TeroTabBarController) -> TeroTabSelectionIndicatorView? {
        func search(_ view: UIView) -> TeroTabSelectionIndicatorView? {
            if let found = view as? TeroTabSelectionIndicatorView { return found }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(controller.tabBar)
    }

    func test_badgeDoesNotChangeTheSelectionFrame() {
        let controller = makeBoundaryController()
        let before = indicator(in: controller)?.frame

        controller.tabs[0].item.badge = .value("999+")
        controller.setTabs(controller.tabs, selectedIdentifier: "t0", animated: false)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(indicator(in: controller)?.frame, before, "Badge 不該把選取外框撐寬（補充規格 §10）")
    }

    func test_selectionStaysInsideTheTabsCapsuleWhenAnActionExists() {
        let controller = makeBoundaryController()
        let action = TeroTabActionItem(identifier: "compose", image: UIImage(systemName: "plus"))
        action.accessibilityIdentifier = "tab.action"
        controller.setActionItem(action, animated: false)
        controller.view.layoutIfNeeded()

        guard let indicator = indicator(in: controller),
              let item = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        XCTAssertTrue(indicator.superview === item.superview, "外框與 Tab 同屬 Tabs 膠囊")
    }

    func test_triggeringTheActionDoesNotMoveTheSelection() {
        let controller = makeBoundaryController()
        let action = TeroTabActionItem(identifier: "compose", image: UIImage(systemName: "plus"))
        action.accessibilityIdentifier = "tab.action"
        controller.setActionItem(action, animated: false)
        controller.view.layoutIfNeeded()
        let before = indicator(in: controller)?.frame

        forceTapTabBarItem("action", in: controller)
        controller.view.layoutIfNeeded()

        XCTAssertEqual(controller.selectedTab?.identifier, "t0")
        XCTAssertEqual(indicator(in: controller)?.frame, before)
    }

    func test_itemViewsDoNotClipTheirContent() {
        let controller = makeBoundaryController()

        guard let item = tabBarControl(for: "t0", in: controller) else { return XCTFail() }
        XCTAssertFalse(item.clipsToBounds, "自訂內容要能畫出 Item 邊界（補充規格 §11）")
        XCTAssertEqual(item.superview?.clipsToBounds, false, "items 容器同樣不裁切")
    }

    func test_cornerRadiusInterpolatesAlongsideTheFrame() throws {
        let controller = makeBoundaryController {
            $0.motion.selectionResponse = 1.2
        }
        controller.tabs[2].item.selectionSize = CGSize(width: 40, height: 20)
        controller.setTabs(controller.tabs, selectedIdentifier: "t0", animated: false)
        controller.view.layoutIfNeeded()

        guard let indicator = indicator(in: controller) else { return XCTFail() }
        let startRadius = indicator.layer.cornerRadius

        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        let endRadius = indicator.layer.cornerRadius
        XCTAssertNotEqual(startRadius, endRadius, accuracy: 0.1, "高度不同，圓角也要跟著變")
        guard let presented = indicator.layer.presentation()?.cornerRadius else {
            throw XCTSkip("模擬器沒有提供 presentation layer")
        }
        let low = min(startRadius, endRadius), high = max(startRadius, endRadius)
        XCTAssertGreaterThanOrEqual(presented, low - 0.5)
        XCTAssertLessThanOrEqual(presented, high + 0.5)
    }
}
