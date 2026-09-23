import XCTest
import UIKit
@testable import Tero

/// Phase 14：把計畫書 §48 的 Stress Lab 情境寫成斷言。
///
/// 每一條都是「在轉場還沒結算時再丟一件事進來」。ADR-0014 對這類 re-entry 只給一個答案：
/// **正在跑的那一段結算到自己的終點**，不丟棄。丟棄看起來乾淨，但會留下沒收到
/// `didMove(toParent:)` 的 child，以及只有 begin 沒有 end 的 appearance。
/// 因此這裡斷言的是**整段序列**，不只是最後的狀態——最後的狀態對了而中途漏掉一半配對，
/// 正是這個模型要防的那種壞法。
///
/// §48 的十個情境裡，**沒有**寫在這裡的是：
/// - **Rotate during transition**：headless 的 XCTest 轉不了裝置方向，
///   `viewWillTransition(to:with:)` 也造不出真的 transition coordinator。
///   能自動化的只有「版面尺寸換掉」那一半，寫成下面的 Resize 兩條。
/// - **Present modal 的 appearance 交接**：沒有宿主 App 時 UIKit 不會把 presenting 端的
///   `viewWillDisappear` 送出來，dismiss 也不保證完成。只留下「modal 不會讓 stack 卡住」那一條。
///
/// 這兩項要在裝置上的 Stress Lab 目視，不要因為這個檔案存在就以為它們有守。
final class StressScenarioTests: TeroTabBarControllerTestCase {

    private func page(_ name: String) -> LifecycleSpyViewController {
        LifecycleSpyViewController(name: name, log: log)
    }

    /// 轉場時間刻意拉長，讓「轉場進行中」的斷言不必跟時鐘賽跑。
    private func presented(
        root: UIViewController,
        duration: TimeInterval = 1.0
    ) -> TeroNavigationContainer {
        let container = TeroNavigationContainer(rootViewController: root)
        container.transitionDuration = duration
        window.rootViewController = container
        window.makeKeyAndVisible()
        container.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
        return container
    }

    private func waitForSettle(
        _ container: TeroNavigationContainer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        waitUntil("轉場結算", file: file, line: line) { container.transitionState == .idle }
    }

    /// 斷言某一頁收到的 appearance 是**這一串**，不是「包含某幾個」。
    ///
    /// 只查「有沒有 willAppear」會讓「begin 了但沒 end」通過；順序錯了也一樣通過。
    private func assertAppearance(
        _ page: LifecycleSpyViewController,
        _ expected: [String],
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            log.events(matching: "\(page.name)."),
            expected.map { "\(page.name).\($0)" },
            message.isEmpty ? "\(page.name) 的 appearance 序列" : message,
            file: file,
            line: line
        )
    }

    // MARK: - Rapid Push

    func test_rapidPush_keepsEveryPushedPageAsAChildAndGivesEachCoveredPageAFullAppearancePair() {
        let root = page("root")
        let container = presented(root: root)
        let pages = (1...4).map { page("p\($0)") }
        log.reset()

        for candidate in pages {
            container.pushViewController(candidate, animated: true)
        }
        waitForSettle(container)

        XCTAssertEqual(
            container.viewControllers.map(ObjectIdentifier.init),
            ([root] + pages).map(ObjectIdentifier.init),
            "四次 push 全部提交，順序就是呼叫順序"
        )
        XCTAssertEqual(
            container.children.map(ObjectIdentifier.init),
            ([root] + pages).map(ObjectIdentifier.init),
            "被下一段瞬間結算掉的那幾頁仍然是 child——settle-forward 不丟棄"
        )

        // 中間三頁都只在畫面上停留了一瞬間，但配對必須完整：這是不丟棄的代價，也是它的目的。
        assertAppearance(root, ["willDisappear", "didDisappear"])
        for covered in pages.dropLast() {
            assertAppearance(covered, ["willAppear", "didAppear", "willDisappear", "didDisappear"])
        }
        assertAppearance(pages[3], ["willAppear", "didAppear"])
    }

    // MARK: - Rapid Pop

    func test_rapidPop_removesEveryPoppedPageFromChildrenAndGivesEachUncoveredPageAFullAppearancePair() {
        let root = page("root")
        let container = presented(root: root)
        let pages = (1...4).map { page("p\($0)") }
        for candidate in pages {
            container.pushViewController(candidate, animated: false)
        }
        XCTAssertEqual(container.viewControllers.count, 5, "起點是五層，才有四次 pop 可以連發")
        log.reset()

        for _ in 0..<4 {
            container.popViewController(animated: true)
        }
        waitForSettle(container)

        XCTAssertEqual(
            container.viewControllers.map(ObjectIdentifier.init),
            [ObjectIdentifier(root)],
            "四次 pop 全部提交"
        )
        XCTAssertEqual(
            container.children.map(ObjectIdentifier.init),
            [ObjectIdentifier(root)],
            "每一頁都走完了 removeFromParent，沒有人卡在 children 裡"
        )
        for popped in pages {
            XCTAssertNil(popped.parent, "\(popped.name) 應該已經脫離容器")
            XCTAssertNil(popped.viewIfLoaded?.superview, "\(popped.name) 的 view 也要離開畫面")
        }

        assertAppearance(pages[3], ["willDisappear", "didDisappear"], "最上面那一頁只是離開")
        for uncovered in pages.dropLast().reversed() {
            assertAppearance(uncovered, ["willAppear", "didAppear", "willDisappear", "didDisappear"])
        }
        assertAppearance(root, ["willAppear", "didAppear"])
    }

    // MARK: - Push while transition

    func test_pushWhileAPopTransitionRuns_settlesThePopFirstSoThePoppedPageStillLeavesChildren() {
        let root = page("root")
        let container = presented(root: root)
        let detail = page("detail")
        container.pushViewController(detail, animated: false)
        log.reset()

        container.popViewController(animated: true)
        XCTAssertEqual(container.transitionState, .popping, "pop 的動畫確實還在跑")
        let third = page("third")
        container.pushViewController(third, animated: true)
        waitForSettle(container)

        XCTAssertEqual(
            container.viewControllers.map(ObjectIdentifier.init),
            [root, third].map(ObjectIdentifier.init)
        )
        XCTAssertNil(detail.parent, "被 push 打斷的 pop 仍然走完了自己的終點")
        XCTAssertEqual(
            container.children.map(ObjectIdentifier.init),
            [root, third].map(ObjectIdentifier.init)
        )

        assertAppearance(detail, ["willDisappear", "didDisappear"])
        assertAppearance(root, ["willAppear", "didAppear", "willDisappear", "didDisappear"],
                         "root 被 pop 推上來又被 push 蓋掉，兩組配對都要完整")
        assertAppearance(third, ["willAppear", "didAppear"])
    }

    // MARK: - Interactive Pop Cancel

    func test_interactivePopCancelledAfterJitteryProgressUpdates_leavesTheStackUnchangedAndReversesTheAppearanceExactlyOnce() {
        let root = page("root")
        let container = presented(root: root, duration: 0.2)
        let first = page("first")
        let second = page("second")
        container.pushViewController(first, animated: false)
        container.pushViewController(second, animated: false)
        log.reset()

        XCTAssertTrue(container.beginInteractivePop())
        for progress in [0.1, 0.6, 0.3, 0.7, 0.2] as [CGFloat] {
            container.updateInteractivePop(progress: progress)
        }
        container.endInteractivePop(progress: 0.2, velocity: 0)
        waitForSettle(container)

        XCTAssertEqual(
            container.viewControllers.map(ObjectIdentifier.init),
            [root, first, second].map(ObjectIdentifier.init),
            "手勢從頭到尾沒有提交，來回拖動多少次都一樣"
        )
        // 反向補償只補一次。每來回一次就補一次的話，這裡會看到重複的 willAppear。
        assertAppearance(second, ["willDisappear", "willAppear", "didAppear"])
        assertAppearance(first, ["willAppear", "willDisappear", "didDisappear"])
        XCTAssertEqual(log.events(matching: "root."), [], "root 不在這段手勢裡，不該收到任何事件")
        XCTAssertNil(first.view.superview, "被拉出來的那一頁要退出畫面")
    }

    func test_beginInteractivePopWhileTheCancelAnimationStillRuns_isRefusedEvenThoughTheStackIsDeepEnough() {
        let container = presented(root: page("root"), duration: 1.0)
        container.pushViewController(page("first"), animated: false)
        container.pushViewController(page("second"), animated: false)

        XCTAssertTrue(container.beginInteractivePop())
        container.updateInteractivePop(progress: 0.4)
        container.endInteractivePop(progress: 0.4, velocity: 0)

        XCTAssertEqual(container.transitionState, .cancellingInteractivePop)
        XCTAssertEqual(container.viewControllers.count, 3, "取消不動 stack，深度足夠再起一段")
        XCTAssertFalse(container.beginInteractivePop(), "但取消的動畫還在跑，同時只能有一段轉場")

        waitForSettle(container)
        XCTAssertTrue(container.beginInteractivePop(),
                      "結算之後同一個 stack 就能再起一段——證明剛才被拒是因為轉場在跑，不是因為太淺")
        container.endInteractivePop(progress: 0, velocity: 0)
        waitForSettle(container)
    }

    // MARK: - Interactive Pop Finish

    func test_beginInteractivePopWhileTheFinishAnimationStillRuns_isRefusedEvenThoughTheCommittedStackIsDeepEnough() {
        let container = presented(root: page("root"), duration: 1.0)
        container.pushViewController(page("first"), animated: false)
        let second = page("second")
        container.pushViewController(second, animated: false)

        XCTAssertTrue(container.beginInteractivePop())
        container.updateInteractivePop(progress: 0.9)
        container.endInteractivePop(progress: 0.9, velocity: 0)

        XCTAssertEqual(container.transitionState, .finishingInteractivePop)
        XCTAssertEqual(container.viewControllers.count, 2, "判定成立的當下就提交，不等動畫")
        XCTAssertTrue(container.children.contains { $0 === second }, "但被 pop 掉的那一頁還沒離開 children")
        XCTAssertFalse(container.beginInteractivePop(), "結算前不能再起一段")

        waitForSettle(container)
        XCTAssertNil(second.parent)
        XCTAssertTrue(container.beginInteractivePop(),
                      "剩下的兩層一樣可以再返回一次——證明剛才被拒是因為轉場在跑，不是因為太淺")
        container.endInteractivePop(progress: 0, velocity: 0)
        waitForSettle(container)
    }

    func test_pushDuringTheFinishAnimationOfAnInteractivePop_settlesTheGestureBeforeTheNewPageAppears() {
        let root = page("root")
        let container = presented(root: root, duration: 1.0)
        let first = page("first")
        let second = page("second")
        container.pushViewController(first, animated: false)
        container.pushViewController(second, animated: false)
        log.reset()

        XCTAssertTrue(container.beginInteractivePop())
        container.endInteractivePop(progress: 0.9, velocity: 0)
        XCTAssertEqual(container.transitionState, .finishingInteractivePop)
        let third = page("third")
        container.pushViewController(third, animated: true)
        waitForSettle(container)

        XCTAssertEqual(
            container.viewControllers.map(ObjectIdentifier.init),
            [root, first, third].map(ObjectIdentifier.init)
        )
        XCTAssertNil(second.parent, "手勢段已經提交，它的結算不能被 push 吃掉")
        assertAppearance(second, ["willDisappear", "didDisappear"])
        assertAppearance(first, ["willAppear", "didAppear", "willDisappear", "didDisappear"],
                         "手勢把 first 拉上來，push 又把它蓋掉，兩組配對都要完整")
        assertAppearance(third, ["willAppear", "didAppear"])
    }

    // MARK: - Resize during transition

    func test_resizingTheContainerMidPush_settlesWithTheIncomingPageFillingTheNewBounds() {
        let container = presented(root: page("root"), duration: 1.0)
        let detail = page("detail")

        container.pushViewController(detail, animated: true)
        XCTAssertEqual(container.transitionState, .pushing, "確定是在轉場中途改尺寸")
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        window.layoutIfNeeded()

        waitForSettle(container)
        container.view.layoutIfNeeded()

        XCTAssertEqual(container.view.bounds.width, 844, "尺寸真的換了")
        XCTAssertEqual(detail.view.transform, .identity, "轉場的位移要收乾淨")
        XCTAssertEqual(detail.view.frame, container.view.bounds, "進入的那一頁要填滿新的版面")
        XCTAssertIdentical(container.topViewController, detail)
    }

    func test_resizingTheContainerMidInteractivePop_stillFinishesAndLeavesThePageBelowFillingTheNewBounds() {
        let root = page("root")
        let container = presented(root: root, duration: 0.2)
        let detail = page("detail")
        container.pushViewController(detail, animated: false)

        XCTAssertTrue(container.beginInteractivePop())
        container.updateInteractivePop(progress: 0.5)
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        window.layoutIfNeeded()
        container.updateInteractivePop(progress: 0.9)
        container.endInteractivePop(progress: 0.9, velocity: 0)
        waitForSettle(container)
        container.view.layoutIfNeeded()

        XCTAssertEqual(container.view.bounds.width, 844, "尺寸真的換了")
        XCTAssertEqual(
            container.viewControllers.map(ObjectIdentifier.init),
            [ObjectIdentifier(root)]
        )
        XCTAssertNil(detail.parent)
        XCTAssertEqual(root.view.transform, .identity)
        XCTAssertEqual(root.view.frame, container.view.bounds)
    }

    // MARK: - Tab switch while transition

    func test_tabSwitchWhileAPushTransitionRuns_stillSettlesTheOffscreenContainerAndKeepsThePushedPageAsAChild() {
        let root = UIViewController()
        let first = TeroNavigationContainer(rootViewController: root)
        first.transitionDuration = 1.0
        let second = TeroNavigationContainer(rootViewController: UIViewController())
        let controller = makeTabController(containers: [first, second])
        let detail = ContainmentSpyViewController(name: "detail", log: log)

        first.pushViewController(detail, animated: true)
        XCTAssertEqual(first.transitionState, .pushing, "確定是在轉場中途切走")
        XCTAssertEqual(log.events(matching: "detail."), ["detail.willMove(container)"],
                       "提交只做 containment 的前半，didMove 屬於結算")
        controller.selectTab(withIdentifier: "t1", animated: false)
        XCTAssertNil(first.viewIfLoaded?.window, "容器已經離開畫面")

        waitUntil("離開畫面的容器仍然結算") { first.transitionState == .idle }

        // 切走不是取消。離開畫面的那一段要跑完自己的終點，否則 detail 會是一個
        // 收不到 didMove(toParent:) 的 child——ADR-0014 選 settle-forward 就是為了這個。
        // 只看 `parent` 不算數：`addChild` 當下 `parent` 就有值了。
        XCTAssertEqual(log.events(matching: "detail."),
                       ["detail.willMove(container)", "detail.didMove(container)"],
                       "containment 的後半要補上")
        XCTAssertEqual(
            first.children.map(ObjectIdentifier.init),
            [root, detail].map(ObjectIdentifier.init)
        )
        XCTAssertEqual(
            first.viewControllers.map(ObjectIdentifier.init),
            [root, detail].map(ObjectIdentifier.init)
        )
        // 這裡刻意不斷言 appearance 序列。切走的時點落在 commit 與 settle 之間時，
        // `settle` 讀的 `isContainerAppeared` 已經是 false，outgoing 的
        // `endAppearanceTransition()` 因此被跳過——它收到的 `willDisappear` 沒有配對。
        // 那是待處理的 library 行為，不是這條測試要釘住的東西，所以只驗 containment 這一半。
    }

    func test_tabSwitchWhileAPushToAHiddenBarPageRuns_leavesTheBarExpandedAndKeepsItThatWayWhenTheOldTransitionSettles() {
        let first = TeroNavigationContainer(rootViewController: UIViewController())
        first.transitionDuration = 1.0
        let second = TeroNavigationContainer(rootViewController: UIViewController())
        let controller = makeTabController(containers: [first, second])

        first.pushViewController(StressHidingPage(), animated: true)
        XCTAssertEqual(controller.tabBar.presentationState, .hidden,
                       "轉場中 Bar 已經 preview 到隱藏——之後才有東西可以被錯誤地保留下來")

        controller.selectTab(withIdentifier: "t1", animated: false)

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
        XCTAssertEqual(controller.tabBar.presentationState, .expanded,
                       "切到新 Tab 要把上一段的 preview 收掉")

        waitUntil("被切走的容器結算") { first.transitionState == .idle }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(controller.tabBarPresentationState, .expanded)
        XCTAssertEqual(controller.tabBar.presentationState, .expanded,
                       "舊容器的結算回呼不能把新 Tab 的 Bar 收起來")
    }

    // MARK: - Present modal while stack active

    /// 只涵蓋「modal 不會讓 stack 卡住」這一半。
    ///
    /// 另一半——容器被全螢幕 modal 蓋住時應該收到 `viewWillDisappear` 並把它轉給 top——
    /// 在沒有宿主 App 的 XCTest 環境裡不會發生（UIKit 不送 presenting 端的 appearance），
    /// 因此那部分留給裝置上的 Stress Lab，這裡不假裝有覆蓋到。
    func test_pushingWhileAModalIsPresentedOverTheContainer_commitsAndSettlesAndLeavesTheModalPresented() {
        let root = page("root")
        let container = presented(root: root, duration: 0.4)
        let modal = UIViewController()
        modal.modalPresentationStyle = .fullScreen
        container.present(modal, animated: false, completion: nil)
        waitUntil("modal 蓋上") { container.presentedViewController === modal }
        log.reset()

        let detail = page("detail")
        container.pushViewController(detail, animated: true)
        waitForSettle(container)

        XCTAssertIdentical(container.presentedViewController, modal, "push 不該把 modal 收掉")
        XCTAssertEqual(
            container.viewControllers.map(ObjectIdentifier.init),
            [root, detail].map(ObjectIdentifier.init)
        )
        XCTAssertIdentical(detail.parent, container)
        container.dismiss(animated: false, completion: nil)
    }

    // MARK: - Scroll while chrome transition

    func test_scrollingDuringAPushTransition_keepsCollapsingTheChromeUntilTheSettleResetsItToExpanded() {
        let first = StressChromeScrollPage()
        let second = StressChromeScrollPage()
        let container = TeroNavigationContainer(rootViewController: first)
        container.transitionDuration = 1.0
        // 收合距離拉長，讓第一段拖曳只收到一半——收滿了就分不出「轉場期間還有沒有繼續收」。
        container.chromeCollapseDistance = 1000
        _ = makeTabController(containers: [container])
        first.loadViewIfNeeded()

        // 第一筆取樣會被當成幾何變更吃掉（安裝 chrome 寫了 reserved inset），只用來重新錨定。
        first.drag(to: 50)
        first.drag(to: 100)
        let collapsedBeforePush = container.chromeCollapseProgress
        XCTAssertGreaterThan(collapsedBeforePush, 0, "捲動樣本要先真的收到 chrome，否則後面都是在比 0 和 0")
        XCTAssertLessThan(collapsedBeforePush, 1, "留一段沒收完，待會才看得出有沒有繼續收")

        container.pushViewController(second, animated: true)
        XCTAssertEqual(container.transitionState, .pushing, "確定是在轉場中途繼續捲")
        // push 會在 commit 當下就寫 incoming 的 reserved inset（chrome 不等 settle 才換），
        // 所以這裡跟開頭一樣，第一筆取樣是重新錨定、不是使用者捲動。
        first.drag(to: 300)
        first.drag(to: 600)

        XCTAssertGreaterThan(container.chromeCollapseProgress, collapsedBeforePush,
                             "轉場期間樣本照走，chrome 繼續收")

        waitForSettle(container)

        XCTAssertEqual(container.chromeCollapseProgress, 0,
                       "換頁後 chrome 回到展開：收合進度屬於上一頁的捲動位置，不延續到下一頁")
    }

    // MARK: - Builders

    private func makeTabController(containers: [TeroNavigationContainer]) -> TeroTabBarController {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        let controller = TeroTabBarController(configuration: configuration)
        let tabs = containers.enumerated().map { index, container in
            TeroTab(
                identifier: "t\(index)",
                viewController: container,
                item: TeroTabItem(title: "T\(index)", image: nil, selectedImage: nil)
            )
        }
        controller.setTabs(tabs, selectedIdentifier: "t0", animated: false)
        present(controller)
        return controller
    }
}

/// 只記錄 containment 的兩半。
///
/// `parent` 在 `addChild` 的當下就有值，所以「它還是 child」證明不了 `didMove(toParent:)`
/// 有送到——而那正是 ADR-0014 不肯丟棄轉場的理由。要驗它就得自己記。
private final class ContainmentSpyViewController: UIViewController {

    private let name: String
    private let log: EventLog

    init(name: String, log: EventLog) {
        self.name = name
        self.log = log
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        log.record("\(name).willMove(\(parent == nil ? "nil" : "container"))")
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        log.record("\(name).didMove(\(parent == nil ? "nil" : "container"))")
    }
}

/// 宣告要隱藏 Tab Bar 的頁面，用來讓轉場的 preview 有東西可以看。
private final class StressHidingPage: UIViewController, TeroTabVisibilityProviding {
    var preferredTeroTabVisibilityPolicy: TeroTabVisibilityPolicy { .hidden }
}

/// 有頂部 chrome、也交出捲動輸入的頁面。
private final class StressChromeScrollPage: UIViewController,
                                            TeroNavigationChromeProviding,
                                            TeroScrollProviding {
    /// 收合只吃使用者驅動的捲動；程式設定 offset 不算。直接設 `contentOffset`
    /// 什麼都證明不了，所以這裡把 `isDragging` 覆寫成真正拖曳的樣子。
    final class DraggingScrollView: UIScrollView {
        var simulatesDragging = false
        override var isDragging: Bool { simulatesDragging || super.isDragging }
    }
    let scrollView = DraggingScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        scrollView.contentSize = CGSize(width: 390, height: 4000)
        view.addSubview(scrollView)
    }

    func drag(to offset: CGFloat) {
        scrollView.simulatesDragging = true
        scrollView.contentOffset = CGPoint(x: 0, y: offset)
        scrollView.simulatesDragging = false
    }

    var teroTrackingScrollView: UIScrollView? { scrollView }
    func makeTeroNavigationChromeView() -> UIView { UIView() }
    var teroNavigationChromeHeight: CGFloat { 96 }
    var teroNavigationChromeCollapsedHeight: CGFloat { 44 }
}
