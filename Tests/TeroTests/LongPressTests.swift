import XCTest
import UIKit
@testable import Tero

/// 可以被指定 state 與位置的長按辨識器。
///
/// 與 `SwipeSelectionTests` 的 `FakeDragRecognizer` 同一個理由：合成觸控驅動不了真的
/// 長按，但 `handleLongPress` 的**內容**只依賴 `state` 與 `location(in:)`。
private final class FakeLongPressRecognizer: UILongPressGestureRecognizer {
    var stubbedState: UIGestureRecognizer.State = .began
    var stubbedLocation: CGPoint = .zero
    override var state: UIGestureRecognizer.State {
        get { stubbedState }
        set { stubbedState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { stubbedLocation }
}

/// 只聽長按的 delegate。
private final class LongPressRecorder: NSObject, TeroTabBarControllerDelegate {
    var pressed: [String] = []
    func teroTabBarController(_ tabController: TeroTabBarController, didLongPress tab: TeroTab) {
        pressed.append(tab.identifier)
    }
}

/// 什麼都不實作的 delegate。
private final class DeafDelegate: NSObject, TeroTabBarControllerDelegate {}

/// issue #96：Tab Item 長按事件。
final class LongPressTests: TeroTabBarControllerTestCase {

    private var listener: LongPressRecorder!

    override func setUp() {
        super.setUp()
        listener = LongPressRecorder()
    }

    override func tearDown() {
        listener = nil
        super.tearDown()
    }

    private func makeListeningController(
        tabs identifiers: [String] = ["a", "b", "c"],
        configure: (TeroTabBarConfiguration) -> Void = { _ in }
    ) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configure(configuration)
        let controller = makeController(configuration: configuration)
        controller.delegate = listener
        controller.setTabs(identifiers.map { makeTab($0) }, selectedIdentifier: identifiers.first, animated: false)
        present(controller)
        return controller
    }

    /// 手指落在某個控制項的中央。控制項是 items 容器的直接子視圖，frame 就是那個座標系。
    private func press(_ identifier: String, in controller: TeroTabBarController,
                       state: UIGestureRecognizer.State = .began) {
        guard let control = tabBarControl(for: identifier, in: controller) else {
            return XCTFail("找不到 \(identifier)")
        }
        let recognizer = FakeLongPressRecognizer()
        recognizer.stubbedState = state
        recognizer.stubbedLocation = CGPoint(x: control.frame.midX, y: control.frame.midY)
        controller.tabBar.simulateLongPress(recognizer)
    }

    func test_aLongPressOnATabReachesTheDelegate() {
        let controller = makeListeningController()

        press("b", in: controller)

        XCTAssertEqual(listener.pressed, ["b"])
        XCTAssertEqual(controller.selectedTab?.identifier, "a", "長按不改選取")
    }

    func test_onlyTheBeganStateFires() {
        let controller = makeListeningController()

        press("b", in: controller, state: .changed)
        press("b", in: controller, state: .ended)

        XCTAssertTrue(listener.pressed.isEmpty, "手指停留與放開都不再發，一次長按一個事件")
    }

    func test_aLongPressOnADisabledTabIsNotDelivered() {
        let controller = makeListeningController()
        controller.tabs[1].item.isEnabled = false
        controller.reloadAllTabs(animated: false)
        controller.view.layoutIfNeeded()

        forceTapTabBarItem("b", in: controller)  // 前提：停用的格連點擊都不選
        press("b", in: controller)

        XCTAssertTrue(listener.pressed.isEmpty)
    }

    func test_aLongPressOnMoreIsNotDelivered() {
        let controller = makeListeningController(tabs: ["a", "b", "c", "d", "e", "f", "g"]) {
            $0.compact.maximumVisibleItems = 4
        }
        XCTAssertNotNil(tabBarControl(for: "more", in: controller), "前提：有 More")

        press("more", in: controller)

        XCTAssertTrue(listener.pressed.isEmpty, "More 不是 Tab")
    }

    func test_dragModeSwallowsLongPresses() {
        let controller = makeListeningController {
            $0.swipeSelectionMode = .drag
            $0.itemAppearance.selectionIndicatorStyle = .always
        }
        XCTAssertTrue(controller.tabBar.isLongPressEnabled, "delegate 有聽")

        press("b", in: controller)

        XCTAssertTrue(listener.pressed.isEmpty, "`.drag` 由零秒長按驅動，半秒的那個等不到")
    }

    func test_nothingListensWhileTheDelegateDoesNotImplementIt() {
        let controller = makeListeningController()
        let deaf = DeafDelegate()

        controller.delegate = deaf
        XCTAssertFalse(controller.tabBar.isLongPressEnabled, "沒有人聽就不攔手勢")
        press("b", in: controller)
        XCTAssertTrue(listener.pressed.isEmpty)

        controller.delegate = listener
        XCTAssertTrue(controller.tabBar.isLongPressEnabled, "換回有聽的 delegate 就重新啟用")
    }
}
