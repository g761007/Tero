import XCTest
@testable import Tero

/// 對應 ticket #40 的可中斷選取轉場。
///
/// 一律透過 controller 的公開 API 驅動，再從公開的 `tabBar` 階層量測外框位置——
/// 斷言的是「膠囊最後往哪去」，不是「協調器被呼叫了幾次」。
final class SelectionTransitionTests: TeroTabBarControllerTestCase {

    private func makeFloatingController(
        tabCount: Int = 5,
        mutate: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.compact.maximumVisibleItems = 6
        configuration.itemAppearance.selectionIndicatorStyle = .always
        mutate(configuration)
        let controller = makeController(configuration: configuration)
        controller.setTabs((0..<tabCount).map { makeTab("t\($0)") }, selectedIdentifier: "t0", animated: false)
        present(controller)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func indicator(in controller: TeroTabBarController) -> UIView? {
        func search(_ view: UIView) -> UIView? {
            if view is TeroTabSelectionIndicatorView { return view }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(controller.tabBar)
    }

    private func assertIndicatorCentred(
        on identifier: String,
        in controller: TeroTabBarController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // 檢查完成後的實際幾何，而非 UIKit animator 提早写入的 model-layer 終點。
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        guard let indicator = indicator(in: controller),
              let item = tabBarControl(for: identifier, in: controller) else {
            return XCTFail("找不到外框或 \(identifier)", file: file, line: line)
        }
        XCTAssertEqual(indicator.frame.midX, item.frame.midX, accuracy: 1.0, file: file, line: line)
    }

    // MARK: 中斷與轉向

    func test_rapidSwitchingRetargetsToTheLastSelection() {
        let controller = makeFloatingController()

        // 不讓 runloop 跑：三次選取全部落在同一個動畫週期內。
        controller.selectTab(withIdentifier: "t1", animated: true)
        controller.selectTab(withIdentifier: "t2", animated: true)
        controller.selectTab(withIdentifier: "t3", animated: true)

        assertIndicatorCentred(on: "t3", in: controller)
        XCTAssertEqual(controller.selectedTab?.identifier, "t3")
    }

    func test_switchingBackAndForthEndsWhereTheUserLastTapped() {
        let controller = makeFloatingController()

        controller.selectTab(withIdentifier: "t1", animated: true)
        controller.selectTab(withIdentifier: "t3", animated: true)
        controller.selectTab(withIdentifier: "t0", animated: true)

        assertIndicatorCentred(on: "t0", in: controller)
    }

    func test_nonInterruptibleTransitionLetsTheRunningSegmentFinishFirst() {
        let controller = makeFloatingController {
            $0.motion.allowsInterruptibleTransition = false
        }

        controller.selectTab(withIdentifier: "t1", animated: true)
        controller.selectTab(withIdentifier: "t3", animated: true)

        // 選取本身立即生效；只有外框的動畫被排在後面。
        XCTAssertEqual(controller.selectedTab?.identifier, "t3")
        guard let view = indicator(in: controller), let item = tabBarControl(for: "t1", in: controller) else { return XCTFail() }
        XCTAssertLessThanOrEqual(view.frame.midX, item.frame.midX, "目前這段仍向第一個目標移動")
    }

    func test_queuedTransitionEventuallyReachesTheLastTarget() {
        let controller = makeFloatingController {
            $0.motion.allowsInterruptibleTransition = false
            $0.motion.selectionResponse = 0.05
        }

        controller.selectTab(withIdentifier: "t1", animated: true)
        controller.selectTab(withIdentifier: "t3", animated: true)

        // 讓排隊的那段接上。
        let deadline = Date().addingTimeInterval(2)
        RunLoop.current.run(until: deadline)

        assertIndicatorCentred(on: "t3", in: controller)
    }

    // MARK: 動畫不擋操作

    func test_barStaysInteractiveDuringATransition() {
        let controller = makeFloatingController()

        controller.selectTab(withIdentifier: "t2", animated: true)

        XCTAssertTrue(controller.tabBar.isUserInteractionEnabled)
        // 轉場中疊上去的透鏡本來就必須不吃觸控，否則它會擋住底下的 Tab。
        // §14 要的是「還能操作」，不是「每一層都吃觸控」——後者由
        // `test_tappingDuringATransitionSelectsImmediately` 與 SelectionLensTests 守住。
        XCTAssertTrue(
            controller.tabBar.subviews
                .filter { !($0 is TeroTabSelectionIndicatorView) }
                .allSatisfy { $0.isUserInteractionEnabled }
        )
    }

    func test_tappingDuringATransitionSelectsImmediately() {
        let controller = makeFloatingController()

        controller.selectTab(withIdentifier: "t2", animated: true)
        tapTabBarItem("t4", in: controller)

        XCTAssertEqual(controller.selectedTab?.identifier, "t4")
        assertIndicatorCentred(on: "t4", in: controller)
    }

    // MARK: 重新排版

    func test_relayoutDuringATransitionKeepsHeadingToTheSameTarget() {
        let controller = makeFloatingController()

        controller.selectTab(withIdentifier: "t3", animated: true)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        assertIndicatorCentred(on: "t3", in: controller)
    }

    func test_widthChangeDuringATransitionRedirectsToTheNewGeometry() {
        let controller = makeFloatingController()

        controller.selectTab(withIdentifier: "t3", animated: true)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 844)
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        assertIndicatorCentred(on: "t3", in: controller)
    }

    // MARK: 沒有動畫的路徑

    func test_unanimatedSelectionPlacesTheIndicatorImmediately() {
        let controller = makeFloatingController()

        controller.selectTab(withIdentifier: "t4", animated: false)
        controller.view.layoutIfNeeded()

        assertIndicatorCentred(on: "t4", in: controller)
    }

    func test_reduceMotionDoesNotLeaveTheIndicatorBehind() {
        overrideAccessibility(reduceMotion: true)
        let controller = makeFloatingController {
            $0.motion.reduceMotionBehavior = .instant
        }

        controller.selectTab(withIdentifier: "t2", animated: true)

        assertIndicatorCentred(on: "t2", in: controller)
        XCTAssertEqual(indicator(in: controller)?.alpha, 1)
    }
    // MARK: - 材質決定移動中有沒有玻璃

    private func makeMaterialController(
        _ material: TeroTabSelectionIndicatorMaterial
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.itemAppearance.selectionIndicatorStyle = .always
        configuration.itemAppearance.selectionIndicatorMaterial = material
        let controller = makeController(configuration: configuration)
        let tabs = (0..<4).map { index in
            TeroTab(identifier: "t\(index)", viewController: UIViewController(),
                    item: TeroTabItem(title: "T\(index)", image: nil, selectedImage: nil))
        }
        controller.setTabs(tabs, selectedIdentifier: "t0", animated: false)
        present(controller)
        return controller
    }

    private var isFloatingAvailable: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    /// 透鏡是 Bar 的**直接** subview；靜止的選取外框巢在膠囊裡面。
    private func lens(in controller: TeroTabBarController) -> TeroTabSelectionIndicatorView? {
        controller.tabBar.subviews.compactMap { $0 as? TeroTabSelectionIndicatorView }.first
    }


    /// `.solid` 的文件說「一律使用實色」。透鏡是一片會飛過去的玻璃，所以「一律」
    /// 必須連動態那一片也關掉——否則選了 `.solid` 的人靜止時拿到實色、移動中仍然
    /// 看到玻璃，而 `.solid` 是唯一能表達「不要玻璃」的值，沒有別的出口。
    func test_solidMaterialShowsNoLensWhileTheSelectionMoves() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMaterialController(.solid)

        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        XCTAssertTrue(lens(in: controller)?.isHidden ?? true,
                      "選了 solid 就不該有玻璃飛過去")
    }

    /// 對照：`.automatic` 的透鏡必須還在，否則上面那條測的是「透鏡壞了」。
    func test_automaticMaterialStillShowsTheLensWhileTheSelectionMoves() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMaterialController(.automatic)

        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        let lensView = try XCTUnwrap(lens(in: controller))
        XCTAssertFalse(lensView.isHidden, "automatic 的動態玻璃由透鏡負責，不能一起關掉")
    }

    func test_solidMaterialStillShowsTheSelectionItself() throws {
        try XCTSkipUnless(isFloatingAvailable)
        let controller = makeMaterialController(.solid)

        controller.selectTab(withIdentifier: "t2", animated: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.12))

        let indicator = try XCTUnwrap(indicator(in: controller))
        XCTAssertFalse(indicator.isHidden, "關掉的是玻璃，不是選取狀態")
        XCTAssertEqual(indicator.alpha, 1)
    }

}
