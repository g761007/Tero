import XCTest
@testable import Tero

final class ScrollInputTests: TeroTabBarControllerTestCase {
    func test_programmaticOffsetDoesNotCollapseButProgrammaticTopRestores() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        scroll.contentSize.height = 2000
        let tracker = TeroTabScrollTracker()
        tracker.configuration = .init(behavior: .minimizeOnScrollDown)
        tracker.track(scroll, resetTo: .expanded)
        scroll.contentOffset.y = 500
        XCTAssertEqual(tracker.state, .expanded)
        tracker.reset(to: .minimized)
        scroll.contentOffset.y = 0
        XCTAssertEqual(tracker.state, .expanded)
    }

    func test_geometryAndProgrammaticChangesDuringDraggingDoNotAccumulate() {
        var machine = TeroTabScrollStateMachine()
        machine.reset(to: .expanded, offset: 100)
        let config = TeroTabScrollStateMachine.Configuration(behavior: .minimizeOnScrollDown)
        var sample = TeroTabScrollSample(offset: 500, maximumOffset: 2000, velocity: 1000)
        sample.geometryChanged = true
        XCTAssertEqual(machine.consume(sample, configuration: config), .expanded)
        sample.geometryChanged = false
        sample.offset = 503
        sample.velocity = 0
        XCTAssertEqual(machine.consume(sample, configuration: config), .expanded)
    }

    func test_velocityCannotBypassDirectionLockAndBottomReboundDoesNotRestore() {
        var machine = TeroTabScrollStateMachine()
        let config = TeroTabScrollStateMachine.Configuration(behavior: .minimizeOnScrollDown)
        for offset: CGFloat in [1, 2, 1, 3] {
            XCTAssertEqual(machine.consume(.init(offset: offset, maximumOffset: 1000, velocity: 900), configuration: config), .expanded)
        }
        XCTAssertEqual(machine.consume(.init(offset: 900, maximumOffset: 1000), configuration: config), .minimized)
        for offset: CGFloat in [1030, 1010, 1000] {
            XCTAssertEqual(machine.consume(.init(offset: offset, maximumOffset: 1000, velocity: -900), configuration: config), .minimized)
        }
    }

    func test_refreshAndNonScrollableContentExpandWithoutLockOverride() {
        var machine = TeroTabScrollStateMachine()
        machine.reset(to: .minimized)
        let config = TeroTabScrollStateMachine.Configuration(behavior: .minimizeOnScrollDown)
        var sample = TeroTabScrollSample(offset: 100, maximumOffset: 500)
        sample.isRefreshing = true
        XCTAssertEqual(machine.consume(sample, configuration: config), .expanded)
        machine.reset(to: .hidden)
        machine.isLocked = true
        XCTAssertEqual(machine.consume(sample, configuration: config), .hidden)
    }

    func test_insetContributionPreservesConsumerInsetsAndIsRemovedOnDetach() {
        let child = UIViewController()
        child.additionalSafeAreaInsets.bottom = 17
        let controller = makeController()
        let tab = TeroTab(identifier: "feed", viewController: child, item: TeroTabItem(title: "Feed", image: nil, selectedImage: nil))
        controller.setTabs([tab], selectedIdentifier: nil, animated: false)
        present(controller)
        let expanded = child.additionalSafeAreaInsets.bottom
        XCTAssertGreaterThan(expanded, 17)
        controller.applyScrollDrivenPresentationState(.hidden, animated: false)
        controller.viewSafeAreaInsetsDidChange()
        XCTAssertEqual(child.additionalSafeAreaInsets.bottom, expanded)
        controller.setTabBarPresentationState(.hidden, animated: false)
        XCTAssertEqual(child.additionalSafeAreaInsets.bottom, 17)
        controller.setTabs([], selectedIdentifier: nil, animated: false)
        XCTAssertEqual(child.additionalSafeAreaInsets.bottom, 17)
    }
}
