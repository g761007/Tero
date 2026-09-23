import UIKit

/// 自建的 Tab 容器，取代 `UITabBarController`（見 ADR-0001）。
///
/// 所有 API 必須在 main thread 呼叫（計畫書 §51）。
public final class TeroTabBarController: UIViewController {

    // MARK: - Public state

    @objc public weak var delegate: TeroTabBarControllerDelegate? {
        didSet { updateLongPressAvailability() }
    }

    @objc public private(set) var tabs: [TeroTab] = []

    /// `dynamic` 是為了 KVO。
    ///
    /// 只標 `@objc` 的 Swift 屬性從 Swift 端是直接存取的，不經 ObjC runtime，於是
    /// `willChangeValueForKey` 不會發——觀察者**靜默地永遠收不到通知**。某個接入專案
    /// 有一處 `RACObserve(controller, selectedIndex)` 正是這樣失效的。
    @objc public dynamic private(set) var selectedTab: TeroTab?

    /// 沒有任何 Tab 時為 `NSNotFound`。Swift 端可改用 `selectedTabIndex`。
    ///
    /// 同樣是 `dynamic`，理由見 `selectedTab`。
    @objc public dynamic private(set) var selectedIndex: Int = NSNotFound

    @objc public var selectedViewController: UIViewController? {
        selectedTab?.viewController
    }

    /// 目前直接顯示在 Tab Bar 上的 Tabs，依顯示順序。不含 More。
    @objc public var visibleTabs: [TeroTab] {
        overflowResolution.visibleIndices.compactMap { tabs.indices.contains($0) ? tabs[$0] : nil }
    }

    /// 目前被收進 More 的 Tabs，依原始順序。
    @objc public var overflowTabs: [TeroTab] {
        overflowResolution.overflowIndices.compactMap { tabs.indices.contains($0) ? tabs[$0] : nil }
    }

    @objc public private(set) var actionItem: TeroTabActionItem?

    @objc public let tabBar: TeroTabBar

    /// Consumer 在設定中要求的 Style。
    @objc public var requestedStyle: TeroTabBarStyle {
        storedConfiguration.style
    }

    /// 實際生效的 Style。iOS 26 以下一律為 `.classic`（見 ADR-0002）。
    @objc public var tabBarStyle: TeroTabBarStyle {
        Self.effectiveStyle(forRequested: storedConfiguration.style)
    }

    @objc public private(set) var tabBarPresentationState: TeroTabBarPresentationState = .expanded

    // MARK: - Private state

    private var storedConfiguration: TeroTabBarConfiguration
    private let contentContainer = UIView()
    private let overflowResolver = TeroTabOverflowResolver()
    private let behaviorResolver = TeroTabScrollBehaviorResolver()
    private let scrollTracker = TeroTabScrollTracker()
    private var tabBarHeightConstraint: NSLayoutConstraint?
    private var tabBarBottomConstraint: NSLayoutConstraint?
    /// 程式呼叫 `.hidden` 造成的鎖定（ADR-0004）。捲動切片會讀它。
    internal private(set) var isPresentationStateLocked = false
    private let visibilityCoordinator = TeroTabVisibilityCoordinator(progress: 1)
    private let visibilityResolver = TeroTabVisibilityResolver()
    private var presentationRevision = 0
    private var selectionRevision = 0
    private weak var lastResolvedPage: UIViewController?
    private var navigationTransaction: NavigationTransaction?
    private let pageStates = NSMapTable<UIViewController, NSNumber>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private struct NavigationTransaction {
        let id: UUID
        let coordinatorID: ObjectIdentifier?
        let source: UIViewController?
        let destination: UIViewController
        let sourceState: TeroTabBarPresentationState
        let destinationState: TeroTabBarPresentationState
        let reserved: TeroTabBarPresentationState
    }
    private var reservedPresentationState: TeroTabBarPresentationState = .expanded
    private var safeAreaLedger = TeroSafeAreaLedger(edge: .bottom)
    private var lastHorizontalSizeClass: UIUserInterfaceSizeClass = .unspecified

    /// 介於 `viewWillAppear` 與 `viewDidDisappear` 之間為 true。
    private var isContainerAppeared = false

    private var activeLayoutConfiguration: TeroTabLayoutConfiguration {
        traitCollection.horizontalSizeClass == .regular
            ? storedConfiguration.regular
            : storedConfiguration.compact
    }

    private var overflowResolution: TeroTabOverflowResolver.Resolution {
        overflowResolver.resolve(
            tabCount: tabs.count,
            maximumVisibleItems: activeLayoutConfiguration.maximumVisibleItems
        )
    }

    // MARK: - Init

    @objc(initWithConfiguration:)
    public init(configuration: TeroTabBarConfiguration) {
        let snapshot = configuration.copy() as! TeroTabBarConfiguration
        self.storedConfiguration = snapshot
        self.tabBar = TeroTabBar(style: Self.effectiveStyle(forRequested: snapshot.style))
        super.init(nibName: nil, bundle: nil)
    }

    /// 註：這裡不能寫 `override`——`UIViewController.init()` 並非可覆寫的 designated
    /// initializer；而本類別宣告了自己的 designated init，父類的 initializer 不會被繼承。
    public convenience init() {
        self.init(configuration: .defaultConfiguration())
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("TeroTabBarController 僅支援程式化初始化，不支援 init(coder:)")
    }

    // MARK: - Configuration

    /// 回傳目前設定的**深拷貝快照**。修改回傳值不會影響 controller。
    @objc(currentConfiguration)
    public func currentConfiguration() -> TeroTabBarConfiguration {
        storedConfiguration.copy() as! TeroTabBarConfiguration
    }

    /// Runtime 套用新設定。
    ///
    /// **不支援 runtime 變更 `style`**（ADR-0003 的前提）：該欄位被忽略，Debug 觸發診斷。
    @objc(applyConfiguration:animated:)
    public func applyConfiguration(_ configuration: TeroTabBarConfiguration, animated: Bool) {
        TeroDiagnostics.assertMainThread()

        let snapshot = configuration.copy() as! TeroTabBarConfiguration
        if snapshot.style != storedConfiguration.style {
            TeroDiagnostics.report("不支援 runtime 變更 style，該欄位被忽略（ADR-0003）。")
            snapshot.style = storedConfiguration.style
        }
        storedConfiguration = snapshot

        guard isViewLoaded else { return }

        tabBar.apply(
            itemAppearance: storedConfiguration.itemAppearance,
            badgeAppearance: storedConfiguration.badgeAppearance,
            classicAppearance: storedConfiguration.classicAppearance,
            floatingAppearance: storedConfiguration.floatingGlassAppearance,
            motion: storedConfiguration.motion
        )
        tabBar.swipeSelectionMode = storedConfiguration.swipeSelectionMode

        let animated = TeroAccessibility.resolvedAnimated(animated)
        refreshTabBar(animated: animated)
        updateTabBarGeometry()
        updateChildSafeAreaInsets()
        refreshScrollTracking()

        let applyLayout = { self.view.layoutIfNeeded() }
        if animated {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut], animations: applyLayout)
        } else {
            applyLayout()
        }
    }

    private static func effectiveStyle(forRequested requested: TeroTabBarStyle) -> TeroTabBarStyle {
        if #available(iOS 26, *) {
            return requested
        }
        return .classic
    }

    // MARK: - Lifecycle

    /// 關閉自動轉發，改為明確驅動 child 的 appearance 事件，
    /// 讓切換 Tab 產生的序列是確定且可測的。
    public override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // 內容區是滿版的，Bar 疊在其上；子畫面以 additionalSafeAreaInsets 避開（計畫書 §44）。
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        let heightConstraint = tabBar.heightAnchor.constraint(equalToConstant: tabBar.contentHeight)
        let bottomConstraint = tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        tabBarHeightConstraint = heightConstraint
        tabBarBottomConstraint = bottomConstraint
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,
            heightConstraint
        ])

        visibilityCoordinator.onUpdate = { [weak self] _, _ in
            guard let self, self.navigationTransaction == nil else { return }
            self.updateTabBarGeometry()
            self.view.layoutIfNeeded()
        }
        tabBar.onVisibilityGeometryChange = { [weak self] in
            guard let self else { return }
            guard self.navigationTransaction == nil else { return }
            if TeroAccessibility.isReduceMotionEnabled() { self.visibilityCoordinator.settle() }
            self.updateTabBarGeometry()
            self.view.layoutIfNeeded()
        }
        tabBar.onSelectItem = { [weak self] visibleIndex in
            self?.selectVisibleItem(at: visibleIndex)
        }
        tabBar.onSelectMore = { [weak self] in
            self?.presentOverflow()
        }
        tabBar.onTriggerAction = { [weak self] in
            self?.triggerAction()
        }
        tabBar.onLongPressItem = { [weak self] visibleIndex in
            self?.longPressVisibleItem(at: visibleIndex)
        }
        updateLongPressAvailability()
        scrollTracker.onStateChange = { [weak self] state in
            self?.applyScrollDrivenPresentationState(state, animated: true)
        }
        // 頂部 chrome 的收合讀的是同一筆樣本。沒有這條線，chrome 的捲動政策再正確
        // 也不會動——它只是沒有人餵。
        scrollTracker.onSample = { [weak self] sample in
            (self?.selectedViewController as? TeroScrollSampleReceiving)?.consumeScrollSample(sample)
        }
        tabBar.apply(
            itemAppearance: storedConfiguration.itemAppearance,
            badgeAppearance: storedConfiguration.badgeAppearance,
            classicAppearance: storedConfiguration.classicAppearance,
            floatingAppearance: storedConfiguration.floatingGlassAppearance,
            motion: storedConfiguration.motion
        )
        tabBar.swipeSelectionMode = storedConfiguration.swipeSelectionMode
        lastHorizontalSizeClass = traitCollection.horizontalSizeClass
        refreshTabBar(animated: false)
        visibilityCoordinator.move(to: tabBarPresentationState == .hidden ? 0 : 1, duration: 0, animated: false)
        updateTabBarGeometry()
        updateChildSafeAreaInsets()
        refreshScrollTracking()

        if let viewController = selectedViewController {
            installContentView(of: viewController)
        }
    }

    /// 以快取的 size class 比對取代已被取代的 `traitCollectionDidChange`。
    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard traitCollection.horizontalSizeClass != lastHorizontalSizeClass else { return }
        lastHorizontalSizeClass = traitCollection.horizontalSizeClass
        refreshTabBar(animated: false)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if tabBarPresentationState == .minimized, !tabBar.canMinimize, navigationTransaction == nil {
            applyPresentationState(.expanded, animated: false, updatesSafeArea: false)
            scrollTracker.reset(to: .expanded)
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTabBarGeometry()
        updateChildSafeAreaInsets()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isContainerAppeared = true
        selectedViewController?.beginAppearanceTransition(true, animated: animated)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        selectedViewController?.endAppearanceTransition()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        selectedViewController?.beginAppearanceTransition(false, animated: animated)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        selectedViewController?.endAppearanceTransition()
        isContainerAppeared = false
    }

    // MARK: - Forwarding

    public override var childForStatusBarStyle: UIViewController? { selectedViewController }

    public override var childForStatusBarHidden: UIViewController? { selectedViewController }

    public override var childForHomeIndicatorAutoHidden: UIViewController? { selectedViewController }

    public override var childForScreenEdgesDeferringSystemGestures: UIViewController? { selectedViewController }

    // 方向宣告沿同一條鏈往下問（2.0 計畫書 §43）：Tab → 選取的子節點 → stack 的 top。
    // 少了這兩個覆寫，stack 容器算出來的值就停在中間，系統永遠問不到最上層那一個。
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        selectedViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
    }

    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        selectedViewController?.preferredInterfaceOrientationForPresentation
            ?? super.preferredInterfaceOrientationForPresentation
    }

    // MARK: - Tabs

    @objc(setTabs:selectedIdentifier:animated:)
    public func setTabs(_ newTabs: [TeroTab], selectedIdentifier: String?, animated: Bool) {
        TeroDiagnostics.assertMainThread()

        selectionRevision += 1
        navigationTransaction = nil
        let sanitized = Self.removingDuplicateIdentifiers(newTabs)
        let previousIdentifier = selectedTab?.identifier
        let previousViewController = selectedViewController

        // 判準是 view controller 的身分而非 identifier：同一個 identifier 若換成新的
        // TeroTab 實例（帶著不同的 view controller），舊的 view controller 也必須卸除。
        let retainedViewControllers = sanitized.map(\.viewController)
        let removed = tabs.filter { existing in
            !retainedViewControllers.contains { $0 === existing.viewController }
        }

        tabs = sanitized
        for tab in tabs {
            attachChild(tab.viewController)
        }

        let target: TeroTab?
        if let selectedIdentifier,
           let match = tabs.first(where: { $0.identifier == selectedIdentifier }) {
            target = match
        } else if let previousIdentifier,
                  let match = tabs.first(where: { $0.identifier == previousIdentifier }) {
            target = match
        } else {
            target = tabs.first
        }

        selectedTab = target
        selectedIndex = target.flatMap { candidate in
            tabs.firstIndex { $0 === candidate }
        } ?? NSNotFound

        if target?.viewController !== previousViewController {
            swapContent(from: previousViewController, to: target?.viewController, animated: animated)
        }

        for tab in removed {
            detachChild(tab.viewController)
        }

        updateChildSafeAreaInsets()
        refreshTabBar(animated: false)
        refreshScrollTracking()

        // identity 以 identifier 為準：同一個 identifier 仍被選取就不算選取變更，不發事件。
        if let target, target.identifier != previousIdentifier {
            delegate?.teroTabBarController?(self, didSelect: target, source: .initial)
        }
    }

    // MARK: - Reload

    /// 重算 title、image、`isEnabled`、accessibility 與 badge。
    @objc(reloadTabWithIdentifier:animated:)
    public func reloadTab(withIdentifier identifier: String, animated: Bool) {
        TeroDiagnostics.assertMainThread()
        guard tabs.contains(where: { $0.identifier == identifier }) else { return }
        refreshTabBar(animated: animated)
    }

    @objc(reloadAllTabsAnimated:)
    public func reloadAllTabs(animated: Bool) {
        TeroDiagnostics.assertMainThread()
        refreshTabBar(animated: animated)
    }

    /// 建議的 runtime Badge 更新入口（計畫書 §30）。
    @objc(setBadge:forTabWithIdentifier:animated:)
    public func setBadge(
        _ badge: TeroTabBadge?,
        forTabWithIdentifier identifier: String,
        animated: Bool
    ) {
        TeroDiagnostics.assertMainThread()
        guard let index = tabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        tabs[index].item.badge = badge
        refreshTabBar(animated: TeroAccessibility.resolvedAnimated(animated))
    }

    // MARK: - Scroll tracking

    /// Escape hatch：自訂容器切換 visible child、捲動視圖被替換、或複雜 pager 換頁時呼叫。
    /// Tab 切換會自動解析；導覽互動請從 Consumer 的 willShow 轉送 coordinateNavigationTransition。
    @objc(refreshScrollTracking)
    public func refreshScrollTracking() {
        TeroDiagnostics.assertMainThread()
        guard isViewLoaded else { return }

        guard navigationTransaction == nil else { return }
        refreshScrollTracking(for: visiblePage, resetTo: .expanded)
    }

    private var visiblePage: UIViewController? {
        if let navigation = selectedViewController as? UINavigationController {
            return navigation.topViewController
        }
        return selectedViewController
    }

    private func pagePolicy(_ page: UIViewController?) -> TeroTabVisibilityPolicy {
        (page as? TeroTabVisibilityProviding)?.preferredTeroTabVisibilityPolicy ?? .inherit
    }

    /// 頁面對 Bar 介面風格的宣告；沒有宣告就跟隨系統（`TeroTabBarAppearanceProviding`）。
    private func pageInterfaceStyle(_ page: UIViewController?) -> UIUserInterfaceStyle {
        (page as? TeroTabBarAppearanceProviding)?.preferredTeroTabBarUserInterfaceStyle ?? .unspecified
    }

    private func refreshScrollTracking(for page: UIViewController?, resetTo fallback: TeroTabBarPresentationState) {
        lastResolvedPage = page
        page?.loadViewIfNeeded()
        // Bar 的介面風格跟著可見頁面走，與 policy 同一個解析時點。
        tabBar.overrideUserInterfaceStyle = pageInterfaceStyle(page)
        // 兩個協定分開解析：輸入是共用的，偏好是 Tab Bar 專屬的（B6）。
        let scrollView = trackingScrollView(of: page)
        let behaviorProvider = scrollBehaviorProvider(of: page)
        scrollTracker.configuration = TeroTabScrollStateMachine.Configuration(
            behavior: effectiveScrollBehavior(for: behaviorProvider),
            downwardTranslationThreshold: storedConfiguration.scrollConfiguration.downwardTranslationThreshold,
            upwardTranslationThreshold: storedConfiguration.scrollConfiguration.upwardTranslationThreshold,
            velocityThreshold: storedConfiguration.scrollConfiguration.velocityThreshold,
            directionLockDistance: storedConfiguration.scrollConfiguration.directionLockDistance
        )
        let policy = pagePolicy(page)
        let state = visibilityResolver.resolve(locked: isPresentationStateLocked, policy: policy, scroll: fallback)
        scrollTracker.isLocked = isPresentationStateLocked || policy != .inherit
        scrollTracker.track(scrollView, resetTo: state)
        reservedPresentationState = isPresentationStateLocked || policy == .hidden ? .hidden : .expanded
        applyPresentationState(state, animated: tabBar.isVisibilityTransitionRunning, updatesSafeArea: false)
        updateChildSafeAreaInsets()
        // 邊緣互動最後才接：它一裝上 UIKit 就重跑 Bar 的 updateProperties，夾在上面那幾次
        // 強制 layout 中間會被 observation tracking 判成回饋迴圈（issue #102）。
        tabBar.updateScrollEdgeSource(state == .hidden ? nil : scrollView)
    }

    /// 從既有 UINavigationControllerDelegate.willShow 轉送；不接管 delegate。
    /// Bar 位於 Navigation 容器外，因此使用 alongsideTransition(in:animation:completion:)。
    @objc(coordinateNavigationTransition:toViewController:animated:)
    public func coordinateNavigationTransition(
        _ navigationController: UINavigationController,
        to destination: UIViewController,
        animated: Bool
    ) {
        TeroDiagnostics.assertMainThread()
        guard selectedViewController === navigationController else { return }
        loadViewIfNeeded()
        let coordinator = animated ? navigationController.transitionCoordinator : nil
        let coordinatorID = coordinator.map { ObjectIdentifier($0 as AnyObject) }
        if let current = navigationTransaction, current.coordinatorID == coordinatorID,
           coordinatorID != nil { return }
        let source = coordinator?.viewController(forKey: .from) ?? lastResolvedPage
        if let source { pageStates.setObject(NSNumber(value: tabBarPresentationState.rawValue), forKey: source) }
        let restored = pageStates.object(forKey: destination)
            .flatMap { TeroTabBarPresentationState(rawValue: $0.intValue) } ?? .expanded
        let target = visibilityResolver.resolve(
            locked: isPresentationStateLocked, policy: pagePolicy(destination), scroll: restored
        )
        let transaction = NavigationTransaction(
            id: UUID(), coordinatorID: coordinatorID, source: source, destination: destination,
            sourceState: tabBarPresentationState, destinationState: target, reserved: reservedPresentationState
        )
        navigationTransaction = transaction
        scrollTracker.isLocked = true
        guard let coordinator else {
            finishNavigation(transaction.id, cancelled: false)
            return
        }
        view.layoutIfNeeded()
        let registered = coordinator.animateAlongsideTransition(in: view, animation: { [weak self] _ in
            guard let self, self.navigationTransaction?.id == transaction.id else { return }
            self.previewNavigation(transaction.destinationState)
        }, completion: { [weak self] context in
            self?.finishNavigation(transaction.id, cancelled: context.isCancelled)
        })
        if !registered {
            // 即使 alongside 無法登記，completion 仍可能呼叫；id 讓重複結算無效。
            finishNavigation(transaction.id, cancelled: coordinator.isCancelled)
        }
    }

    // MARK: - 自建 stack 容器的轉場（Phase 9）

    /// 開始一段由 `TeroNavigationContainer` 驅動的轉場，回傳 transaction id。
    ///
    /// 與 `coordinateNavigationTransition` 做同一件事，差別在於**沒有
    /// `UIViewControllerTransitionCoordinator` 可用**——2.0 的容器自己跑
    /// `UIViewPropertyAnimator`，不產生那個協定（ADR-0014 取代 ADR-0011 的理由）。
    /// 因此 preview 與結算改由容器在自己的時點回呼，而不是掛 alongside。
    @discardableResult
    internal func beginContainerNavigation(
        from source: UIViewController?,
        to destination: UIViewController,
        animated: Bool
    ) -> UUID? {
        guard isViewLoaded else { return nil }
        if let source { pageStates.setObject(NSNumber(value: tabBarPresentationState.rawValue), forKey: source) }
        let restored = pageStates.object(forKey: destination)
            .flatMap { TeroTabBarPresentationState(rawValue: $0.intValue) } ?? .expanded
        let target = visibilityResolver.resolve(
            locked: isPresentationStateLocked, policy: pagePolicy(destination), scroll: restored
        )
        let transaction = NavigationTransaction(
            id: UUID(), coordinatorID: nil, source: source, destination: destination,
            sourceState: tabBarPresentationState, destinationState: target, reserved: reservedPresentationState
        )
        navigationTransaction = transaction
        scrollTracker.isLocked = true

        guard animated else {
            finishNavigation(transaction.id, cancelled: false)
            return nil
        }
        view.layoutIfNeeded()
        previewNavigation(transaction.destinationState)
        return transaction.id
    }

    /// 結算一段容器轉場。`cancelled` 為 true 時回到來源狀態。
    internal func endContainerNavigation(_ id: UUID, cancelled: Bool) {
        finishNavigation(id, cancelled: cancelled)
    }

    private func previewNavigation(_ state: TeroTabBarPresentationState) {
        let resolved = isPresentationStateLocked ? TeroTabBarPresentationState.hidden : state
        tabBar.apply(presentationState: resolved, animated: false)
        updateTabBarGeometry(state: resolved)
        view.layoutIfNeeded()
    }

    private func finishNavigation(_ id: UUID, cancelled: Bool) {
        guard let transaction = navigationTransaction, transaction.id == id else { return }
        navigationTransaction = nil
        let state = isPresentationStateLocked ? .hidden
            : (cancelled ? transaction.sourceState : transaction.destinationState)
        reservedPresentationState = cancelled ? transaction.reserved : (state == .hidden ? .hidden : .expanded)
        let page = cancelled ? transaction.source : transaction.destination
        visibilityCoordinator.move(to: state == .hidden ? 0 : 1, duration: 0, animated: false)
        previewNavigation(state)
        refreshScrollTracking(for: page ?? visiblePage, resetTo: state)
        if cancelled, !isPresentationStateLocked {
            reservedPresentationState = transaction.reserved
            updateChildSafeAreaInsets()
        }
    }

    private func trackingScrollView(of page: UIViewController?) -> UIScrollView? {
        (page as? TeroScrollProviding)?.teroTrackingScrollView
    }

    private func scrollBehaviorProvider(of page: UIViewController?) -> TeroTabBarScrollBehaviorProviding? {
        page as? TeroTabBarScrollBehaviorProviding
    }

    private func effectiveScrollBehavior(
        for provider: TeroTabBarScrollBehaviorProviding?
    ) -> TeroTabBarScrollBehavior {
        behaviorResolver.resolve(
            preferred: provider?.preferredTeroTabBarScrollBehavior,
            configured: storedConfiguration.scrollConfiguration.behavior,
            style: tabBarStyle
        )
    }

    // MARK: - Presentation state

    /// Classic 不支援 `.minimized`，收到時回傳 false（計畫書 §14）。
    ///
    /// `.hidden` 會進入鎖定，捲動驅動的變更失效；`.expanded` 同時就是解鎖動作（ADR-0004）。
    @discardableResult
    @objc(setTabBarPresentationState:animated:)
    public func setTabBarPresentationState(
        _ state: TeroTabBarPresentationState,
        animated: Bool
    ) -> Bool {
        TeroDiagnostics.assertMainThread()

        guard state != .minimized || (tabBarStyle == .floatingGlass && (!isViewLoaded || tabBar.canMinimize)) else { return false }

        switch state {
        case .hidden:
            isPresentationStateLocked = true
        case .expanded:
            isPresentationStateLocked = false
        case .minimized:
            break
        }

        let resolved = visibilityResolver.resolve(
            locked: isPresentationStateLocked,
            navigation: navigationTransaction?.destinationState,
            policy: pagePolicy(visiblePage), scroll: state
        )
        applyPresentationState(resolved, animated: animated, updatesSafeArea: true)
        if navigationTransaction != nil { previewNavigation(resolved) }
        scrollTracker.isLocked = isPresentationStateLocked || navigationTransaction != nil || pagePolicy(visiblePage) != .inherit
        scrollTracker.reset(to: resolved)
        return true
    }

    /// 捲動驅動的變更走這裡：**不更動 safe area**，避免與捲動觀察形成回授迴圈（ADR-0004）。
    internal func applyScrollDrivenPresentationState(
        _ state: TeroTabBarPresentationState,
        animated: Bool
    ) {
        guard !isPresentationStateLocked, navigationTransaction == nil, pagePolicy(visiblePage) == .inherit else { return }
        guard state != .minimized || tabBar.canMinimize else { return }
        reservedPresentationState = .expanded
        applyPresentationState(state, animated: animated, updatesSafeArea: false)
        updateChildSafeAreaInsets()
    }

    private func applyPresentationState(
        _ state: TeroTabBarPresentationState,
        animated requestedAnimated: Bool,
        updatesSafeArea: Bool
    ) {
        presentationRevision += 1
        let revision = presentationRevision
        if updatesSafeArea { reservedPresentationState = state }
        if isViewLoaded {
            // 明確 layout 起點；數值可見度與最小化分別驅動同一個幾何計算。
            view.layoutIfNeeded()
        }
        guard state != tabBarPresentationState else {
            if tabBar.presentationState != state {
                tabBar.apply(presentationState: state, animated: false)
                visibilityCoordinator.move(to: state == .hidden ? 0 : 1, duration: 0, animated: false)
                updateTabBarGeometry()
                view.layoutIfNeeded()
            }
            if updatesSafeArea { updateChildSafeAreaInsets() }
            return
        }
        let animated = TeroAccessibility.resolvedAnimated(requestedAnimated)

        delegate?.teroTabBarController?(self, willChangeTabBarPresentationState: state)
        guard presentationRevision == revision else { return }

        tabBarPresentationState = state
        tabBar.apply(presentationState: state, animated: animated)
        guard presentationRevision == revision else { return }
        tabBar.isUserInteractionEnabled = state != .hidden
        tabBar.accessibilityElementsHidden = state == .hidden

        guard isViewLoaded else {
            tabBar.updateScrollEdgeSource(state == .hidden ? nil : scrollTracker.trackedScrollView)
            delegate?.teroTabBarController?(self, didChangeTabBarPresentationState: state)
            return
        }

        updateTabBarGeometry()
        if updatesSafeArea { updateChildSafeAreaInsets() }

        visibilityCoordinator.move(
            to: state == .hidden ? 0 : 1,
            duration: storedConfiguration.motion.restoreDuration,
            animated: animated
        )
        view.layoutIfNeeded()
        // 同上：邊緣互動在強制 layout 之後才接（issue #102）。
        tabBar.updateScrollEdgeSource(state == .hidden ? nil : scrollTracker.trackedScrollView)

        // didChange 的語意是「狀態已變更」，不是「動畫已結束」。
        delegate?.teroTabBarController?(self, didChangeTabBarPresentationState: state)
    }

    // MARK: - Action

    /// Classic 保留 Action 的狀態並顯示於 Bar 中央；FloatingGlass 顯示於 Bar 之外（ADR-0003）。
    @objc(setActionItem:animated:)
    public func setActionItem(_ actionItem: TeroTabActionItem?, animated: Bool) {
        TeroDiagnostics.assertMainThread()
        self.actionItem = actionItem
        refreshTabBar(animated: animated)
        updateTabBarGeometry()
        updateChildSafeAreaInsets()
    }

    /// Action 只發出自己的事件，不影響選取（計畫書 §11）。
    private func triggerAction() {
        guard let actionItem, actionItem.isEnabled else { return }
        delegate?.teroTabBarController?(self, didTrigger: actionItem)
    }

    // MARK: - Selection

    @discardableResult
    @objc(selectTabWithIdentifier:animated:)
    public func selectTab(withIdentifier identifier: String, animated: Bool) -> Bool {
        TeroDiagnostics.assertMainThread()
        guard let index = tabs.firstIndex(where: { $0.identifier == identifier }) else {
            return false
        }
        return select(tabs[index], at: index, source: .programmatic, animated: animated)
    }

    @discardableResult
    @objc(selectTabAtIndex:animated:)
    public func selectTab(at index: Int, animated: Bool) -> Bool {
        TeroDiagnostics.assertMainThread()
        guard tabs.indices.contains(index) else {
            return false
        }
        return select(tabs[index], at: index, source: .programmatic, animated: animated)
    }

    @discardableResult
    internal func select(
        _ tab: TeroTab,
        at index: Int,
        source: TeroTabSelectionSource,
        animated: Bool
    ) -> Bool {
        guard tab.item.isEnabled else { return false }

        if tab.identifier == selectedTab?.identifier {
            // 重複點擊事件專屬於使用者互動；程式呼叫不觸發，以免造成非預期的導覽重置。
            if source == .user {
                // 只留選取格的最小化膠囊上只有這一格：點它是「展開」，不是「重選」（issue #93）。
                if tabBarPresentationState == .minimized,
                   storedConfiguration.floatingGlassAppearance.minimizedLayout == .selectedOnly {
                    applyScrollDrivenPresentationState(.expanded, animated: true)
                    scrollTracker.reset(to: .expanded)
                    return true
                }
                // Bar 自己給回饋，但仍然不做 popToRoot / scrollToTop——
                // 那是 App 的決定，套件只回報事件（計畫書 §12、補充規格 §12）。
                tabBar.playReselectFeedback()
                delegate?.teroTabBarController?(self, didReselect: tab)
            }
            return true
        }

        selectionRevision += 1
        let revision = selectionRevision
        if source != .initial,
           let allowed = delegate?.teroTabBarController?(self, shouldSelect: tab, source: source),
           allowed == false {
            return false
        }

        guard selectionRevision == revision, tabs.indices.contains(index), tabs[index] === tab else { return false }
        let previousViewController = selectedViewController
        let resolvedAnimated = TeroAccessibility.resolvedAnimated(animated)
        navigationTransaction = nil
        selectedTab = tab
        selectedIndex = index
        swapContent(from: previousViewController, to: tab.viewController, animated: resolvedAnimated)
        // Bar 收到的是**呼叫端要求的**動畫意圖，不是已經被減少動態效果收掉的結果：
        // 要不要、以及怎麼降級（交叉淡入或直接換狀態）是 Bar 的決定，
        // 在這裡先收掉的話 Bar 就分不出「不要動畫」和「要動畫但必須降級」。
        refreshTabBar(animated: animated)
        // 新 Tab 預設展開（計畫書 §40），除非處於程式鎖定。
        guard selectionRevision == revision else { return true }
        refreshScrollTracking()
        guard selectionRevision == revision else { return true }
        delegate?.teroTabBarController?(self, didSelect: tab, source: source)
        return true
    }

    private func selectVisibleItem(at visibleIndex: Int) {
        let indices = overflowResolution.visibleIndices
        guard indices.indices.contains(visibleIndex) else { return }
        let tabIndex = indices[visibleIndex]
        guard tabs.indices.contains(tabIndex) else { return }
        select(tabs[tabIndex], at: tabIndex, source: .user, animated: true)
    }

    // MARK: - 長按

    /// 只在 delegate 聽的時候才裝辨識器：沒有人聽，Bar 就不該多攔一種手勢。
    private func updateLongPressAvailability() {
        let selector = #selector(TeroTabBarControllerDelegate.teroTabBarController(_:didLongPress:))
        tabBar.isLongPressEnabled = delegate?.responds(to: selector) ?? false
    }

    /// 長按只發事件，不改選取——要不要開帳號切換、要不要 popToRoot 是 App 的決定。
    private func longPressVisibleItem(at visibleIndex: Int) {
        let indices = overflowResolution.visibleIndices
        guard indices.indices.contains(visibleIndex) else { return }
        let tabIndex = indices[visibleIndex]
        guard tabs.indices.contains(tabIndex), tabs[tabIndex].item.isEnabled else { return }
        delegate?.teroTabBarController?(self, didLongPress: tabs[tabIndex])
    }

    // MARK: - Overflow

    private func refreshTabBar(animated: Bool) {
        guard isViewLoaded else { return }

        let resolution = overflowResolution
        var model = TeroTabBar.Model()
        model.items = resolution.visibleIndices.map {
            TeroTabItemPresentation(key: tabs[$0].identifier, item: tabs[$0].item)
        }
        model.selectedItemIndex = resolution.visibleIndices.firstIndex(of: selectedIndex)

        if resolution.showsMore {
            model.more = TeroTabItemPresentation(
                moreItem: storedConfiguration.moreItem,
                badge: Self.overflowBadge(for: resolution.overflowIndices.map { tabs[$0] })
            )
            model.isMoreSelected = resolution.overflowIndices.contains(selectedIndex)
        }

        if let actionItem {
            model.action = TeroTabItemPresentation(actionItem: actionItem)
        }

        // Overflow 的 Tab 仍屬於列表，其自訂內容要保留，回到可見時才不必重新載入。
        tabBar.retainedContentKeys = Set(resolution.overflowIndices.map { tabs[$0].identifier })
        tabBar.apply(model: model, animated: animated)
        tabBar.moreMenu = makeOverflowMenuIfNeeded()
    }

    /// 任一 Overflow Tab 有 Badge 時 More 顯示圓點。V1 不做數值加總（計畫書 §43）。
    private static func overflowBadge(for overflowTabs: [TeroTab]) -> TeroTabBadge? {
        overflowTabs.contains { $0.item.badge != nil } ? .dot() : nil
    }

    private var effectiveMorePresentationStyle: TeroTabMorePresentationStyle {
        switch storedConfiguration.morePresentationStyle {
        case .automatic:
            return .menu
        case .menu, .sheet, .popover:
            return storedConfiguration.morePresentationStyle
        }
    }

    private func makeOverflowMenuIfNeeded() -> UIMenu? {
        guard effectiveMorePresentationStyle == .menu else { return nil }
        return makeOverflowMenu()
    }

    private func makeOverflowMenu() -> UIMenu? {
        let indices = overflowResolution.overflowIndices
        guard !indices.isEmpty else { return nil }

        let actions: [UIAction] = indices.map { index in
            let tab = tabs[index]
            // Overflow 選單不 render 自訂內容，圖示依序退回（計畫書 §43）。
            let image = tab.item.overflowImage ?? tab.item.image
            let action = UIAction(
                title: tab.item.title ?? tab.identifier,
                image: image,
                state: index == selectedIndex ? .on : .off
            ) { [weak self] _ in
                guard let self, self.tabs.indices.contains(index) else { return }
                self.select(self.tabs[index], at: index, source: .overflow, animated: true)
            }
            if !tab.item.isEnabled {
                action.attributes = .disabled
            }
            return action
        }
        return UIMenu(title: storedConfiguration.moreItem.title ?? "", children: actions)
    }

    /// `.menu` 由選單自己接手（掛在 More 控制項上），因此只有 sheet / popover 走這裡。
    private func presentOverflow() {
        let indices = overflowResolution.overflowIndices
        guard !indices.isEmpty else { return }

        let controller = UIAlertController(
            title: storedConfiguration.moreItem.title,
            message: nil,
            preferredStyle: .actionSheet
        )
        for index in indices {
            let tab = tabs[index]
            let action = UIAlertAction(title: tab.item.title ?? tab.identifier, style: .default) { [weak self] _ in
                guard let self, self.tabs.indices.contains(index) else { return }
                self.select(self.tabs[index], at: index, source: .overflow, animated: true)
            }
            action.isEnabled = tab.item.isEnabled
            controller.addAction(action)
        }
        // `.popover` 在不適合的環境由 UIKit 自動退回 sheet（計畫書 §18）。
        controller.popoverPresentationController?.sourceView = tabBar
        controller.popoverPresentationController?.sourceRect = tabBar.bounds
        present(controller, animated: true)
    }

    // MARK: - Layout helpers

    /// Bar 的幾何。Classic 貼齊底部滿版；FloatingGlass 浮在底部上方一段距離。
    /// `.hidden` 時整條推到畫面之外——那是真正的重新排版，不是改 alpha。
    private func updateTabBarGeometry(state preview: TeroTabBarPresentationState? = nil) {
        guard isViewLoaded else { return }

        let state = preview ?? tabBarPresentationState
        let safeBottom = view.safeAreaInsets.bottom
        let contentHeight = preview == nil ? tabBar.contentHeight : tabBar.contentHeight(for: state)
        let floatingInset = tabBar.floatingBottomInset

        switch tabBarStyle {
        case .classic:
            tabBarHeightConstraint?.constant = contentHeight + safeBottom
        case .floatingGlass:
            tabBarHeightConstraint?.constant = contentHeight
        }

        // FloatingGlass 的 `bottomInset` 從**螢幕邊緣**量起，不疊在安全區之上。
        //
        // 疊加的話 Bar 永遠落在 home indicator 那條帶子**外面**，比系統原生的浮動 Tab Bar
        // 高一個安全區；而且 `bottomInset` 設成 0 也只能貼到安全區上緣，追不下去——
        // 那個位置在舊規則下根本無法表達。同一組 appearance 裡的 `horizontalInset` 本來
        // 就是從螢幕邊緣量的，兩個 inset 基準不一致本身就是個坑。
        let visibleBottom: CGFloat = tabBarStyle == .classic ? 0 : -floatingInset
        let hiddenBottom = (tabBarHeightConstraint?.constant ?? 0) + floatingInset
        let visibility: CGFloat = preview == nil ? visibilityCoordinator.progress : (state == .hidden ? 0 : 1)
        tabBarBottomConstraint?.constant = hiddenBottom + (visibleBottom - hiddenBottom) * visibility
    }

    /// 子畫面的 safe area 必須避開 Bar。
    ///
    /// FloatingGlass 的 Bar 從螢幕邊緣量起，因此它有一段落在 home indicator 那條帶子
    /// **裡面**——那一段本來就在視窗自身的 safe area 裡，不能重複加。扣掉之後子畫面的
    /// 內容底邊正好貼齊 Bar 的頂邊：不重疊，也不會空出一段等於安全區的死空間。
    ///
    /// Classic 貼齊底部滿版，`contentHeight` 本來就不含安全區，維持原樣。
    private func updateChildSafeAreaInsets() {
        guard isViewLoaded else { return }
        let reserved = tabBar.contentHeight(for: reservedPresentationState) + tabBar.floatingBottomInset
        let inset = reservedPresentationState == .hidden
            ? 0
            : (tabBarStyle == .floatingGlass
                ? max(0, reserved - view.safeAreaInsets.bottom)
                : reserved)
        // 包在 withoutTracking 裡：寫 inset 會移動 contentOffset，不擋住的話
        // 下一筆取樣會把它讀成使用者捲動（§31 的回授迴圈）。
        scrollTracker.withoutTracking {
            for child in children {
                safeAreaLedger.apply(inset, to: child)
            }
        }
    }

    // MARK: - Containment

    private func attachChild(_ viewController: UIViewController) {
        guard viewController.parent !== self else { return }
        addChild(viewController)
        viewController.didMove(toParent: self)
        observeContainerNavigation(of: viewController)
    }

    /// 掛上對 stack 容器的觀察。
    ///
    /// **只對選取中的那一個生效**：所有 tab 的容器都會被掛上，但非選取的容器
    /// 轉場時不該改變 Tab Bar——1.x 在 `coordinateNavigationTransition` 用
    /// `selectedViewController === navigationController` 擋掉，這裡用同一條判斷。
    private func observeContainerNavigation(of viewController: UIViewController) {
        guard let container = viewController as? TeroNavigationContainer else { return }
        // 樣本由這裡的追蹤路徑餵給容器；容器自己的追蹤器停用，同一個 scroll view 不會有兩個觀察者。
        container.receivesExternalScrollSamples = true
        container.onNavigationTransition = { [weak self, weak container] source, destination, animated in
            guard let self, let container, self.selectedViewController === container else { return nil }
            return self.beginContainerNavigation(from: source, to: destination, animated: animated)
        }
        container.onNavigationTransitionEnd = { [weak self, weak container] id, cancelled in
            guard let self, let container, self.selectedViewController === container else { return }
            self.endContainerNavigation(id, cancelled: cancelled)
        }
    }

    private func detachChild(_ viewController: UIViewController) {
        if let container = viewController as? TeroNavigationContainer {
            container.onNavigationTransition = nil
            container.onNavigationTransitionEnd = nil
            container.receivesExternalScrollSamples = false
        }
        safeAreaLedger.release(viewController)
        guard viewController.parent === self else { return }
        viewController.willMove(toParent: nil)
        if viewController.viewIfLoaded?.superview === contentContainer {
            viewController.viewIfLoaded?.removeFromSuperview()
        }
        viewController.removeFromParent()
    }

    private func swapContent(
        from oldViewController: UIViewController?,
        to newViewController: UIViewController?,
        animated: Bool
    ) {
        guard isViewLoaded else { return }  // viewDidLoad 會補上安裝

        let notifiesAppearance = isContainerAppeared

        if notifiesAppearance {
            oldViewController?.beginAppearanceTransition(false, animated: animated)
            newViewController?.beginAppearanceTransition(true, animated: animated)
        }

        if let oldViewController,
           oldViewController.viewIfLoaded?.superview === contentContainer {
            oldViewController.viewIfLoaded?.removeFromSuperview()
        }
        if let newViewController {
            installContentView(of: newViewController)
        }

        if notifiesAppearance {
            oldViewController?.endAppearanceTransition()
            newViewController?.endAppearanceTransition()
        }

        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    private func installContentView(of viewController: UIViewController) {
        let contentView = viewController.view!
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.insertSubview(contentView, at: 0)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
    }

    private static func removingDuplicateIdentifiers(_ tabs: [TeroTab]) -> [TeroTab] {
        var seen = Set<String>()
        var result: [TeroTab] = []
        for tab in tabs {
            if seen.insert(tab.identifier).inserted {
                result.append(tab)
            } else {
                TeroDiagnostics.report("Tab identifier 重複：\(tab.identifier)。保留第一個，忽略其餘。")
            }
        }
        return result
    }
}

extension TeroTabBarController {

    /// `selectedIndex` 的 optional 形式，省去與 `NSNotFound` 比對。兩者永遠一致。
    @nonobjc public var selectedTabIndex: Int? {
        selectedIndex == NSNotFound ? nil : selectedIndex
    }
}
