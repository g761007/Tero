import XCTest
@testable import Tero

/// 對應 ticket #40 的彈簧換算。純運算，不需要真的跑一次動畫再量結果。
final class SpringDescriptionTests: XCTestCase {

    func test_stiffnessFollowsTheSquareOfAngularFrequency() {
        // ω = 2π / response；stiffness = m·ω²
        let spring = TeroTabSpring.description(response: 0.5, dampingRatio: 1)
        let omega = 2 * CGFloat.pi / 0.5

        XCTAssertEqual(spring.mass, 1)
        XCTAssertEqual(spring.stiffness, omega * omega, accuracy: 0.0001)
    }

    func test_dampingFollowsTheRatio() {
        // damping = 2·ζ·m·ω
        let omega = 2 * CGFloat.pi / 0.5
        let critical = TeroTabSpring.description(response: 0.5, dampingRatio: 1)
        let underdamped = TeroTabSpring.description(response: 0.5, dampingRatio: 0.5)

        XCTAssertEqual(critical.damping, 2 * omega, accuracy: 0.0001)
        XCTAssertEqual(underdamped.damping, omega, accuracy: 0.0001)
    }

    func test_fasterResponseMeansStifferSpring() {
        let fast = TeroTabSpring.description(response: 0.2, dampingRatio: 0.8)
        let slow = TeroTabSpring.description(response: 0.8, dampingRatio: 0.8)

        XCTAssertGreaterThan(fast.stiffness, slow.stiffness)
    }

    func test_criticalDampingIsTheRatioOfOne() {
        // 臨界阻尼的定義：c = 2·√(m·k)
        let spring = TeroTabSpring.description(response: 0.35, dampingRatio: 1)

        XCTAssertEqual(spring.damping, 2 * sqrt(spring.mass * spring.stiffness), accuracy: 0.0001)
    }

    func test_zeroResponseIsClampedInsteadOfDiverging() {
        let spring = TeroTabSpring.description(response: 0, dampingRatio: 0.8)

        XCTAssertTrue(spring.stiffness.isFinite)
        XCTAssertGreaterThan(spring.stiffness, 0)
    }

    func test_negativeResponseIsClamped() {
        let clamped = TeroTabSpring.description(response: -1, dampingRatio: 0.8)
        let minimum = TeroTabSpring.description(
            response: TeroTabSpring.minimumResponse,
            dampingRatio: 0.8
        )

        XCTAssertEqual(clamped, minimum)
    }

    func test_dampingRatioIsClampedToASensibleRange() {
        let tooLow = TeroTabSpring.description(response: 0.4, dampingRatio: -5)
        let tooHigh = TeroTabSpring.description(response: 0.4, dampingRatio: 99)
        let low = TeroTabSpring.description(
            response: 0.4,
            dampingRatio: TeroTabSpring.dampingRatioRange.lowerBound
        )
        let high = TeroTabSpring.description(
            response: 0.4,
            dampingRatio: TeroTabSpring.dampingRatioRange.upperBound
        )

        XCTAssertEqual(tooLow, low)
        XCTAssertEqual(tooHigh, high)
    }

    func test_nominalDurationPrefersResponseWhenPresent() {
        var motion = TeroTabMotionConfiguration()
        motion.selectionResponse = 0.25
        motion.selectionDuration = 9

        XCTAssertEqual(TeroTabSpring.nominalDuration(for: motion), 0.25)
    }

    func test_nominalDurationFallsBackToDurationWhenResponseIsNil() {
        var motion = TeroTabMotionConfiguration()
        motion.selectionResponse = nil
        motion.selectionDuration = 0.6

        XCTAssertEqual(TeroTabSpring.nominalDuration(for: motion), 0.6)
    }
}


/// Motion 設定本身的擁有權語意，與其他設定一致（見 ConfigurationOwnershipTests）。
final class MotionConfigurationOwnershipTests: TeroTabBarControllerTestCase {

    func test_motionSurvivesTheConfigurationCopy() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.motion.selectionResponse = 0.123
        configuration.motion.allowsInterruptibleTransition = false

        let copy = configuration.copy() as! TeroTabBarConfiguration

        XCTAssertEqual(copy.motion.selectionResponse, 0.123)
        XCTAssertFalse(copy.motion.allowsInterruptibleTransition)
    }

    func test_mutatingTheOriginalDoesNotReachTheController() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        let controller = makeController(configuration: configuration)

        configuration.motion.selectionResponse = 0.999

        XCTAssertNotEqual(controller.currentConfiguration().motion.selectionResponse, 0.999)
    }

    func test_mutatingTheSnapshotDoesNotReachTheController() {
        let controller = makeController()

        let snapshot = controller.currentConfiguration()
        snapshot.motion.reselectDuration = 5

        XCTAssertNotEqual(controller.currentConfiguration().motion.reselectDuration, 5)
    }
}
