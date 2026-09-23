import XCTest
@testable import Tero

/// Phase 7：頂部 chrome 的捲動政策。
///
/// 純值型別，落在 seam 2——輸入取樣序列、斷言輸出進度，不建任何 view。
/// 這與 `ScrollStateMachineTests` 是同一種寫法。
final class ChromeScrollPolicyTests: XCTestCase {

    private func sample(
        _ offset: CGFloat,
        maximum: CGFloat = 2000,
        velocity: CGFloat = 0,
        userDriven: Bool = true,
        refreshing: Bool = false,
        geometryChanged: Bool = false
    ) -> TeroTabScrollSample {
        var s = TeroTabScrollSample(offset: offset, maximumOffset: maximum, velocity: velocity)
        s.isUserDriven = userDriven
        s.isRefreshing = refreshing
        s.geometryChanged = geometryChanged
        return s
    }

    private let config = TeroChromeScrollPolicy.Configuration(
        behavior: .hidePrimary, collapseDistance: 100, directionLockDistance: 8
    )

    // MARK: - 收合

    func test_scrollingDownPastTheLockDistanceStartsCollapsing() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)

        policy.consume(sample(110), configuration: config)
        let progress = policy.consume(sample(150), configuration: config)

        XCTAssertGreaterThan(progress, 0)
        XCTAssertLessThan(progress, 1)
    }

    func test_scrollingTheFullCollapseDistanceReachesOne() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)
        policy.consume(sample(110), configuration: config)

        let progress = policy.consume(sample(250), configuration: config)

        XCTAssertEqual(progress, 1)
    }

    func test_progressNeverExceedsOne() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)
        policy.consume(sample(110), configuration: config)

        // 走 1400pt，是 collapseDistance 的十四倍——但仍在內容範圍內，
        // 否則會先被底部 overscroll 的排除規則接走。
        let progress = policy.consume(sample(1500), configuration: config)

        XCTAssertEqual(progress, 1, "夾住，不是讓它繼續長")
    }

    func test_shortMovementWithinTheLockDistanceDoesNothing() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)

        let progress = policy.consume(sample(104), configuration: config)

        XCTAssertEqual(progress, 0, "沒過鎖距就沒有方向，也就沒有進度")
    }

    // MARK: - 回頂與排除的輸入

    func test_returningToTheTopExpandsImmediately() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)
        policy.consume(sample(110), configuration: config)
        policy.consume(sample(250), configuration: config)

        let progress = policy.consume(sample(0), configuration: config)

        XCTAssertEqual(progress, 0)
    }

    func test_refreshingKeepsTheChromeExpanded() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)
        policy.consume(sample(110), configuration: config)
        policy.consume(sample(250), configuration: config)

        let progress = policy.consume(sample(200, refreshing: true), configuration: config)

        XCTAssertEqual(progress, 0, "下拉刷新不是「想收起 chrome」的訊號")
    }

    func test_programmaticScrollingDoesNotCollapse() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)

        policy.consume(sample(110, userDriven: false), configuration: config)
        let progress = policy.consume(sample(300, userDriven: false), configuration: config)

        XCTAssertEqual(progress, 0, "程式捲動不觸發收合，與 Tab Bar 那側一致")
    }

    func test_geometryChangeRebasesInsteadOfCollapsing() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)

        let progress = policy.consume(sample(400, geometryChanged: true), configuration: config)

        XCTAssertEqual(progress, 0, "版面改變造成的位移不是使用者捲動")
    }

    func test_bottomOverscrollDoesNotExpand() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)
        policy.consume(sample(110), configuration: config)
        policy.consume(sample(250), configuration: config)
        let collapsed = policy.progress

        let progress = policy.consume(sample(2100, maximum: 2000), configuration: config)

        XCTAssertEqual(progress, collapsed, "底部回彈不該把 chrome 展開")
    }

    // MARK: - 反向

    func test_scrollingBackUpExpandsAgain() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)
        policy.consume(sample(110), configuration: config)
        policy.consume(sample(250), configuration: config)
        XCTAssertEqual(policy.progress, 1)

        policy.consume(sample(240), configuration: config)
        let progress = policy.consume(sample(180), configuration: config)

        XCTAssertLessThan(progress, 1, "往回捲要重新展開")
    }

    // MARK: - fixed

    func test_fixedBehaviorNeverCollapses() {
        var policy = TeroChromeScrollPolicy()
        policy.reset(offset: 100)
        let fixed = TeroChromeScrollPolicy.Configuration(behavior: .fixed, collapseDistance: 100)

        policy.consume(sample(110), configuration: fixed)
        let progress = policy.consume(sample(500), configuration: fixed)

        XCTAssertEqual(progress, 0)
    }

    // MARK: - 與 Tab Bar 的獨立性（§26）

    func test_theChromePolicyAndTheTabBarMachineCanDisagree() {
        var chrome = TeroChromeScrollPolicy()
        chrome.reset(offset: 100)
        var tabBar = TeroTabScrollStateMachine()
        tabBar.reset(to: .expanded, offset: 100)
        let tabConfig = TeroTabScrollStateMachine.Configuration(behavior: .none)

        chrome.consume(sample(110), configuration: config)
        chrome.consume(sample(250), configuration: config)
        tabBar.consume(sample(110), configuration: tabConfig)
        let tabState = tabBar.consume(sample(250), configuration: tabConfig)

        XCTAssertEqual(chrome.progress, 1, "頂部收起來了")
        XCTAssertEqual(tabState, .expanded, "底部沒有——兩套 policy 互不相干（§26）")
    }
}
