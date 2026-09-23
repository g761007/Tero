import XCTest
@testable import Tero

/// 對應 ticket #29。這是 spec 指定的第二個 seam：純邏輯，不建立任何視圖、不依賴時間。
final class ScrollStateMachineTests: XCTestCase {

    private let maximum: CGFloat = 2000

    private func makeMachine(
        _ behavior: TeroTabBarScrollBehavior,
        down: CGFloat = 40,
        up: CGFloat = 24,
        velocity: CGFloat = 120
    ) -> (TeroTabScrollStateMachine, TeroTabScrollStateMachine.Configuration) {
        var machine = TeroTabScrollStateMachine()
        machine.reset(to: .expanded, offset: 0)
        let configuration = TeroTabScrollStateMachine.Configuration(
            behavior: behavior,
            downwardTranslationThreshold: down,
            upwardTranslationThreshold: up,
            velocityThreshold: velocity
        )
        return (machine, configuration)
    }

    private func feed(
        _ machine: inout TeroTabScrollStateMachine,
        _ configuration: TeroTabScrollStateMachine.Configuration,
        offsets: [CGFloat],
        velocity: CGFloat = 0
    ) -> [TeroTabBarPresentationState] {
        offsets.map { offset in
            machine.consume(
                TeroTabScrollSample(offset: offset, maximumOffset: maximum, velocity: velocity),
                configuration: configuration
            )
        }
    }

    // MARK: 起始狀態

    func test_startsExpanded() {
        let (machine, _) = makeMachine(.hideOnScrollDown)
        XCTAssertEqual(machine.state, .expanded)
    }

    // MARK: 方向與位移門檻

    func test_scrollingDownPastThresholdCollapses() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 40)

        let states = feed(&machine, configuration, offsets: [10, 20, 39, 41])

        XCTAssertEqual(states, [.expanded, .expanded, .expanded, .hidden])
    }

    func test_scrollingDownBelowThresholdDoesNothing() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 40)

        _ = feed(&machine, configuration, offsets: [10, 20, 30, 39])

        XCTAssertEqual(machine.state, .expanded)
    }

    func test_scrollingUpPastThresholdExpands() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 40, up: 24)
        _ = feed(&machine, configuration, offsets: [50, 100])
        XCTAssertEqual(machine.state, .hidden)

        let states = feed(&machine, configuration, offsets: [90, 80, 75])

        XCTAssertEqual(states.last, .expanded, "100 → 75 已超過向上門檻 24")
    }

    func test_scrollingUpBelowThresholdKeepsCollapsed() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, up: 24)
        _ = feed(&machine, configuration, offsets: [50, 100])

        _ = feed(&machine, configuration, offsets: [95, 90])

        XCTAssertEqual(machine.state, .hidden, "只回捲 10 點，不足以展開")
    }

    /// 位移門檻必須從轉向點起算，否則在中途反向的手勢會誤判。
    func test_thresholdIsMeasuredFromTheTurningPoint() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 40, up: 24)
        _ = feed(&machine, configuration, offsets: [200, 400])
        XCTAssertEqual(machine.state, .hidden)

        // 從 400 往上回 20（未達 24），再往下 20（未達 40）→ 都不該改變狀態
        _ = feed(&machine, configuration, offsets: [380])
        XCTAssertEqual(machine.state, .hidden)
        _ = feed(&machine, configuration, offsets: [400])
        XCTAssertEqual(machine.state, .hidden)
    }

    // MARK: 速度門檻

    func test_fastFlickDownCollapsesBeforeThreshold() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 400, velocity: 100)

        let states = feed(&machine, configuration, offsets: [10, 20], velocity: 500)

        XCTAssertEqual(states.last, .hidden, "速度超過門檻時不必等位移")
    }

    func test_fastFlickUpExpandsBeforeThreshold() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 40, up: 400, velocity: 100)
        _ = feed(&machine, configuration, offsets: [200, 400])
        XCTAssertEqual(machine.state, .hidden)

        let states = feed(&machine, configuration, offsets: [390], velocity: -500)

        XCTAssertEqual(states.last, .expanded)
    }

    func test_velocityBelowThresholdIsIgnored() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 400, velocity: 600)

        _ = feed(&machine, configuration, offsets: [10, 20, 30], velocity: 500)

        XCTAssertEqual(machine.state, .expanded)
    }

    // MARK: 回彈

    func test_reboundAtTopForcesExpanded() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown)
        _ = feed(&machine, configuration, offsets: [200, 400])
        XCTAssertEqual(machine.state, .hidden)

        // 往上拉過頭
        let states = feed(&machine, configuration, offsets: [-30])

        XCTAssertEqual(states.last, .expanded)
    }

    func test_reboundAtBottomDoesNotChangeState() {
        var (machine, configuration) = makeMachine(.minimizeOnScrollDown, down: 40)
        _ = feed(&machine, configuration, offsets: [1000, 1900])
        XCTAssertEqual(machine.state, .minimized)

        // 拉過底部：不該把狀態再往下推，也不該展開
        let before = machine.state
        let states = feed(&machine, configuration, offsets: [2050, 2100])

        XCTAssertEqual(states, [before, before])
    }

    func test_reboundAtBottomWhileExpandedStaysExpanded() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 4000)

        let states = feed(&machine, configuration, offsets: [2050, 2100])

        XCTAssertEqual(states, [.expanded, .expanded])
    }

    // MARK: 回到頂部

    func test_returningToTopForcesExpanded() {
        var (machine, configuration) = makeMachine(.minimizeOnScrollDown)
        _ = feed(&machine, configuration, offsets: [200, 400])
        XCTAssertEqual(machine.state, .minimized)

        let states = feed(&machine, configuration, offsets: [0])

        XCTAssertEqual(states.last, .expanded)
    }

    // MARK: 行為

    func test_hideBehaviorCollapsesToHidden() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown)
        _ = feed(&machine, configuration, offsets: [100, 200])
        XCTAssertEqual(machine.state, .hidden)
    }

    func test_minimizeBehaviorCollapsesToMinimized() {
        var (machine, configuration) = makeMachine(.minimizeOnScrollDown)
        _ = feed(&machine, configuration, offsets: [100, 200])
        XCTAssertEqual(machine.state, .minimized)
    }

    func test_noneBehaviorNeverChangesState() {
        var (machine, configuration) = makeMachine(TeroTabBarScrollBehavior.none)

        let states = feed(&machine, configuration, offsets: [100, 400, 1000, 0, -50], velocity: 900)

        XCTAssertEqual(Set(states), [.expanded], "`.none` 下捲動完全不影響狀態")
    }

    // MARK: 鎖定

    func test_lockedMachineIgnoresEverything() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown)
        machine.reset(to: .hidden, offset: 500)
        machine.isLocked = true

        let states = feed(&machine, configuration, offsets: [400, 300, 0, -50], velocity: -900)

        XCTAssertEqual(Set(states), [.hidden], "鎖定期間連回到頂部也不展開")
    }

    func test_unlockingRestoresScrollControl() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown)
        machine.reset(to: .hidden, offset: 500)
        machine.isLocked = true
        _ = feed(&machine, configuration, offsets: [0])
        XCTAssertEqual(machine.state, .hidden)

        machine.isLocked = false
        machine.reset(to: .expanded, offset: 0)
        let states = feed(&machine, configuration, offsets: [100, 200])

        XCTAssertEqual(states.last, .hidden, "解鎖後捲動應重新生效")
    }

    // MARK: 重設

    func test_resetClearsDirectionAndAnchor() {
        var (machine, configuration) = makeMachine(.hideOnScrollDown, down: 40)
        _ = feed(&machine, configuration, offsets: [10, 20, 30])

        machine.reset(to: .expanded, offset: 30)
        _ = feed(&machine, configuration, offsets: [50])

        XCTAssertEqual(machine.state, .expanded, "重設之後門檻從新的錨點起算")
    }
}

/// 行為解析的優先順序（計畫書 §38）。
final class ScrollBehaviorResolverTests: XCTestCase {

    private let resolver = TeroTabScrollBehaviorResolver()

    func test_visibleViewControllerPreferenceWins() {
        let result = resolver.resolve(
            preferred: .minimizeOnScrollDown,
            configured: TeroTabBarScrollBehavior.none,
            style: .floatingGlass
        )
        XCTAssertEqual(result, .minimizeOnScrollDown)
    }

    func test_configurationIsUsedWhenNoPreference() {
        let result = resolver.resolve(
            preferred: nil,
            configured: .hideOnScrollDown,
            style: .floatingGlass
        )
        XCTAssertEqual(result, .hideOnScrollDown)
    }

    func test_classicDowngradesMinimizeToHide() {
        XCTAssertEqual(
            resolver.resolve(preferred: .minimizeOnScrollDown, configured: TeroTabBarScrollBehavior.none, style: .classic),
            .hideOnScrollDown
        )
        XCTAssertEqual(
            resolver.resolve(preferred: nil, configured: .minimizeOnScrollDown, style: .classic),
            .hideOnScrollDown
        )
    }

    func test_classicKeepsHideAndNone() {
        XCTAssertEqual(
            resolver.resolve(preferred: nil, configured: .hideOnScrollDown, style: .classic),
            .hideOnScrollDown
        )
        XCTAssertEqual(
            resolver.resolve(preferred: nil, configured: TeroTabBarScrollBehavior.none, style: .classic),
            TeroTabBarScrollBehavior.none
        )
    }

    func test_floatingGlassKeepsMinimize() {
        XCTAssertEqual(
            resolver.resolve(preferred: nil, configured: .minimizeOnScrollDown, style: .floatingGlass),
            .minimizeOnScrollDown
        )
    }
}
