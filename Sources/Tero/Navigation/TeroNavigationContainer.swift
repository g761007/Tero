import UIKit

/// 自建的 stack 容器。不是 `UINavigationController` 的子類，也不追求與它的 API 相容。
///
/// **Stack 是同步提交的模型，轉場是它的落後呈現**（ADR-0014）。`push` / `pop` /
/// `setViewControllers` 在 return 之前就完成陣列變更，不等動畫。因此在轉場進行中：
///
/// - `viewControllers` 與畫面上看到的**不一致**。用 `topViewController` 回答
///   「畫面現在顯示什麼」會拿到未來。
/// - `viewControllers` 與 `children` 也**不一致**。pop 提交後那個 View Controller
///   已離開 `viewControllers`，但仍是 `children` 的一員，直到轉場結算才移除。
///
/// 成員逐一標註 `@objc`：容器有非公開的實作面，而且 initializer 需要釘 selector；
/// `@objcMembers` 對無法在 Objective-C 表示的成員會靜默略過（見
/// `docs/spikes/0001-objc-interop.md`）。純資料型別走另一條規則。
public final class TeroNavigationContainer: UIViewController {

    // MARK: - Stack

    /// 目前這一疊 View Controller，由底到頂。空 stack 是合法狀態。
    ///
    /// 轉場進行中，這裡是**已提交**的結果，不是畫面上的樣子。
    /// 觀察 stack 變更。時點語意見 `TeroNavigationContainerDelegate`。
    @objc public weak var delegate: TeroNavigationContainerDelegate?

    @objc public private(set) var viewControllers: [UIViewController] = []

    /// stack 最上面那一個。空 stack 時為 nil。
    @objc public var topViewController: UIViewController? { viewControllers.last }

    /// stack 最底下那一個。空 stack 時為 nil。
    @objc public var rootViewController: UIViewController? { viewControllers.first }

    // MARK: - 初始化

    /// 建立空容器。空 stack 合法，容器只顯示自己的 view。
    @objc public init() {
        super.init(nibName: nil, bundle: nil)
        ownScrollTracker.onSample = { [weak self] sample in self?.consumeScrollSample(sample) }
    }

    /// 建立只有一個 View Controller 的容器。
    ///
    /// 走內部安裝路徑：不啟動轉場、不發事件、不載入 view。
    @objc(initWithRootViewController:)
    public convenience init(rootViewController: UIViewController) {
        self.init()
        install([rootViewController])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("TeroNavigationContainer 不支援 Storyboard 與 XIB，請改用程式化初始化")
    }

    // MARK: - 生命週期

    /// 手動控制 appearance 轉發：容器要在正確的時點成對送出 begin/end，
    /// 交給 UIKit 自動轉發會在 stack 變更時失去配對。
    public override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    private var isContainerAppeared = false
    private let transitions = TeroNavigationTransitionCoordinator()

    // MARK: - Chrome

    /// 每個 child 的 chrome。key 綁 containment，不綁 stack——互動式返回時 stack 沒變，
    /// 但被拉出來的那一頁已經在階層裡，它也要有 chrome（B17）。
    private var chromeViews: [ObjectIdentifier: UIView] = [:]
    /// 轉場中的那一對 chrome（issue #91）。
    ///
    /// 兩個都掛在 `chromeContainer` 裡，進度決定各自的 alpha 與容器的高度：outgoing 淡出、
    /// incoming 淡入，高度在兩頁的帶高之間內插。有動畫的 push／pop 由 animator 推到 1，
    /// 互動式返回跟著手指。轉場外這裡是 nil，chrome 由 `updateVisibleChrome` 管。
    ///
    /// 原本 commit 那一刻直接換成新頁的 chrome、內容才開始滑，互動返回期間 chrome 完全
    /// 不動、finish 之後才跳——原生 `UINavigationController` 與 Instagram 的標題與返回鍵
    /// 都是跟著轉場走的，這是取代它最容易被肉眼看出的差異。
    private struct ChromeTransition {
        var outgoing: UIView?
        var incoming: UIView?
        var fromHeight: CGFloat
        var toHeight: CGFloat
        var progress: CGFloat = 0
    }
    private var chromeTransition: ChromeTransition?

    /// 上次看到的內容尺寸類別，用來偵測 Dynamic Type 變動。
    ///
    /// 沿用 `TeroTabBarController` 對 size class 的做法（比對快取值），不掛已被取代的
    /// `traitCollectionDidChange`——同一個 repo 裡混用兩種慣例比任一種都糟。
    private var lastContentSizeCategory: UIContentSizeCategory?
    private var chromeHeightConstraint: NSLayoutConstraint?

    private lazy var chromeContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = true
        return container
    }()

    /// 要不要在頂部 chrome 裝 iOS 26 的 scroll edge effect。預設開。
    ///
    /// 實測（2026-09-18，iPhone 17／iOS 26 模擬器）：這個互動一裝上，chrome 區裡的**動態系統色**
    /// 會解析成 bar 的變體——`systemBackground` 畫出來是 (245, 245, 245) 而不是白，固定色不受影響。
    /// 半透明的 chrome 要它（內容捲過去時的邊緣處理）；不透明、要與內容同色的 chrome
    /// （Instagram 那種白底 header）關掉它，不然 header 會比內容灰一階。
    ///
    /// Objective-C 是 `scrollEdgeEffectEnabled`，getter 是 `isScrollEdgeEffectEnabled`，比照 UIKit。
    @objc(scrollEdgeEffectEnabled)
    public var isScrollEdgeEffectEnabled: Bool {
        @objc(isScrollEdgeEffectEnabled) get { storedScrollEdgeEffectEnabled }
        set {
            guard newValue != storedScrollEdgeEffectEnabled else { return }
            storedScrollEdgeEffectEnabled = newValue
            updateScrollEdgeSource()
        }
    }
    private var storedScrollEdgeEffectEnabled = true

    private var storedScrollEdgeInteraction: AnyObject?

    @available(iOS 26, *)
    private var scrollEdgeInteraction: UIScrollEdgeElementContainerInteraction? {
        get { storedScrollEdgeInteraction as? UIScrollEdgeElementContainerInteraction }
        set { storedScrollEdgeInteraction = newValue }
    }

    /// 系統的 scroll edge effect，頂部版本。底部由 `TeroTabBar` 裝 `.bottom`，兩邊對稱。
    ///
    /// 互動**只在有 chrome、有追蹤對象、而且沒被關掉時才裝**，其餘時候拆掉（issue #102）：
    /// 沒有 scroll view 就沒有邊緣可處理，而裝著沒事做的互動不是免費的——它會改寫容器裡
    /// 動態系統色的解析（見 `isScrollEdgeEffectEnabled`），Tab Bar 那一側還會被 iOS 26 的
    /// observation tracking 判成回饋迴圈。對象沒換就不重寫。
    private func updateScrollEdgeSource() {
        guard #available(iOS 26, *), isViewLoaded else { return }
        let hasChrome = topViewController
            .map(ObjectIdentifier.init)
            .flatMap { chromeViews[$0] } != nil
        let target = (isScrollEdgeEffectEnabled && hasChrome) ? trackingScrollView(of: topViewController) : nil
        if let target {
            if scrollEdgeInteraction == nil {
                let interaction = UIScrollEdgeElementContainerInteraction()
                interaction.edge = .top
                chromeContainer.addInteraction(interaction)
                scrollEdgeInteraction = interaction
            }
            if scrollEdgeInteraction?.scrollView !== target {
                scrollEdgeInteraction?.scrollView = target
            }
        } else if let interaction = scrollEdgeInteraction {
            chromeContainer.removeInteraction(interaction)
            scrollEdgeInteraction = nil
        }
    }

    private func trackingScrollView(of viewController: UIViewController?) -> UIScrollView? {
        (viewController as? TeroScrollProviding)?.teroTrackingScrollView
    }

    /// 收合進度，0 為完全展開。由捲動或程式設定。
    /// 頂部 chrome 的收合進度，0 為完全展開、1 為完全收合。
    ///
    /// 唯讀：這個值由捲動樣本驅動，不是設定值。要改變 chrome 收合**多少**，
    /// 調整頁面宣告的兩個帶高；要改變收合的**方式**，寫自己的 chrome view。
    @objc public internal(set) var chromeCollapseProgress: CGFloat = 0 {
        didSet {
            guard chromeCollapseProgress != oldValue else { return }
            updateChromeGeometry()
        }
    }

    /// 頂部 chrome 的捲動政策。**與 Tab Bar 的狀態機是兩套**（§26）：讀同一份取樣
    /// 與同一個方向鎖，但一邊輸出 0…1 的連續進度、一邊輸出三個離散狀態。
    private var chromePolicy = TeroChromeScrollPolicy()

    /// chrome 對捲動的反應方式。`.fixed` 表示這個容器的 chrome 不隨捲動改變。
    ///
    /// 與 Tab Bar 的 `TeroTabBarScrollBehavior` 是兩套值（§26）：同一次下捲，頂部可以
    /// 收起來、底部可以不動。改變時從目前的進度重新起算。
    @objc public var chromeScrollBehavior: TeroChromeScrollBehavior = .hidePrimary {
        didSet { chromePolicy.reset(progress: chromeCollapseProgress) }
    }

    // MARK: - 捲動樣本的來源

    /// 容器自己的追蹤器。只在**沒有上層餵樣本**時工作。
    ///
    /// 單獨使用的容器（modal 流程、onboarding）原本沒有樣本來源，頂部 chrome 不會隨
    /// 捲動收合（owner-actions §6 欠條 4）。兩個選項裡選了「容器自己追蹤」：內部型別
    /// 不外露，consumer 也不必多接一條線。
    private let ownScrollTracker = TeroTabScrollTracker()

    /// 上層掛導管時設為 true：樣本由它餵，容器自己的追蹤器停用。
    ///
    /// 同一個 scroll view 兩個觀察者會各算一套方向鎖、在邊界上得到不同結論
    /// （`TeroTabScrollTracker` 的註解），所以兩條路徑互斥。方向是父層朝下：容器只接受
    /// 通知，不查詢 parent（§38）。
    internal var receivesExternalScrollSamples = false {
        didSet {
            guard receivesExternalScrollSamples != oldValue else { return }
            updateOwnScrollTracking()
        }
    }

    /// 測試用：容器現在是不是自己在觀察某個 scroll view。
    internal var isTrackingScrollViewItself: Bool { ownScrollTracker.trackedScrollView != nil }

    /// 接上（或放掉）top 的 scroll view。只在對象改變時重接，重接會重設方向鎖。
    private func updateOwnScrollTracking() {
        guard isViewLoaded else { return }
        let target = receivesExternalScrollSamples ? nil : trackingScrollView(of: topViewController)
        guard ownScrollTracker.trackedScrollView !== target else { return }
        ownScrollTracker.track(target, resetTo: .expanded)
    }

    /// 餵一筆捲動取樣給頂部政策。
    ///
    /// 取樣由誰產生不是這裡的事：在 Tab Bar 底下時，上層把它那條既有追蹤路徑的樣本
    /// 轉進來，兩側因此讀同一份；單獨使用時由 `ownScrollTracker` 產生。兩者只有一個在工作。
    internal func consumeScrollSample(_ sample: TeroTabScrollSample) {
        var sample = sample
        if pendingGeometryChange {
            pendingGeometryChange = false
            sample.geometryChanged = true
        }
        let configuration = TeroChromeScrollPolicy.Configuration(
            behavior: chromeScrollBehavior,
            collapseDistance: chromeCollapseDistance,
            directionLockDistance: chromeDirectionLockDistance
        )
        chromeCollapseProgress = chromePolicy.consume(sample, configuration: configuration)
    }

    /// 從方向鎖的錨點往下捲多少 pt 算完全收合。預設 120。
    ///
    /// Instagram 那種「header 在自己的高度內就收完」把它設成 chrome 的展開高度即可。
    /// 非正值或非有限值回退為預設並回報診斷，與 `TeroTabScrollConfiguration` 的處置一致。
    @objc public var chromeCollapseDistance: CGFloat = 120 {
        didSet {
            guard chromeCollapseDistance.isFinite, chromeCollapseDistance > 0 else {
                TeroDiagnostics.report("chromeCollapseDistance 必須是正的有限值，收到 \(chromeCollapseDistance)，已回退為 120。")
                chromeCollapseDistance = 120
                return
            }
            chromePolicy.reset(progress: chromeCollapseProgress)
        }
    }
    internal var chromeDirectionLockDistance: CGFloat = 8

    /// 轉場狀態（§11）。Phase 3 會加上互動式返回的三個狀態。
    internal enum TransitionState {
        case idle
        case pushing
        case popping
        case interactivePop
        case finishingInteractivePop
        case cancellingInteractivePop
    }

    internal private(set) var transitionState: TransitionState = .idle

    /// 轉場時長。Phase 2 先用常數；要不要開成設定留到有實際需求時再決定。
    /// push／pop 動畫的長度。互動式返回的結束動畫依剩餘距離縮放這個值。
    ///
    /// 2.0 不提供自訂轉場：轉場的**樣式**（推拉與 parallax）是固定的，只有長度可調。
    @objc public var transitionDuration: TimeInterval = 0.35

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(chromeContainer)
        let height = chromeContainer.heightAnchor.constraint(equalToConstant: 0)
        chromeHeightConstraint = height
        NSLayoutConstraint.activate([
            chromeContainer.topAnchor.constraint(equalTo: view.topAnchor),
            chromeContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chromeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            height
        ])
        view.addGestureRecognizer(edgePanRecognizer)
        edgePanRecognizer.isEnabled = isInteractivePopGestureEnabled
        if let top = topViewController {
            installContentView(of: top)
            installChromeIfNeeded(for: top)
            updateVisibleChrome()
        }
    }

    /// 安全區變了（旋轉、視窗 resize）chrome 的總高要跟著重算。
    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateChromeGeometry()
    }

    /// 以快取的內容尺寸類別比對取代已被取代的 `traitCollectionDidChange`。
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let category = traitCollection.preferredContentSizeCategory
        guard lastContentSizeCategory != category else { return }
        lastContentSizeCategory = category
        updateChromeGeometry()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        topViewController?.beginAppearanceTransition(true, animated: animated)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isContainerAppeared = true
        topViewController?.endAppearanceTransition()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        topViewController?.beginAppearanceTransition(false, animated: animated)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isContainerAppeared = false
        topViewController?.endAppearanceTransition()
    }

    // MARK: - Stack mutation

    /// 推入一個 View Controller。
    ///
    /// 陣列在 return 之前就已變更（ADR-0014）。
    @objc(pushViewController:animated:)
    public func pushViewController(_ viewController: UIViewController, animated: Bool) {
        TeroDiagnostics.assertMainThread()

        guard viewController !== topViewController else {
            TeroDiagnostics.report("重複 push 同一個 View Controller，已忽略")
            return
        }
        guard !viewControllers.contains(where: { $0 === viewController }) else {
            TeroDiagnostics.report("這個 View Controller 已經在 stack 裡，已忽略")
            return
        }
        guard viewController.parent == nil || viewController.parent === self else {
            TeroDiagnostics.report("這個 View Controller 已屬於其他容器，已忽略")
            return
        }

        let outgoing = topViewController
        commit(viewControllers + [viewController], incoming: viewController, outgoing: outgoing,
               operation: .push, animated: animated)
    }

    /// 移除最上面那一個並回傳它。stack 只有一個或空的時候回傳 nil 且不做任何事。
    @discardableResult
    @objc(popViewControllerAnimated:)
    public func popViewController(animated: Bool) -> UIViewController? {
        TeroDiagnostics.assertMainThread()

        guard viewControllers.count > 1, let removed = viewControllers.last else { return nil }

        let newStack = Array(viewControllers.dropLast())
        commit(newStack, incoming: newStack.last, outgoing: removed, removing: [removed],
               operation: .pop, animated: animated)
        return removed
    }

    /// 回到 root。已經在 root 或空 stack 時是無聲的 no-op。
    /// Pop 到指定的 View Controller，回傳被移除的那些（由底到頂）。
    ///
    /// 不在 stack 裡就什麼都不做並回報診斷——這是呼叫端的錯，安靜地什麼都不做會讓它
    /// 留到跑進那條路徑才爆。已經在最上層時回傳空陣列。
    ///
    /// 存在的理由是索引算術：consumer 自己用 `firstIndex(of:)` 加切片再 `setViewControllers`
    /// 也做得到，但算錯不會被編譯器發現，而正確答案容器自己知道。
    @discardableResult
    @objc(popToViewController:animated:)
    public func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController] {
        TeroDiagnostics.assertMainThread()

        guard let index = viewControllers.firstIndex(where: { $0 === viewController }) else {
            TeroDiagnostics.report("popToViewController: 目標不在 stack 裡，什麼都不做")
            return []
        }
        let removing = Array(viewControllers.suffix(from: index + 1))
        guard !removing.isEmpty else { return [] }

        let newStack = Array(viewControllers.prefix(through: index))
        let outgoing = topViewController
        commit(newStack, incoming: viewController, outgoing: outgoing, removing: removing,
               operation: .pop, animated: animated)
        return removing
    }

    @objc(popToRootViewControllerAnimated:)
    public func popToRootViewController(animated: Bool) {
        TeroDiagnostics.assertMainThread()

        guard viewControllers.count > 1, let root = viewControllers.first else { return }
        let removing = Array(viewControllers.dropFirst())
        let outgoing = topViewController
        commit([root], incoming: root, outgoing: outgoing, removing: removing,
               operation: .pop, animated: animated)
    }

    /// 整組替換。傳空陣列是合法的，容器會變成只顯示自己的 view。
    @objc(setViewControllers:animated:)
    public func setViewControllers(_ newViewControllers: [UIViewController], animated: Bool) {
        TeroDiagnostics.assertMainThread()

        var accepted: [UIViewController] = []
        for candidate in newViewControllers {
            if accepted.contains(where: { $0 === candidate }) {
                TeroDiagnostics.report("同一個 View Controller 在陣列中出現多次，只保留第一個")
                continue
            }
            if let parent = candidate.parent, parent !== self {
                TeroDiagnostics.report("這個 View Controller 已屬於其他容器，已略過")
                continue
            }
            accepted.append(candidate)
        }

        guard accepted.map(ObjectIdentifier.init) != viewControllers.map(ObjectIdentifier.init) else {
            return  // 完全相同：無聲 no-op
        }

        let outgoing = topViewController
        let removing = viewControllers.filter { old in !accepted.contains { $0 === old } }
        let operation: TeroNavigationTransitionCoordinator.Operation =
            accepted.count >= viewControllers.count ? .push : .pop
        commit(accepted, incoming: accepted.last, outgoing: outgoing, removing: removing,
               operation: operation, animated: animated)
    }

    // MARK: - 邊緣手勢

    private lazy var edgePanRecognizer: UIScreenEdgePanGestureRecognizer = {
        let recognizer = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan))
        // leading 而非寫死 .left：RTL 下返回手勢在右邊（ADR-0006 的內部一律用 leading/trailing）。
        recognizer.edges = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
        return recognizer
    }()

    /// 驅動互動式返回的邊緣手勢辨識器。
    ///
    /// 公開它是為了**手勢仲裁**：頁面左緣若有橫向捲動的內容（輪播、照片 pager、可左滑的
    /// 列），前 20pt 會被這顆辨識器吃掉，而仲裁只能由 consumer 自己決定：
    ///
    /// ```swift
    /// carousel.panGestureRecognizer.require(toFail: container.interactivePopGestureRecognizer)
    /// ```
    ///
    /// 驅動這段手勢的三個入口維持 internal——2.0 不支援自訂返回手勢（見 README 的已知限制）。
    @objc public var interactivePopGestureRecognizer: UIGestureRecognizer { edgePanRecognizer }

    /// 是否啟用邊緣返回手勢。預設開。
    ///
    /// Objective-C 是 `interactivePopGestureEnabled`，getter 是 `isInteractivePopGestureEnabled`，
    /// 比照 UIKit。
    @objc(interactivePopGestureEnabled)
    public var isInteractivePopGestureEnabled: Bool {
        @objc(isInteractivePopGestureEnabled) get { storedInteractivePopGestureEnabled }
        set {
            storedInteractivePopGestureEnabled = newValue
            edgePanRecognizer.isEnabled = newValue
        }
    }
    private var storedInteractivePopGestureEnabled = true

    @objc private func handleEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        let width = view.bounds.width
        guard width > 0 else { return }

        let isRTL = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let translation = recognizer.translation(in: view).x * (isRTL ? -1 : 1)
        let velocity = recognizer.velocity(in: view).x * (isRTL ? -1 : 1)
        let progress = min(max(translation / width, 0), 1)

        switch recognizer.state {
        case .began:
            beginInteractivePop()
        case .changed:
            updateInteractivePop(progress: progress)
        case .ended:
            endInteractivePop(progress: progress, velocity: velocity)
        case .cancelled, .failed:
            endInteractivePop(progress: 0, velocity: 0)
        default:
            break
        }
    }

    // MARK: - 互動式返回

    /// 手勢進行中的那一對。**stack 尚未變動**——提交在 finish 判定成立時才發生。
    private var interactivePair: (outgoing: UIViewController, incoming: UIViewController)?
    private var interactiveNavigationID: UUID?

    /// 開始互動式返回。回傳 false 表示現在不能開始（stack 太淺、或已有轉場在跑）。
    ///
    /// Phase 1–3 維持 internal，以 `@testable` 驅動（B9）：`§55` 的必做 scope 沒有
    /// 「consumer 自訂 interactive pop 驅動」，而公開 API 一旦進基準就不可逆。
    @discardableResult
    internal func beginInteractivePop() -> Bool {
        guard transitionState == .idle, viewControllers.count > 1 else { return false }
        guard isViewLoaded, view.window != nil else { return false }

        let outgoing = viewControllers[viewControllers.count - 1]
        let incoming = viewControllers[viewControllers.count - 2]

        // 下一頁要先在階層裡才能跟著手指動，但它還不是 top——stack 沒變。
        addChildIfNeeded(incoming)
        installChromeIfNeeded(for: incoming)
        installContentView(of: incoming)
        view.layoutIfNeeded()

        beginAppearance(incoming: incoming, outgoing: outgoing)
        transitions.beginInteractive(from: outgoing, to: incoming, in: view)
        // 下一頁的 chrome 一起被拉出來，跟手指淡入（issue #91）。
        beginChromeTransition(from: outgoing, to: incoming)
        interactivePair = (outgoing, incoming)
        // 互動式返回的目的地是下面那一頁。取消時以 cancelled: true 結算，
        // 上層因此回到來源狀態——而 stack 從頭到尾沒變（ADR-0014）。
        interactiveNavigationID = onNavigationTransition?(outgoing, incoming, true)
        transitionState = .interactivePop
        return true
    }

    /// 以 0…1 的進度更新。超出範圍會被夾住。
    internal func updateInteractivePop(progress: CGFloat) {
        guard transitionState == .interactivePop else { return }
        transitions.updateInteractive(progress: progress)
        applyChromeTransition(progress: progress)
    }

    /// 結束手勢。依 §16 由進度與速度共同判定，兩者任一達標就 finish。
    internal func endInteractivePop(progress: CGFloat, velocity: CGFloat) {
        guard transitionState == .interactivePop, let pair = interactivePair else { return }

        let shouldFinish = progress > 0.5 || velocity > 800
        transitionState = shouldFinish ? .finishingInteractivePop : .cancellingInteractivePop
        interactivePair = nil

        if shouldFinish {
            // 提交落在判定成立的這一刻，不是動畫結束時（ADR-0014）。
            pair.outgoing.willMove(toParent: nil)
            viewControllers = Array(viewControllers.dropLast())
            delegate?.teroNavigationContainer?(self, willShow: pair.incoming, animated: true)
        } else {
            // 取消：stack 一個字都沒變過，但 appearance 已經送出去了。
            // UIKit 沒有 beginAppearanceTransition 的 rollback，唯一的復原是補一組相反的配對。
            pair.outgoing.beginAppearanceTransition(true, animated: true)
            pair.incoming.beginAppearanceTransition(false, animated: true)
        }

        transitions.endInteractive(
            finish: shouldFinish,
            progress: progress,
            duration: transitionDuration,
            alongside: { [weak self] in
                // chrome 用剩下的距離跟內容一起跑完（或退回）。
                self?.applyChromeTransition(progress: shouldFinish ? 1 : 0)
                self?.view.layoutIfNeeded()
            }
        ) { [weak self] in
            guard let self else { return }
            if shouldFinish {
                pair.outgoing.viewIfLoaded?.removeFromSuperview()
                self.returnTopInset(for: pair.outgoing)
                self.removeChrome(for: pair.outgoing)
                pair.outgoing.removeFromParent()
                pair.outgoing.endAppearanceTransition()
                pair.incoming.endAppearanceTransition()
            } else {
                // 回到原狀：下一頁退出階層，兩邊的反向配對收尾。
                pair.incoming.viewIfLoaded?.removeFromSuperview()
                pair.outgoing.endAppearanceTransition()
                pair.incoming.endAppearanceTransition()
            }
            self.endChromeTransition()
            self.updateVisibleChrome()
            if shouldFinish {
                self.delegate?.teroNavigationContainer?(self, didShow: pair.incoming, animated: true)
            }
            if let id = self.interactiveNavigationID {
                self.interactiveNavigationID = nil
                self.onNavigationTransitionEnd?(id, !shouldFinish)
            }
            self.transitionState = .idle
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            self.setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        }
    }

    /// 手勢進行中又收到 stack 變更時，把手勢段收乾淨。
    ///
    /// 不收的話 `beginInteractivePop` 送出的 `beginAppearanceTransition` 會永遠等不到配對的
    /// `end`，而且被拉出來的那一頁會留在畫面上——`endInteractivePop` 之後會因為
    /// `transitionState` 已被改回 `.idle` 而直接 return。
    private func abortInteractivePopIfNeeded() {
        guard transitionState == .interactivePop, let pair = interactivePair else { return }
        interactivePair = nil
        transitions.abortInteractive()

        if isContainerAppeared {
            // 與取消同樣的反向配對，只是不帶動畫。
            pair.outgoing.beginAppearanceTransition(true, animated: false)
            pair.incoming.beginAppearanceTransition(false, animated: false)
            pair.outgoing.endAppearanceTransition()
            pair.incoming.endAppearanceTransition()
        }
        pair.incoming.viewIfLoaded?.removeFromSuperview()
        // 被拉出來的那一頁的 chrome 也要收回去，否則它會留在容器裡陪下一段轉場。
        endChromeTransition()
        updateVisibleChrome()
        if let id = interactiveNavigationID {
            interactiveNavigationID = nil
            onNavigationTransitionEnd?(id, true)   // 手勢沒有完成，等同取消
        }
        transitionState = .idle
    }

    // MARK: - Chrome 安裝

    /// 在 View Controller 進入階層時建立它的 chrome，並把帶高讀下來。
    ///
    /// 綁 containment 而不是綁 `topViewController`：互動式返回把下一頁裝進階層時 stack
    /// 還沒變，綁 top 的話那一頁整段手勢都不會有 chrome，finish 時才憑空彈出（B17）。
    private func installChromeIfNeeded(for viewController: UIViewController) {
        let key = ObjectIdentifier(viewController)
        guard chromeViews[key] == nil,
              let provider = viewController as? TeroNavigationChromeProviding else { return }

        let chromeView = provider.makeTeroNavigationChromeView()
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        chromeViews[key] = chromeView
        updateBackNavigationAvailability()
    }

    private func removeChrome(for viewController: UIViewController) {
        let key = ObjectIdentifier(viewController)
        chromeViews[key]?.removeFromSuperview()
        chromeViews[key] = nil
    }

    /// 告訴每一頁的導覽列它有沒有上一頁可以回去，鏡射據此決定要不要合成返回鍵。
    ///
    /// 答案只有容器知道，而且要在 stack 提交之後才對：chrome 在提交之前就建立了、建好之後
    /// 也不重建，頁面自己在 `makeTeroNavigationChromeView()` 裡判斷 root，會在換 root、
    /// 空容器 push、root 被拿掉這幾種情況答錯。所以每次提交與每次建立 chrome 之後都重算一次。
    /// 互動式返回判定 finish 時只拿掉最上面那一頁，其餘頁的位置不變，不必重算。
    ///
    /// 不在 stack 裡的頁面不動：pop 提交之後，離開的那一頁還在畫面上淡出，返回鍵要陪它到最後。
    private func updateBackNavigationAvailability() {
        for (index, viewController) in viewControllers.enumerated() {
            guard let chromeView = chromeViews[ObjectIdentifier(viewController)] else { continue }
            for bar in Self.navigationBars(in: chromeView) {
                bar.canNavigateBack = index > 0
            }
        }
    }

    /// chrome view 本身或它子樹裡的 `TeroNavigationBar`：採用者可能把 bar 包在自己的 view 裡。
    private static func navigationBars(in chromeView: UIView) -> [TeroNavigationBar] {
        var bars: [TeroNavigationBar] = []
        var queue = [chromeView]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let bar = view as? TeroNavigationBar {
                bars.append(bar)
            } else {
                queue.append(contentsOf: view.subviews)
            }
        }
        return bars
    }

    /// 把 top 的 chrome 放進容器，其餘移出。轉場中不動——那時兩頁的 chrome 都該在。
    private func updateVisibleChrome() {
        guard isViewLoaded, chromeTransition == nil else { return }
        let top = topViewController
        let topKey = top.map(ObjectIdentifier.init)

        for (key, chromeView) in chromeViews where key != topKey {
            chromeView.removeFromSuperview()
        }
        if let topKey, let chromeView = chromeViews[topKey], chromeView.superview !== chromeContainer {
            installChromeView(chromeView)
        }
        updateChromeGeometry()
        updateScrollEdgeSource()
        updateOwnScrollTracking()
    }

    private func installChromeView(_ chromeView: UIView) {
        chromeContainer.addSubview(chromeView)
        NSLayoutConstraint.activate([
            chromeView.topAnchor.constraint(equalTo: chromeContainer.topAnchor),
            chromeView.leadingAnchor.constraint(equalTo: chromeContainer.leadingAnchor),
            chromeView.trailingAnchor.constraint(equalTo: chromeContainer.trailingAnchor),
            chromeView.bottomAnchor.constraint(equalTo: chromeContainer.bottomAnchor)
        ])
    }

    // MARK: - 轉場中的 chrome（issue #91）

    /// 讓兩頁的 chrome 同時在容器裡，從 outgoing 現在的高度出發、往 incoming 的展開高度走。
    ///
    /// outgoing 停在它現在的樣子（可能收合了一半），incoming 的 provider 先收到 0——
    /// 它是一頁新的、展開的 chrome。收合進度屬於離開的那一頁，這裡把政策歸零。
    private func beginChromeTransition(from outgoing: UIViewController?, to incoming: UIViewController?) {
        guard isViewLoaded, outgoing !== incoming else { return }
        let collapse = min(max(chromeCollapseProgress, 0), 1)
        let fromHeight = chromeHeights(of: outgoing)
            .map { $0.expanded + ($0.collapsed - $0.expanded) * collapse } ?? 0
        let toHeight = chromeHeights(of: incoming)?.expanded ?? 0
        let outgoingChrome = outgoing.flatMap { chromeViews[ObjectIdentifier($0)] }
        let incomingChrome = incoming.flatMap { chromeViews[ObjectIdentifier($0)] }
        for chrome in [outgoingChrome, incomingChrome].compactMap({ $0 }) where chrome.superview !== chromeContainer {
            installChromeView(chrome)
        }
        if let incoming, let incomingChrome, let provider = incoming as? TeroNavigationChromeProviding {
            provider.updateTeroNavigationChrome?(incomingChrome, collapseProgress: 0)
        }
        chromeTransition = ChromeTransition(
            outgoing: outgoingChrome, incoming: incomingChrome, fromHeight: fromHeight, toHeight: toHeight
        )
        chromePolicy.reset()
        applyChromeTransition(progress: 0)
    }

    /// 0 是 outgoing 的樣子，1 是 incoming 的。alpha 互補，高度線性內插。
    private func applyChromeTransition(progress: CGFloat) {
        guard var transition = chromeTransition else { return }
        let p = min(max(progress, 0), 1)
        transition.progress = p
        chromeTransition = transition
        transition.outgoing?.alpha = 1 - p
        transition.incoming?.alpha = p
        chromeHeightConstraint?.constant = view.safeAreaInsets.top
            + transition.fromHeight + (transition.toHeight - transition.fromHeight) * p
    }

    /// 轉場結束：兩個 alpha 歸位，之後由 `updateVisibleChrome` 決定誰留下。
    private func endChromeTransition() {
        guard chromeTransition != nil else { return }
        chromeTransition = nil
        for chrome in chromeViews.values { chrome.alpha = 1 }
    }

    /// 問 provider 目前的兩個帶高。
    ///
    /// **每次都問，不快取**（B18）。快取住的話，凡是帶高在頁面存活期間會變的情境全部
    /// 無解：使用者調大字級、標題從一行變兩行、Secondary 列依條件出現或消失。錯的還不只
    /// chrome 自己的高度——reserved inset 讀同一個來源，內容讓開的邊距會一起錯。
    private func chromeHeights(
        of viewController: UIViewController?
    ) -> (expanded: CGFloat, collapsed: CGFloat)? {
        guard let viewController,
              chromeViews[ObjectIdentifier(viewController)] != nil,
              let provider = viewController as? TeroNavigationChromeProviding else { return nil }
        let expanded = provider.teroNavigationChromeHeight
        return (expanded, provider.teroNavigationChromeCollapsedHeight ?? expanded)
    }

    /// 要求重算 chrome 的幾何。
    ///
    /// chrome 的結構由 consumer 決定，所以「什麼時候該重新量」也只有 consumer 知道：
    /// 換了標題、Secondary 列出現或消失之後呼叫它。Dynamic Type 的變動由容器自己偵測，
    /// 不需要呼叫這個方法。
    @objc public func setNeedsChromeGeometryUpdate() {
        updateChromeGeometry()
    }

    /// 依兩個端點內插目前高度，並把進度交給 provider。
    ///
    /// 高度是設定值不是量測值（B18），每次都重問 provider（C3）。轉場中高度由轉場進度
    /// 決定，這裡只把 reserved inset 對到 top。
    private func updateChromeGeometry() {
        guard isViewLoaded else { return }
        if let transition = chromeTransition {
            applyChromeTransition(progress: transition.progress)
            updateTopReservedInset()
            return
        }
        let key = topViewController.map(ObjectIdentifier.init)
        let heights = chromeHeights(of: topViewController)
        let progress = min(max(chromeCollapseProgress, 0), 1)
        let height = heights.map { $0.expanded + ($0.collapsed - $0.expanded) * progress } ?? 0

        // 容器把 chrome 貼在 view 的頂邊，也就是狀態列底下；宣告的高度則只算導覽列
        // 自己的內容。兩者相差一個安全區，由容器補——狀態列高度依裝置而異，consumer
        // 寫不出可攜的常數，而容器本來就知道自己的安全區。
        //
        // 這也讓 reserved inset 對得上：`additionalSafeAreaInsets` 是疊在系統安全區
        // 之上的增量，所以它就是宣告的高度本身。少了這一項，chrome 蓋住的範圍會比
        // 內容讓開的範圍短一個狀態列，中間空一條。
        chromeHeightConstraint?.constant = view.safeAreaInsets.top + height
        updateTopReservedInset()

        if let key, let chromeView = chromeViews[key],
           let provider = topViewController as? TeroNavigationChromeProviding {
            provider.updateTeroNavigationChrome?(chromeView, collapseProgress: progress)
        }
    }

    /// Top 軸的 reserved inset。
    ///
    /// 依 ADR-0004 的 2.0 修訂：這個容器**只寫 top**，且只寫自己的 direct children，
    /// 不轉寫它從上層收到的 inset。捲動驅動時值恆為展開高度（B19），避免
    /// 「inset 變 → contentOffset 變 → 被判成 user scroll」這條回授路徑。
    private func updateTopReservedInset() {
        guard isViewLoaded else { return }
        let reserved = topViewController
            .map(ObjectIdentifier.init)
            .flatMap { _ in chromeHeights(of: topViewController) }?.expanded ?? 0

        var changed = false
        // 寫 inset 會移動 contentOffset；自己的追蹤器整段暫停，與 Tab Bar 那條路徑的
        // `withoutTracking` 是同一件事。上層餵樣本時這個追蹤器沒在觀察，包著也無害。
        ownScrollTracker.withoutTracking {
            for child in children {
                let value = child === topViewController ? reserved : 0
                changed = safeAreaLedger.apply(value, to: child) || changed
            }
        }
        // 寫 inset 會移動 contentOffset。下一筆取樣必須被當成幾何變更而不是使用者捲動，
        // 否則就是 §31 的回授迴圈：inset 變 → offset 變 → 判成捲動 → 再變。
        if changed { pendingGeometryChange = true }
    }

    /// 只寫 top（軸擁有權，ADR-0004 2.0 修訂）。
    // MARK: - 對上層的轉場通知（Phase 9）
    //
    // 容器**不持有、不查詢、不呼叫 parent**（§38）。它只是把「轉場開始了」送出去，
    // 由掛上這些 closure 的人決定要不要反應——所以換成任何容器都能接上，
    // 而容器本身不需要認得 TeroTabBarController 這個型別。

    /// 轉場開始。回傳非 nil 表示上層要求在結束時通知它。
    internal var onNavigationTransition: ((UIViewController?, UIViewController, Bool) -> UUID?)?
    /// 轉場結束。`cancelled` 為 true 表示互動式返回被取消。
    internal var onNavigationTransitionEnd: ((UUID, Bool) -> Void)?

    private var safeAreaLedger = TeroSafeAreaLedger(edge: .top)
    private var pendingGeometryChange = false

    private func returnTopInset(for viewController: UIViewController) {
        safeAreaLedger.release(viewController)
    }

    private func addChildIfNeeded(_ viewController: UIViewController) {
        guard viewController.parent !== self else { return }
        addChild(viewController)
        viewController.didMove(toParent: self)
    }

    // MARK: - 提交與結算

    /// 提交：陣列、containment 的前半。轉場之後才結算。
    ///
    /// Phase 1 沒有動畫，因此提交後立即結算；兩者在程式碼上分開，是為了讓
    /// Phase 2 把轉場插在中間時不必重寫這一段。
    private func commit(
        _ newStack: [UIViewController],
        incoming: UIViewController?,
        outgoing: UIViewController?,
        removing: [UIViewController] = [],
        operation: TeroNavigationTransitionCoordinator.Operation,
        animated: Bool
    ) {
        // 手勢段沒有「自己的終點」可以結算過去，所以它是中止而不是 settle-forward。
        // 它從未提交，因此中止只需要把 appearance 反向補回去（與取消同一條路）。
        abortInteractivePopIfNeeded()
        // settle-forward：正在飛的那一段先結算到終點，新的一段才從乾淨的階層起跑。
        transitions.settleRunningTransition()

        if let incoming, incoming.parent !== self {
            addChild(incoming)  // 前半：didMove 留到結算
        }
        if let incoming { installChromeIfNeeded(for: incoming) }
        for viewController in removing {
            viewController.willMove(toParent: nil)  // 前半：removeFromParent 留到結算
        }

        viewControllers = newStack
        updateBackNavigationAvailability()

        let canAnimate = animated && isViewLoaded && view.window != nil && incoming !== outgoing
        if let incoming, incoming !== outgoing {
            delegate?.teroNavigationContainer?(self, willShow: incoming, animated: canAnimate)
        }
        guard canAnimate else {
            // 無動畫也要通知上層：邏輯狀態變了，只是沒有中間過程可以 preview。
            // beginContainerNavigation 在 animated: false 時會自己結算並回傳 nil。
            if let incoming { _ = onNavigationTransition?(outgoing, incoming, false) }
            settle(incoming: incoming, outgoing: outgoing, removing: removing)
            return
        }

        transitionState = operation == .push ? .pushing : .popping
        beginAppearance(incoming: incoming, outgoing: outgoing)
        if let incoming { installContentView(of: incoming) }
        // top inset 跟著 commit 走，不等 settle：到這裡 `viewControllers` 已經是新 stack，
        // incoming 要以自己的帶高排版，否則它會帶著 0 的 inset 滑進來、結算那一刻跳一次。
        // chrome 則是兩頁一起在容器裡，跟內容同一個 animator 交叉淡入、高度內插（issue #91）。
        beginChromeTransition(from: outgoing, to: incoming)
        updateTopReservedInset()
        updateScrollEdgeSource()
        updateOwnScrollTracking()
        view.layoutIfNeeded()

        let navigationID = incoming.flatMap { onNavigationTransition?(outgoing, $0, true) }

        transitions.run(
            operation: operation,
            from: outgoing,
            to: incoming,
            in: view,
            duration: transitionDuration,
            alongside: { [weak self] in
                self?.applyChromeTransition(progress: 1)
                self?.view.layoutIfNeeded()
            }
        ) { [weak self] in
            self?.settle(
                incoming: incoming, outgoing: outgoing, removing: removing,
                appearanceAlreadyBegun: true, animated: true
            )
            if let navigationID { self?.onNavigationTransitionEnd?(navigationID, false) }
        }
    }

    /// 結算：視圖、containment 的後半、appearance 的配對。
    private func beginAppearance(incoming: UIViewController?, outgoing: UIViewController?) {
        guard isContainerAppeared, incoming !== outgoing else { return }
        outgoing?.beginAppearanceTransition(false, animated: true)
        incoming?.beginAppearanceTransition(true, animated: true)
    }

    private func settle(
        incoming: UIViewController?,
        outgoing: UIViewController?,
        removing: [UIViewController],
        appearanceAlreadyBegun: Bool = false,
        animated: Bool = false
    ) {
        let notifiesAppearance = isContainerAppeared && incoming !== outgoing

        if notifiesAppearance && !appearanceAlreadyBegun {
            outgoing?.beginAppearanceTransition(false, animated: false)
            incoming?.beginAppearanceTransition(true, animated: false)
        }

        if isViewLoaded {
            if outgoing !== incoming, outgoing?.viewIfLoaded?.superview === view {
                outgoing?.viewIfLoaded?.removeFromSuperview()
            }
            if let incoming { installContentView(of: incoming) }
        }

        if notifiesAppearance {
            outgoing?.endAppearanceTransition()
            incoming?.endAppearanceTransition()
        }

        if let incoming, incoming.parent === self {
            incoming.didMove(toParent: self)  // 後半
        }
        for viewController in removing {
            viewController.viewIfLoaded?.removeFromSuperview()
            returnTopInset(for: viewController)   // entry 綁 containment，離開就歸還
            removeChrome(for: viewController)
            viewController.removeFromParent()  // 後半
        }

        endChromeTransition()
        updateVisibleChrome()
        // 換頁時 chrome 回到展開：收合進度屬於某一頁的捲動位置，不該延續到下一頁。
        chromeCollapseProgress = 0
        chromePolicy.reset()
        transitionState = .idle
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        if let incoming, incoming !== outgoing {
            delegate?.teroNavigationContainer?(self, didShow: incoming, animated: animated)
        }
    }

    /// initializer 專用：不發事件、不啟動轉場、不載入 view。
    private func install(_ stack: [UIViewController]) {
        for viewController in stack {
            addChild(viewController)
            viewController.didMove(toParent: self)
        }
        viewControllers = stack
        // chrome 留到 viewDidLoad：這條路徑的契約是不載入任何 view（B10）。
    }

    private func installContentView(of viewController: UIViewController) {
        let content = viewController.view!
        content.translatesAutoresizingMaskIntoConstraints = false
        // 內容一律排在 chrome 之下。內容是滿版且不透明的，`addSubview` 會把它疊到
        // 最上層，整條 chrome 就此看不見——保留邊距仍然正確、chrome 的 parent 仍然
        // 正確，只有畫面是錯的。安裝內容有四條路徑，全部走這裡。
        view.insertSubview(content, belowSubview: chromeContainer)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    // MARK: - 轉發

    public override var childForStatusBarStyle: UIViewController? { topViewController }
    public override var childForStatusBarHidden: UIViewController? { topViewController }
    public override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
    public override var childForScreenEdgesDeferringSystemGestures: UIViewController? { topViewController }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }

    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        topViewController?.preferredInterfaceOrientationForPresentation
            ?? super.preferredInterfaceOrientationForPresentation
    }
}

// MARK: - 對上層容器的導管
//
// 容器自己不表態，只把 top 的宣告原封傳上去（B20）。這讓 Tab Bar 不必認得
// stack 容器這個型別——任何 conform 這些協定的容器都能接上。

extension TeroNavigationContainer: TeroScrollSampleReceiving {}

extension TeroNavigationContainer: TeroTabVisibilityProviding {

    /// 原封回傳 top 的 policy，**含 `.inherit`**。
    ///
    /// `.inherit` 表示「這一頁交給捲動決定」，容器把它照原樣傳上去，而不是代替頁面表態。
    public var preferredTeroTabVisibilityPolicy: TeroTabVisibilityPolicy {
        (topViewController as? TeroTabVisibilityProviding)?.preferredTeroTabVisibilityPolicy ?? .inherit
    }
}

extension TeroNavigationContainer: TeroScrollProviding {

    /// 把 top 的捲動輸入傳上去，這樣 Tab Bar 追蹤的是真正在捲動的那個視圖。
    public var teroTrackingScrollView: UIScrollView? {
        (topViewController as? TeroScrollProviding)?.teroTrackingScrollView
    }
}

extension TeroNavigationContainer: TeroTabBarAppearanceProviding {

    /// 原封回傳 top 對 Bar 介面風格的宣告，沒有宣告就 `.unspecified`。
    public var preferredTeroTabBarUserInterfaceStyle: UIUserInterfaceStyle {
        (topViewController as? TeroTabBarAppearanceProviding)?.preferredTeroTabBarUserInterfaceStyle
            ?? .unspecified
    }
}

extension TeroNavigationContainer: TeroTabBarScrollBehaviorProviding {

    /// top 沒有偏好時回 `.inherit`，設定裡的行為因此照樣套得上（B20）。
    ///
    /// 這裡原本覆寫 `responds(to:)`，只為了在 top 沒表態時假裝自己也沒實作這個成員——
    /// 因為當時 `TeroTabBarScrollBehavior` 沒有「沒有偏好」這個值。`.inherit` 補上之後
    /// 那個手法就不必要了，而且它是每個寫導管的人都得自己想出來的東西。
    public var preferredTeroTabBarScrollBehavior: TeroTabBarScrollBehavior {
        (topViewController as? TeroTabBarScrollBehaviorProviding)?
            .preferredTeroTabBarScrollBehavior ?? .inherit
    }
}
