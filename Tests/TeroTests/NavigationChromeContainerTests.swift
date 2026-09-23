import XCTest
import UIKit
@testable import Tero

/// 依 B17 選項 A 提供 chrome 的測試頁面：Tero 只認得一個 view 與一條進度。
private final class ChromePage: UIViewController, TeroNavigationChromeProviding {
    let name: String
    private(set) var makeCallCount = 0
    private(set) var progressSamples: [CGFloat] = []
    func resetProgressSamples() { progressSamples.removeAll() }
    var expandedHeight: CGFloat
    let collapsedHeight: CGFloat?

    init(name: String, expanded: CGFloat = 96, collapsed: CGFloat? = 44) {
        self.name = name
        self.expandedHeight = expanded
        self.collapsedHeight = collapsed
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private(set) weak var madeView: UIView?
    func makeTeroNavigationChromeView() -> UIView {
        makeCallCount += 1
        let view = UIView()
        view.accessibilityIdentifier = "chrome.\(name)"
        madeView = view
        return view
    }
    var teroNavigationChromeHeight: CGFloat { expandedHeight }
    var teroNavigationChromeCollapsedHeight: CGFloat { collapsedHeight ?? expandedHeight }
    func updateTeroNavigationChrome(_ chromeView: UIView, collapseProgress: CGFloat) {
        progressSamples.append(collapseProgress)
    }
}

/// 有 chrome、也交出捲動視圖的頁面。
private final class ScrollingChromePage: UIViewController, TeroNavigationChromeProviding, TeroScrollProviding {
    let scrollView = UIScrollView()
    var teroTrackingScrollView: UIScrollView? { scrollView }
    func makeTeroNavigationChromeView() -> UIView { UIView() }
    var teroNavigationChromeHeight: CGFloat { 44 }
}

/// Phase 4：Chrome Container。
final class NavigationChromeContainerTests: TeroTabBarControllerTestCase {

    private func presented(_ root: UIViewController) -> TeroNavigationContainer {
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = 0.2
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        return container
    }

    private func chromeView(named name: String, in container: TeroNavigationContainer) -> UIView? {
        container.view.subviews
            .flatMap { $0.subviews }
            .first { $0.accessibilityIdentifier == "chrome.\(name)" }
    }

    // MARK: - 安裝

    func test_theTopPageChromeIsInstalled() {
        let root = ChromePage(name: "root")
        let container = presented(root)

        XCTAssertNotNil(chromeView(named: "root", in: container))
        XCTAssertEqual(root.makeCallCount, 1)
    }

    func test_aPageWithoutChrome_reservesNoHeight() {
        let container = presented(LifecycleSpyViewController(name: "plain", log: log))

        XCTAssertNil(chromeView(named: "plain", in: container))
    }

    func test_pushingAChromePage_replacesTheVisibleChrome() {
        let container = presented(ChromePage(name: "root"))
        container.pushViewController(ChromePage(name: "detail"), animated: false)

        XCTAssertNotNil(chromeView(named: "detail", in: container))
        XCTAssertNil(chromeView(named: "root", in: container), "只有 top 的 chrome 在容器裡")
    }

    func test_chromeIsBuiltOnceEvenAcrossRepeatedLayout() {
        let root = ChromePage(name: "root")
        let container = presented(root)
        container.view.layoutIfNeeded()
        container.view.layoutIfNeeded()

        XCTAssertEqual(root.makeCallCount, 1, "只有 provider 參考變更才重建（ADR-0005）")
    }

    // MARK: - B17：chrome 綁 containment，不綁 stack

    func test_duringAnInteractivePop_thePageBeingDraggedInAlreadyHasItsChrome() {
        let root = ChromePage(name: "root")
        let container = presented(root)
        container.pushViewController(ChromePage(name: "detail"), animated: false)

        container.beginInteractivePop()

        XCTAssertEqual(root.makeCallCount, 1, "手勢一開始就建好，不是等 finish 才憑空出現")
        container.endInteractivePop(progress: 0, velocity: 0)
        waitUntil("手勢結算") { container.transitionState == .idle }
    }

    func test_afterAPageLeavesTheHierarchy_itsChromeIsReleased() {
        let container = presented(ChromePage(name: "root"))
        let detail = ChromePage(name: "detail")
        container.pushViewController(detail, animated: false)
        container.popViewController(animated: false)

        XCTAssertNil(chromeView(named: "detail", in: container))
    }

    // MARK: - B18：高度是設定值，兩端點內插

    func test_theCollapseProgressIsForwardedToTheProvider() {
        let root = ChromePage(name: "root")
        let container = presented(root)
        root.resetProgressSamples()

        container.chromeCollapseProgress = 0.5

        XCTAssertEqual(root.progressSamples.last, 0.5)
    }

    func test_theProgressIsClampedToZeroAndOne() {
        let root = ChromePage(name: "root")
        let container = presented(root)
        root.resetProgressSamples()

        container.chromeCollapseProgress = 2.0

        XCTAssertEqual(root.progressSamples.last, 1.0, "超出範圍要夾住，不是原封轉送")
    }

    func test_aPageThatDoesNotCollapse_keepsItsHeightAtEveryProgress() {
        let root = ChromePage(name: "root", expanded: 80, collapsed: 80)
        let container = presented(root)
        let before = chromeView(named: "root", in: container)?.superview?.bounds.height

        container.chromeCollapseProgress = 1.0
        container.view.layoutIfNeeded()

        XCTAssertEqual(chromeView(named: "root", in: container)?.superview?.bounds.height, before)
    }

    // MARK: - chrome 要真的看得見

    /// 保留邊距正確、parent 正確、然後整條 chrome 被內容蓋住——這三件事可以同時成立。
    /// 既有測試只驗前兩件，所以 chrome 從來沒有在真實使用下顯示過而沒有人發現。
    private func chromeIsAboveContent(
        _ container: TeroNavigationContainer,
        chrome page: ChromePage,
        page content: UIViewController
    ) throws -> Bool {
        let chromeView = try XCTUnwrap(page.madeView, "chrome view 沒有被建立")
        let chromeContainer = try XCTUnwrap(chromeView.superview, "chrome view 沒有被裝進容器")
        let subviews = container.view.subviews
        let chromeIndex = try XCTUnwrap(subviews.firstIndex(of: chromeContainer))
        let contentIndex = try XCTUnwrap(subviews.firstIndex(of: content.view))
        return chromeIndex > contentIndex
    }

    func test_rootChromeIsDrawnAboveTheRootContent() throws {
        let root = ChromePage(name: "root")
        let container = presented(root)

        XCTAssertTrue(try chromeIsAboveContent(container, chrome: root, page: root),
                      "內容是滿版不透明的；chrome 排在它下面就等於完全看不到")
    }

    func test_chromeStaysAboveTheContentAfterPushing() throws {
        let root = ChromePage(name: "root")
        let container = presented(root)
        let detail = ChromePage(name: "detail")

        container.pushViewController(detail, animated: false)

        XCTAssertTrue(try chromeIsAboveContent(container, chrome: detail, page: detail),
                      "推進新頁之後也要維持——安裝內容的路徑有四條，全部都得對")
    }

    // MARK: - 轉場期間的 chrome（Phase 15 A1 待驗）

    func test_animatedPush_givesTheIncomingPageItsOwnTopInsetBeforeTheAnimationEnds() {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        let detail = ChromePage(name: "detail", expanded: 44)

        container.pushViewController(detail, animated: true)

        XCTAssertEqual(detail.additionalSafeAreaInsets.top, 44,
                       "commit 之後 topViewController 已經是 detail，內容就該以自己的帶高排版；"
                       + "等到 settle 才寫，使用者會看到結算那一刻跳一下")
    }

    func test_animatedPush_showsTheIncomingPagesChromeBeforeTheAnimationEnds() throws {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        let detail = ChromePage(name: "detail", expanded: 44)

        container.pushViewController(detail, animated: true)

        let chromeView = try XCTUnwrap(detail.madeView, "incoming 的 chrome 還沒被建出來")
        XCTAssertNotNil(chromeView.superview,
                        "動畫期間畫面上掛的應該是 incoming 的 chrome，不是 outgoing 的")
    }

    // MARK: - 轉場中兩頁的 chrome 都在（issue #91）

    func test_animatedPush_keepsBothChromesInTheContainerUntilSettle() throws {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        container.transitionDuration = 1.0
        let detail = ChromePage(name: "detail", expanded: 44)

        container.pushViewController(detail, animated: true)

        let rootChrome = try XCTUnwrap(root.madeView)
        let detailChrome = try XCTUnwrap(detail.madeView)
        XCTAssertNotNil(rootChrome.superview, "離開的那一頁的 chrome 要留到結算，才有東西可以淡出")
        XCTAssertIdentical(rootChrome.superview, detailChrome.superview, "兩個都在同一個容器裡")

        waitUntil("轉場結算") { container.transitionState == .idle }
        XCTAssertNil(rootChrome.superview, "結算後只剩 top 的")
        XCTAssertEqual(detailChrome.alpha, 1)
    }

    func test_interactivePop_crossFadesTheChromesWithTheFinger() throws {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        let detail = ChromePage(name: "detail", expanded: 44)
        container.pushViewController(detail, animated: false)
        let rootChrome = try XCTUnwrap(root.madeView)
        let detailChrome = try XCTUnwrap(detail.madeView)

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.5)
        container.view.layoutIfNeeded()

        XCTAssertEqual(rootChrome.alpha, 0.5, accuracy: 0.001, "下面那一頁的 chrome 跟著手指淡入")
        XCTAssertEqual(detailChrome.alpha, 0.5, accuracy: 0.001, "離開的淡出")
        let expected = container.view.safeAreaInsets.top + (44 + 96) / 2
        XCTAssertEqual(try XCTUnwrap(detailChrome.superview).bounds.height, expected, accuracy: 0.5,
                       "高度在兩頁的帶高之間內插，不是跳過去")

        container.endInteractivePop(progress: 0.5, velocity: 0)
        waitUntil("手勢結算") { container.transitionState == .idle }
    }

    func test_cancelledInteractivePop_restoresTheOutgoingChromeAndRemovesTheIncomingOne() throws {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        let detail = ChromePage(name: "detail", expanded: 44)
        container.pushViewController(detail, animated: false)
        let rootChrome = try XCTUnwrap(root.madeView)
        let detailChrome = try XCTUnwrap(detail.madeView)

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.3)
        container.endInteractivePop(progress: 0.3, velocity: 0)
        waitUntil("手勢結算") { container.transitionState == .idle }

        XCTAssertEqual(detailChrome.alpha, 1, "取消之後留下的那一頁完全可見")
        XCTAssertNil(rootChrome.superview, "被拉出來又收回去的那一頁的 chrome 不能留在容器裡")
        XCTAssertEqual(try XCTUnwrap(detailChrome.superview).bounds.height,
                       container.view.safeAreaInsets.top + 44, accuracy: 0.5)
    }

    func test_finishedInteractivePop_leavesOnlyTheIncomingChrome() throws {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        let detail = ChromePage(name: "detail", expanded: 44)
        container.pushViewController(detail, animated: false)
        let rootChrome = try XCTUnwrap(root.madeView)
        let detailChrome = try XCTUnwrap(detail.madeView)

        container.beginInteractivePop()
        container.endInteractivePop(progress: 0.9, velocity: 0)
        waitUntil("手勢結算") { container.transitionState == .idle }

        XCTAssertNil(detailChrome.superview)
        XCTAssertEqual(rootChrome.alpha, 1)
        XCTAssertEqual(try XCTUnwrap(rootChrome.superview).bounds.height,
                       container.view.safeAreaInsets.top + 96, accuracy: 0.5)
    }

    /// 手勢途中被 push 打斷：被拉出來那一頁的 chrome 不能留下來陪新的轉場。
    func test_aPushDuringAnInteractivePop_doesNotLeaveTheDraggedChromeBehind() throws {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        let detail = ChromePage(name: "detail", expanded: 44)
        container.pushViewController(detail, animated: false)
        let rootChrome = try XCTUnwrap(root.madeView)

        container.beginInteractivePop()
        container.updateInteractivePop(progress: 0.4)
        container.pushViewController(ChromePage(name: "third", expanded: 60), animated: false)

        XCTAssertNil(rootChrome.superview, "root 既不是 top 也不在轉場裡")
        XCTAssertEqual(try XCTUnwrap(detail.madeView).alpha, 1)
    }

    // MARK: - C3：帶高在頁面存活期間會變

    func test_aChangedDeclaredHeightTakesEffectAfterRequestingAGeometryUpdate() {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 96, "前提")

        root.expandedHeight = 140
        container.setNeedsChromeGeometryUpdate()

        XCTAssertEqual(root.additionalSafeAreaInsets.top, 140,
                       "帶高不快取（B18）：字級變大、標題折行、Secondary 列出現，"
                       + "正確的高度都會在頁面存活期間改變")
    }

    // MARK: - 系統的 scroll edge effect（頂部）

    @available(iOS 26, *)
    private func edgeInteraction(
        in container: TeroNavigationContainer
    ) -> UIScrollEdgeElementContainerInteraction? {
        // 互動掛在私有的 chrome 容器上；從 view 階層撈回來，不需要私有存取。
        container.view.subviews
            .flatMap(\.interactions)
            .compactMap { $0 as? UIScrollEdgeElementContainerInteraction }
            .first
    }

    func test_theChromeContainerFeedsTheSystemScrollEdgeEffect() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("UIScrollEdgeElementContainerInteraction 是 iOS 26 API")
        }
        let page = ScrollingChromePage()
        let container = presented(page)

        let interaction = try XCTUnwrap(edgeInteraction(in: container),
                                        "頂部 chrome 少了底部 Tab Bar 已經有的那個效果")

        XCTAssertEqual(interaction.edge, .top, "底部裝 .bottom，頂部要對稱")
        XCTAssertIdentical(interaction.scrollView, page.scrollView,
                           "追蹤對象是這一頁交出來的捲動視圖")
    }

    func test_aPageWithoutChromeInstallsNoScrollEdgeInteraction() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("UIScrollEdgeElementContainerInteraction 是 iOS 26 API")
        }
        let container = presented(UIViewController())

        XCTAssertNil(edgeInteraction(in: container),
                     "沒有 chrome 就沒有邊緣元素；裝著沒事做的互動會改寫容器裡動態色的解析（issue #102）")
    }

    func test_aChromePageWithoutAScrollViewInstallsNoScrollEdgeInteraction() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("UIScrollEdgeElementContainerInteraction 是 iOS 26 API")
        }
        let container = presented(ChromePage(name: "static"))

        XCTAssertNil(edgeInteraction(in: container), "有 chrome 沒有 scroll view，一樣沒有東西可處理")
    }

    /// 實測：互動一裝上，chrome 區裡的 `systemBackground` 會畫成 (245, 245, 245)。
    /// 不透明的 header 要關得掉，而且關掉是真的拆掉互動，不是只把追蹤對象清成 nil。
    func test_theScrollEdgeEffectCanBeTurnedOffAndBackOn() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("UIScrollEdgeElementContainerInteraction 是 iOS 26 API")
        }
        let page = ScrollingChromePage()
        let container = presented(page)
        XCTAssertNotNil(edgeInteraction(in: container), "前提：預設有裝")

        container.isScrollEdgeEffectEnabled = false
        XCTAssertNil(edgeInteraction(in: container), "關掉就拆掉，動態色才會回到內容的解析")

        container.isScrollEdgeEffectEnabled = true
        let reinstalled = try XCTUnwrap(edgeInteraction(in: container), "再開要裝回來")
        XCTAssertIdentical(reinstalled.scrollView, page.scrollView, "而且追蹤對象要重新接上")
    }

    func test_pushingToAPageWithChromeHandsTheEffectTheNewPagesScrollView() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("UIScrollEdgeElementContainerInteraction 是 iOS 26 API")
        }
        let root = ScrollingChromePage()
        let container = presented(root)
        let detail = ScrollingChromePage()

        container.pushViewController(detail, animated: false)

        let interaction = try XCTUnwrap(edgeInteraction(in: container))
        XCTAssertIdentical(interaction.scrollView, detail.scrollView,
                           "換頁之後追蹤對象要跟著換")
    }

    // MARK: - 玻璃按鈕的圖示不得被自己的底蓋住

    /// `applyMaterial()` 用 `insertSubview(at: 0)` 把玻璃底放到最底層——但那一刻
    /// `imageView` 還不存在。UIButton 之後才惰性建立它並插進 index 0，底就被頂到圖示
    /// 上面，圖示變成玻璃裡的折射而不是圖形（實測按鈕內最暗像素 235/255）。
    func test_theGlassBackdropStaysBehindTheButtonsIcon() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("glass 是 iOS 26 材質") }
        guard !TeroAccessibility.isReduceTransparencyEnabled() else {
            throw XCTSkip("降低透明度開啟時不套玻璃")
        }
        let button = TeroNavigationButton(image: UIImage(systemName: "square.and.arrow.up"),
                                          material: .glass)
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)

        button.layoutIfNeeded()

        let backdrop = try XCTUnwrap(button.subviews.first { $0 is UIVisualEffectView },
                                     "玻璃底沒有被建立")
        let icon = try XCTUnwrap(button.imageView, "按鈕沒有 imageView")
        let backdropIndex = try XCTUnwrap(button.subviews.firstIndex(of: backdrop))
        let iconIndex = try XCTUnwrap(button.subviews.firstIndex(of: icon))

        XCTAssertLessThan(backdropIndex, iconIndex,
                          "底要排在圖示之下，否則圖示被自己的材質蓋掉")
    }

    // MARK: - B19 / B11：reserved inset

    func test_theTopPageReceivesTheExpandedHeightAsTopInset() {
        let root = ChromePage(name: "root", expanded: 96)
        _ = presented(root)

        XCTAssertEqual(root.additionalSafeAreaInsets.top, 96)
    }

    func test_theReservedInsetStaysAtTheExpandedHeightWhileCollapsing() {
        let root = ChromePage(name: "root", expanded: 96, collapsed: 44)
        let container = presented(root)

        container.chromeCollapseProgress = 1.0

        XCTAssertEqual(root.additionalSafeAreaInsets.top, 96,
                       "收合時 inset 不跟著變——否則 contentOffset 會變，被判成 user scroll（B19）")
    }

    func test_aPageThatLeavesTheHierarchy_getsItsInsetBack() {
        let container = presented(ChromePage(name: "root"))
        let detail = ChromePage(name: "detail", expanded: 120)
        container.pushViewController(detail, animated: false)
        XCTAssertEqual(detail.additionalSafeAreaInsets.top, 120)

        container.popViewController(animated: false)

        XCTAssertEqual(detail.additionalSafeAreaInsets.top, 0, "離開 children 就歸還（ADR-0004 2.0 修訂）")
    }

    func test_theContainerOnlyAdjustsItsOwnContribution() {
        let root = ChromePage(name: "root", expanded: 96)
        root.additionalSafeAreaInsets = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        _ = presented(root)

        XCTAssertEqual(root.additionalSafeAreaInsets.top, 106, "保留 Consumer 自己設的 10")
    }

    func test_onlyTheTopPageCarriesTheReservedInset() {
        let root = ChromePage(name: "root", expanded: 96)
        let container = presented(root)
        container.pushViewController(ChromePage(name: "detail", expanded: 60), animated: false)

        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, "不是 top 就不佔位")
    }
}

/// Phase 4：預設導覽列。Consumer 可以完全不用它，所以這裡只驗它自己的行為。
final class NavigationBarTests: TeroTabBarControllerTestCase {

    func test_theTitleReachesTheLabel() {
        let bar = TeroNavigationBar()
        bar.title = "Profile"

        let labels = bar.subviews.flatMap { $0.subviews }.compactMap { $0 as? UILabel }
        XCTAssertEqual(labels.first?.text, "Profile")
    }

    func test_leadingAndTrailingItemsAreArranged() {
        let bar = TeroNavigationBar()
        let back = TeroNavigationButton(title: "‹")
        let more = TeroNavigationButton(title: "⋯")

        bar.leadingItems = [back]
        bar.trailingItems = [more]

        XCTAssertIdentical(back.superview?.superview?.superview, bar)
        XCTAssertIdentical(more.superview?.superview?.superview, bar)
    }

    func test_replacingItemsRemovesTheOldOnes() {
        let bar = TeroNavigationBar()
        let first = TeroNavigationButton(title: "a")
        bar.leadingItems = [first]

        bar.leadingItems = [TeroNavigationButton(title: "b")]

        XCTAssertNil(first.superview, "換掉的控制項要離開階層")
    }

    func test_secondaryViewIsOptional() {
        let bar = TeroNavigationBar()
        XCTAssertNil(bar.secondaryView, "§23：Secondary optional")

        let stories = UIView()
        bar.secondaryView = stories

        XCTAssertIdentical(stories.superview?.superview, bar)
    }

    func test_replacingTheSecondaryViewRemovesTheOldOne() {
        let bar = TeroNavigationBar()
        let first = UIView()
        bar.secondaryView = first

        bar.secondaryView = UIView()

        XCTAssertNil(first.superview)
    }

    func test_collapseProgressFadesThePrimaryRowAndLeavesSecondary() {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        let stories = UIView()
        bar.secondaryView = stories
        bar.layoutIfNeeded()

        bar.applyCollapseProgress(1.0)

        let primaryRow = bar.subviews.first { $0.subviews.contains { $0 is UILabel } }
        XCTAssertEqual(primaryRow?.alpha, 0, "§24 的 hidePrimary：Primary 淡出")
        XCTAssertEqual(stories.superview?.alpha, 1, "Secondary 留下")
    }

    /// 「留下」必須是真的拿到空間，不是被擠成 0 然後靠打斷 constraint 畫出來。
    ///
    /// 用 transform 位移看起來一樣對——但 Auto Layout 眼中 Secondary 的高度沒變，
    /// 收合到底就被壓扁，裡面四邊釘死的 view 於是和它衝突。這裡量的是高度。
    /// 長標題不得蓋住兩側控制項。
    func test_aLongTitleStaysClearOfTheLeadingAndTrailingControls() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 390, height: 44))
        bar.leadingItems = [TeroNavigationButton(title: "Back")]
        bar.trailingItems = [TeroNavigationButton(title: "Share")]
        bar.title = String(repeating: "很長的標題", count: 12)
        bar.layoutIfNeeded()

        let label = try XCTUnwrap(
            bar.subviews.flatMap(\.subviews).compactMap { $0 as? UILabel }.first
        )
        let leading = try XCTUnwrap(bar.leadingItems.first)
        let trailing = try XCTUnwrap(bar.trailingItems.first)

        XCTAssertGreaterThanOrEqual(label.frame.minX, leading.convert(leading.bounds, to: label.superview).maxX,
                                    "標題壓到返回鍵上了")
        XCTAssertLessThanOrEqual(label.frame.maxX, trailing.convert(trailing.bounds, to: label.superview).minX,
                                 "標題壓到右側按鈕上了")
    }

    /// 寬的 leading 控制項不得被標題的置中擠掉。
    ///
    /// 三條必要優先權的約束（centerX、leading `>=`、trailing `<=`）在 leading 控制項寬過
    /// Primary 列一半時**無解**：空標題被釘在中心，卻同時被要求站到控制項右邊 8pt 之外。
    /// Auto Layout 只能打斷一條，而它打斷的是控制項自己的寬度——**標題縮到 0 也救不了**。
    /// 修正前要求 241.2pt 的分段控制只拿到 177.0pt，而且要求再寬也還是 177。
    func test_aWideLeadingControlKeepsItsWidth() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        let segmented = UIView()
        segmented.translatesAutoresizingMaskIntoConstraints = false
        let requested: CGFloat = 402 * 0.6
        NSLayoutConstraint.activate([
            segmented.widthAnchor.constraint(equalToConstant: requested),
            segmented.heightAnchor.constraint(equalToConstant: 32)
        ])
        bar.leadingItems = [segmented]
        bar.trailingItems = [TeroNavigationButton(image: UIImage(systemName: "plus"))]
        bar.title = "標題"

        bar.layoutIfNeeded()

        XCTAssertEqual(segmented.frame.width, requested, accuracy: 1.0,
                       "leading 控制項要多寬就有多寬；讓開與截斷是標題的事")
    }

    // MARK: - 標題的外觀與自訂視圖

    private func titleLabel(in bar: TeroNavigationBar) throws -> UILabel {
        try XCTUnwrap(bar.subviews.flatMap(\.subviews).compactMap { $0 as? UILabel }.first)
    }

    func test_titleColorAndFontDefaultToTheSameValuesAsBefore() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        bar.title = "標題"
        bar.layoutIfNeeded()
        let label = try titleLabel(in: bar)

        XCTAssertEqual(label.textColor, .label, "不設 titleColor 就是原本的 .label")
        XCTAssertEqual(label.font, .preferredFont(forTextStyle: .headline))
        XCTAssertTrue(label.adjustsFontForContentSizeCategory, "預設仍跟隨 Dynamic Type")
    }

    func test_settingTitleColorAndFontOverridesTheDefaults() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        bar.title = "標題"
        bar.titleColor = .white
        bar.titleFont = .systemFont(ofSize: 22, weight: .bold)
        bar.layoutIfNeeded()
        let label = try titleLabel(in: bar)

        XCTAssertEqual(label.textColor, .white, "深色底上標題要看得見")
        XCTAssertEqual(label.font.pointSize, 22)
        XCTAssertFalse(label.adjustsFontForContentSizeCategory,
                       "指定字型等於退出 Dynamic Type——替它偷偷縮放就不是照抄了")
    }

    func test_clearingTitleColorAndFontReturnsToTheDefaults() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        bar.title = "標題"
        bar.titleColor = .white
        bar.titleFont = .systemFont(ofSize: 22, weight: .bold)

        bar.titleColor = nil
        bar.titleFont = nil
        bar.layoutIfNeeded()
        let label = try titleLabel(in: bar)

        XCTAssertEqual(label.textColor, .label)
        XCTAssertEqual(label.font, .preferredFont(forTextStyle: .headline))
        XCTAssertTrue(label.adjustsFontForContentSizeCategory, "Dynamic Type 要跟著回來")
    }

    func test_aTitleViewReplacesTheTextTitleAndIsCentred() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        bar.title = "會被取代"
        let custom = UIView()
        custom.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            custom.widthAnchor.constraint(equalToConstant: 68),
            custom.heightAnchor.constraint(equalToConstant: 44)
        ])

        bar.titleView = custom
        bar.layoutIfNeeded()

        XCTAssertTrue(try titleLabel(in: bar).isHidden, "文字標題要讓位")
        let row = try XCTUnwrap(custom.superview)
        XCTAssertEqual(custom.frame.midX, row.bounds.midX, accuracy: 1.0, "置中")
        XCTAssertEqual(custom.frame.width, 68, accuracy: 1.0, "自訂視圖的尺寸由它自己決定")
    }

    func test_replacingTheTitleViewRemovesThePreviousOne() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        let first = UIView()
        let second = UIView()
        bar.titleView = first

        bar.titleView = second

        XCTAssertNil(first.superview, "換掉之後舊的要離開階層")
        XCTAssertNotNil(second.superview)
    }

    func test_clearingTheTitleViewBringsTheTextTitleBack() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        bar.title = "標題"
        bar.titleView = UIView()

        bar.titleView = nil
        bar.layoutIfNeeded()

        XCTAssertFalse(try titleLabel(in: bar).isHidden)
    }

    func test_aTitleViewStillYieldsToAWideLeadingControl() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        let wide = UIView()
        wide.translatesAutoresizingMaskIntoConstraints = false
        let requested: CGFloat = 402 * 0.6
        NSLayoutConstraint.activate([
            wide.widthAnchor.constraint(equalToConstant: requested),
            wide.heightAnchor.constraint(equalToConstant: 32)
        ])
        bar.leadingItems = [wide]
        let custom = UIView()
        custom.translatesAutoresizingMaskIntoConstraints = false
        let width = custom.widthAnchor.constraint(equalToConstant: 68)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([width, custom.heightAnchor.constraint(equalToConstant: 44)])
        custom.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.titleView = custom

        bar.layoutIfNeeded()

        XCTAssertEqual(wide.frame.width, requested, accuracy: 1.0,
                       "自訂標題視圖也不得壓垮 leading 控制項")
    }

    func test_theBackdropCanBeTurnedOff() throws {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 402, height: 44))
        let backdrop = try XCTUnwrap(bar.subviews.compactMap { $0 as? UIVisualEffectView }.first)
        XCTAssertFalse(backdrop.isHidden, "預設有底")

        bar.showsBackdrop = false

        XCTAssertTrue(backdrop.isHidden,
                      "底排在最底層，設 backgroundColor 蓋不掉它——沒有這個開關就關不掉")
    }

    func test_collapsingGivesTheSecondaryRowThePrimaryRowsSpace() throws {
        // 模擬真實情境：容器把導覽列的高度從展開值縮到收合值。固定高度的 bar 驗不到
        // 這件事——被擠壓的是「導覽列縮短之後」的 Secondary。
        let expanded: CGFloat = 96, collapsed: CGFloat = 52
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 390, height: expanded))
        let stories = UIView()
        bar.secondaryView = stories
        bar.layoutIfNeeded()
        let container = try XCTUnwrap(stories.superview)

        bar.frame = CGRect(x: 0, y: 0, width: 390, height: collapsed)
        bar.applyCollapseProgress(1.0)
        bar.layoutIfNeeded()

        XCTAssertEqual(container.bounds.height, collapsed, accuracy: 0.5,
                       "收合後整條導覽列都是 Secondary 的；留在 Primary 下方就只剩 8pt，"
                       + "裡面四邊釘死的 view 只能靠打斷 constraint 才畫得出來")
    }

    func test_collapseProgressIsClamped() {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
        bar.layoutIfNeeded()

        bar.applyCollapseProgress(-1)

        let primaryRow = bar.subviews.first { $0.subviews.contains { $0 is UILabel } }
        XCTAssertEqual(primaryRow?.alpha, 1)
    }

    func test_plainButtonHasNoBackdrop() {
        let button = TeroNavigationButton(title: "‹", material: .plain)

        XCTAssertFalse(button.subviews.contains { $0 is UIVisualEffectView })
    }

    func test_glassButtonDegradesWhenReduceTransparencyIsOn() {
        overrideAccessibility(reduceTransparency: true)

        let button = TeroNavigationButton(title: "‹", material: .glass)

        XCTAssertFalse(button.subviews.contains { $0 is UIVisualEffectView },
                       "降低透明度時不做玻璃（ADR-0006）")
    }

    // MARK: - `.automatic` 跟隨 Tab Bar 的 effective style（issue #90）

    /// chrome 上放一顆 `.automatic` 按鈕的頁面。
    private final class AutomaticButtonPage: UIViewController, TeroNavigationChromeProviding {
        let button = TeroNavigationButton(image: UIImage(systemName: "plus"), material: .automatic)
        func makeTeroNavigationChromeView() -> UIView {
            let bar = TeroNavigationBar(frame: .zero)
            bar.trailingItems = [button]
            return bar
        }
        var teroNavigationChromeHeight: CGFloat { 44 }
    }

    private func presentUnderTabBar(style: TeroTabBarStyle) -> AutomaticButtonPage {
        let page = AutomaticButtonPage()
        let container = TeroNavigationContainer(rootViewController: page)
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = style
        let controller = makeController(configuration: configuration)
        controller.setTabs([TeroTab(identifier: "a", viewController: container,
                                    item: TeroTabItem(title: nil, image: nil, selectedImage: nil))],
                           selectedIdentifier: "a", animated: false)
        present(controller)
        page.button.layoutIfNeeded()
        return page
    }

    private func hasGlassBackdrop(_ button: TeroNavigationButton) -> Bool {
        button.subviews.contains { $0 is UIVisualEffectView }
    }

    func test_automaticResolvesToGlassUnderAFloatingGlassTabBar() throws {
        guard #available(iOS 26, *) else { throw XCTSkip("glass 是 iOS 26 材質") }
        guard !TeroAccessibility.isReduceTransparencyEnabled() else { throw XCTSkip("降低透明度開啟時不套玻璃") }

        let page = presentUnderTabBar(style: .floatingGlass)

        XCTAssertTrue(hasGlassBackdrop(page.button), "FloatingGlass 底下的 .automatic 等同 .glass")
    }

    func test_automaticResolvesToPlainUnderAClassicTabBar() {
        let page = presentUnderTabBar(style: .classic)

        XCTAssertFalse(hasGlassBackdrop(page.button), "Classic 底下的 .automatic 等同 .plain")
    }

    func test_automaticResolvesToPlainOutsideAnyTabBar() {
        let page = AutomaticButtonPage()
        let container = TeroNavigationContainer(rootViewController: page)
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        page.button.layoutIfNeeded()

        XCTAssertFalse(hasGlassBackdrop(page.button), "單獨使用的容器沒有 style 可跟，等同 .plain")
    }
}

/// Phase 7：捲動驅動的 chrome 收合。
final class ChromeScrollCoordinationTests: TeroTabBarControllerTestCase {

    private func page(_ name: String) -> ChromePage { ChromePage(name: name) }

    private func presented(_ root: UIViewController) -> TeroNavigationContainer {
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = 0.2
        container.chromeCollapseDistance = 100
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        return container
    }

    private func sample(_ offset: CGFloat, userDriven: Bool = true) -> TeroTabScrollSample {
        var s = TeroTabScrollSample(offset: offset, maximumOffset: 2000, velocity: 0)
        s.isUserDriven = userDriven
        return s
    }

    func test_scrollingDownCollapsesTheChrome() {
        let container = presented(page("root"))

        container.consumeScrollSample(sample(100))
        container.consumeScrollSample(sample(120))
        container.consumeScrollSample(sample(200))

        XCTAssertGreaterThan(container.chromeCollapseProgress, 0)
    }

    func test_theProviderSeesTheProgressFromScrolling() {
        let root = page("root")
        let container = presented(root)
        root.resetProgressSamples()

        container.consumeScrollSample(sample(100))
        container.consumeScrollSample(sample(120))
        container.consumeScrollSample(sample(250))

        XCTAssertEqual(root.progressSamples.last, 1.0, "收合進度要一路送到 chrome view")
    }

    func test_theReservedInsetDoesNotFollowTheCollapse() {
        let root = ChromePage(name: "root", expanded: 96, collapsed: 44)
        let container = presented(root)

        container.consumeScrollSample(sample(100))
        container.consumeScrollSample(sample(120))
        container.consumeScrollSample(sample(250))

        XCTAssertEqual(container.chromeCollapseProgress, 1, "確實收合了")
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 96,
                       "但 inset 維持展開高度——否則 contentOffset 會變，被判成 user scroll（B19）")
    }

    func test_programmaticScrollingDoesNotCollapse() {
        let container = presented(page("root"))

        container.consumeScrollSample(sample(100, userDriven: false))
        container.consumeScrollSample(sample(400, userDriven: false))

        XCTAssertEqual(container.chromeCollapseProgress, 0)
    }

    func test_fixedBehaviorIgnoresScrolling() {
        let container = presented(page("root"))
        container.chromeScrollBehavior = .fixed

        container.consumeScrollSample(sample(100))
        container.consumeScrollSample(sample(400))

        XCTAssertEqual(container.chromeCollapseProgress, 0)
    }

    func test_pushingANewPageExpandsTheChromeAgain() {
        let container = presented(page("root"))
        container.consumeScrollSample(sample(100))
        container.consumeScrollSample(sample(120))
        container.consumeScrollSample(sample(250))
        XCTAssertEqual(container.chromeCollapseProgress, 1)

        container.pushViewController(page("detail"), animated: false)

        XCTAssertEqual(container.chromeCollapseProgress, 0,
                       "收合進度屬於某一頁的捲動位置，不該延續到下一頁")
    }

    // MARK: - 收合距離是公開設定（issue #94）

    /// 同一組樣本，距離短的先收完。只斷言相對關係，不綁方向鎖的錨點細節。
    func test_aShorterCollapseDistanceCollapsesSooner() {
        let short = presented(page("short"))
        short.chromeCollapseDistance = 60
        let long = presented(page("long"))
        long.chromeCollapseDistance = 200

        for container in [short, long] {
            container.consumeScrollSample(sample(100))
            container.consumeScrollSample(sample(120))
            container.consumeScrollSample(sample(200))
        }

        XCTAssertEqual(short.chromeCollapseProgress, 1, "捲了約 80–100pt，60pt 的距離早就收完")
        XCTAssertLessThan(long.chromeCollapseProgress, 1, "200pt 的距離還沒走完")
        XCTAssertGreaterThan(long.chromeCollapseProgress, 0)
    }

    func test_aNonPositiveCollapseDistanceFallsBackAndIsReported() {
        let container = presented(page("root"))

        container.chromeCollapseDistance = -5

        XCTAssertEqual(container.chromeCollapseDistance, 120, "Release 採安全 fallback")
        XCTAssertEqual(reportedDiagnostics.count, 1)
    }
}
