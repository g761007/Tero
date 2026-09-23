import UIKit

/// Tab Bar 的視圖。可讀取，但不支援 consumer 自行實例化——
/// 所有導覽與狀態變更都透過 `TeroTabBarController`。
///
/// 註：`init(frame:)` 必須明確標記 unavailable，否則會從 `UIView` 繼承而來。
public final class TeroTabBar: UIView {

    @objc public private(set) var style: TeroTabBarStyle

    @objc public private(set) var presentationState: TeroTabBarPresentationState = .expanded

    // MARK: - Internal model

    /// Bar 要畫什麼。把可見 Tab 與 More 收斂成一份資料，
    /// 版面因此不需要知道哪一格是 More。
    internal struct Model {
        internal var items: [TeroTabItemPresentation] = []
        internal var more: TeroTabItemPresentation?
        /// Action 是獨立指令，不參與選取（計畫書 §11）。
        internal var action: TeroTabItemPresentation?
        /// `items` 內的索引；選取落在 More 時為 nil。
        internal var selectedItemIndex: Int?
        internal var isMoreSelected: Bool = false
    }

    internal var onSelectItem: ((Int) -> Void)?
    internal var onSelectMore: (() -> Void)?
    internal var onTriggerAction: (() -> Void)?
    /// 長按某一格（`itemViews` 的索引）。More 與 Action 不發（issue #96）。
    internal var onLongPressItem: ((Int) -> Void)?

    /// 由 controller 依 delegate 有沒有實作長按回呼設定。沒有人聽，Bar 就不多攔一種手勢。
    internal var isLongPressEnabled = false {
        didSet { applySwipeSelectionMode() }
    }

    /// 滑動選取的操作方式。`.disabled` 時手勢完全停用，行為與只能點擊時相同。
    internal var swipeSelectionMode: TeroTabSwipeSelectionMode = .disabled {
        didSet { applySwipeSelectionMode() }
    }

    private lazy var panRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.isEnabled = false
        return recognizer
    }()

    /// `.drag` 的驅動者。
    ///
    /// **不能用 pan**：pan 要等約 10pt 的 slop 才 `.began`，所以「手指按住不動」完全沒
    /// 反應——而 `.drag` 的契約是「連續跟隨手指」。零秒 long press 在 touch-down 當下
    /// 就 `.began`。
    ///
    /// `allowableMovement` 放到最大，否則手指一移動 long press 就被判失敗；
    /// `cancelsTouchesInView = false` 與同時辨識則是為了不吃掉 Tab 自己的點擊。
    private lazy var dragRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleDragGesture(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.allowableMovement = .greatestFiniteMagnitude
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = dragGestureDelegate
        recognizer.isEnabled = false
        dragGestureDelegate.dragRecognizer = recognizer
        return recognizer
    }()

    /// 代理獨立成內部型別，`TeroTabBar` 的公開介面才不會多出手勢代理的方法。
    private let dragGestureDelegate = TeroTabDragGestureDelegate()

    /// 長按一格的辨識器（issue #96）。半秒；辨識成功時 UIKit 會取消 Tab 自己的點擊，
    /// 所以長按不會順帶選取。
    private lazy var longPressRecognizer: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGesture(_:)))
        recognizer.minimumPressDuration = 0.5
        recognizer.isEnabled = false
        return recognizer
    }()

    private func applySwipeSelectionMode() {
        panRecognizer.isEnabled = (swipeSelectionMode == .swipe)
        dragRecognizer.isEnabled = (swipeSelectionMode == .drag)
        // `.drag` 由零秒長按驅動、touch-down 當下就接手，半秒的長按永遠等不到——兩者互斥。
        longPressRecognizer.isEnabled = isLongPressEnabled && swipeSelectionMode != .drag
    }

    private var isDraggingIndicator = false
    private var dragStartFrame: CGRect = .zero
    private var lastDragFingerX: CGFloat = 0
    private var lastDragSampleTime: CFTimeInterval = 0
    private let swipeResolver = TeroTabSwipeSelectionResolver()

    /// `.menu` 樣式時掛在 More 上的選單。
    internal var moreMenu: UIMenu? {
        didSet { applyMoreMenu() }
    }

    // MARK: - Views

    /// 玻璃容器。iOS 26 上套 `UIGlassContainerEffect`，讓 Tabs 與 Action 的玻璃
    /// 在靠近時融合；其餘情況 effect 為 nil，只當單純的容器。
    /// 階層永遠一致，避免版面因為系統版本而長得不一樣。
    private let glassContainer = UIVisualEffectView(effect: nil)
    /// Tabs 的膠囊。Classic 下它填滿整個 Bar；FloatingGlass 下它是浮動的圓角區塊。
    private let tabsCapsule = UIVisualEffectView(effect: nil)
    /// Action 的膠囊。只有 FloatingGlass 會用到——Classic 的 Action 在 Tabs 列的中央。
    private let actionCapsule = UIVisualEffectView(effect: nil)
    private let separator = UIView()
    private let itemsContainer = UIView()
    private let selectionIndicator = TeroTabSelectionIndicatorView()
    /// 轉場中疊在玻璃之上的透鏡。靜止時不存在。
    ///
    /// 做成獨立的一層、而不是把 `selectionIndicator` 在轉場時搬到玻璃之上，
    /// 是因為搬動會改變它的座標系，滑動選取讀的 `selectionIndicator.frame`
    /// 就會和版面給的 `slotSelectionFrames` 對不起來（ADR-0010）。
    private let selectionLens = TeroTabSelectionIndicatorView()
    /// 非繪製的選取時間軸。Selection 與可見度都由 renderSelectionGeometry 寫入實際膠囊。
    private let selectionDriver = UIView()
    private let visibilityCoordinator = TeroTabVisibilityCoordinator()
    internal var onVisibilityGeometryChange: (() -> Void)?
    internal private(set) var minimizationProgress: CGFloat = 0
    private var modelRevision = 0
    private var accessibilityObservers: [NSObjectProtocol] = []
    internal var isVisibilityTransitionRunning: Bool { visibilityCoordinator.isRunning }
    private var layoutSnapshots: (expanded: TeroFloatingGlassLayoutEngine.Layout, minimized: TeroFloatingGlassLayoutEngine.Layout)?
    private var snapshotWidth: CGFloat = -1
    private var snapshotDirection: UIUserInterfaceLayoutDirection?
    private var selectionTransitionProgress: CGFloat = 1
    private let selectionCoordinator = TeroTabSelectionTransitionCoordinator()
    private var itemViews: [TeroTabItemView] = []
    private var moreView: TeroTabItemView?
    private var actionView: TeroTabItemView?

    private var model = Model()

    /// 自訂內容的快取。鍵是 Item 的穩定鍵，因此 Item 視圖被重建（例如進出 Overflow）
    /// 之後仍會對回同一份 view，不必重新載入動畫檔（計畫書 §9）。
    private var contentViews: [String: (provider: TeroTabContentProvider, view: UIView)] = [:]
    private var motion = TeroTabMotionConfiguration()
    private var itemAppearance = TeroTabItemAppearance()
    private var badgeAppearance = TeroTabBadgeAppearance()
    private var classicAppearance = TeroClassicTabBarAppearance()
    private var floatingAppearance = TeroFloatingGlassAppearance()
    private let classicLayoutEngine = TeroClassicLayoutEngine()
    private let floatingLayoutEngine = TeroFloatingGlassLayoutEngine()

    internal init(style: TeroTabBarStyle) {
        self.style = style
        super.init(frame: .zero)
        addSubview(glassContainer)
        glassContainer.contentView.addSubview(tabsCapsule)
        glassContainer.contentView.addSubview(actionCapsule)
        tabsCapsule.contentView.addSubview(separator)
        tabsCapsule.contentView.addSubview(itemsContainer)
        itemsContainer.addSubview(selectionIndicator)
        // 透鏡疊在整個玻璃容器之上，Icon 才會落進它取樣的 backdrop。
        addSubview(selectionLens)
        selectionLens.isHidden = true
        selectionDriver.isUserInteractionEnabled = false
        selectionDriver.alpha = 0.001
        selectionDriver.isHidden = false
        itemsContainer.addSubview(selectionDriver)
        selectionCoordinator.attach(to: selectionDriver)
        selectionCoordinator.onSegmentStart = { [weak self] slot, animated in
            self?.beginSelectionSegment(to: slot, animated: animated)
        }
        visibilityCoordinator.onUpdate = { [weak self] progress, animated in
            guard let self else { return }
            self.minimizationProgress = progress
            self.onVisibilityGeometryChange?()
            self.setNeedsLayout()
            self.layoutIfNeeded()
            self.notifyPresentationProgress(animated: animated)
        }
        selectionCoordinator.onProgress = { [weak self] progress in
            self?.applySelectionProgress(progress)
        }
        itemsContainer.addGestureRecognizer(panRecognizer)
        itemsContainer.addGestureRecognizer(dragRecognizer)
        itemsContainer.addGestureRecognizer(longPressRecognizer)
        observeAccessibilitySettings()
        observeResignActive()

        // 讓系統播報「第 N 項，共 M 項」。套件不得夾帶字串（ADR-0007），
        // 因此位置資訊交給 `.tabBar` trait 由系統在地化，而不是自己拼字串。
        isAccessibilityElement = false
        accessibilityTraits = .tabBar

        applyBackground()
    }

    deinit {
        accessibilityObservers.forEach(NotificationCenter.default.removeObserver)
    }

    @available(*, unavailable)
    public override init(frame: CGRect) {
        fatalError("TeroTabBar 不支援 consumer 自行實例化，請透過 TeroTabBarController 取用")
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("TeroTabBar 不支援 init(coder:)")
    }

    // MARK: - Internal API

    internal func apply(style: TeroTabBarStyle) {
        guard self.style != style else { return }
        self.style = style
        applyBackground()
        setNeedsLayout()
    }

    internal func apply(presentationState: TeroTabBarPresentationState, animated: Bool) {
        guard self.presentationState != presentationState else { return }
        self.presentationState = presentationState
        isUserInteractionEnabled = presentationState != .hidden
        accessibilityElementsHidden = presentationState == .hidden
        let target: CGFloat = presentationState == .minimized ? 1
            : (presentationState == .hidden ? minimizationProgress : 0)
        visibilityCoordinator.move(
            to: target,
            duration: target > minimizationProgress ? motion.minimizeDuration : motion.restoreDuration,
            animated: animated
        )
        // 不重設選取動畫或重建 Item；只發既有的離散 presentation 通知。
        let revision = modelRevision
        for (index, item) in model.items.enumerated() {
            notifyState(item, selected: model.selectedItemIndex == index, animated: animated)
            guard revision == modelRevision else { return }
        }
        if let more = model.more { notifyState(more, selected: model.isMoreSelected, animated: animated) }
        guard revision == modelRevision else { return }
        if let action = model.action { notifyState(action, selected: false, animated: animated) }
    }

    private func notifyState(_ item: TeroTabItemPresentation, selected: Bool, animated: Bool) {
        guard let cached = contentViews[item.key] else { return }
        cached.provider.updateContentView?(cached.view, selected: selected,
            presentationState: presentationState, animated: TeroAccessibility.resolvedAnimated(animated))
    }

    private func notifyPresentationProgress(animated: Bool) {
        let revision = modelRevision
        let cachedViews = Array(contentViews.values)
        for cached in cachedViews where cached.view.superview != nil {
            (cached.provider as? TeroTabInteractiveContentProvider)?.updateContentView?(
                cached.view, presentationProgress: minimizationProgress,
                animated: TeroAccessibility.resolvedAnimated(animated)
            )
            guard revision == modelRevision else { return }
        }
    }

    internal func apply(
        itemAppearance: TeroTabItemAppearance,
        badgeAppearance: TeroTabBadgeAppearance,
        classicAppearance: TeroClassicTabBarAppearance,
        floatingAppearance: TeroFloatingGlassAppearance,
        motion: TeroTabMotionConfiguration
    ) {
        layoutSnapshots = nil
        self.itemAppearance = itemAppearance
        self.badgeAppearance = badgeAppearance
        self.classicAppearance = classicAppearance
        self.floatingAppearance = floatingAppearance
        self.motion = motion
        selectionCoordinator.motion = motion
        applyBackground()
        apply(model: model, animated: false)
    }

    /// Tabs 與 More 的所有格位視圖，依顯示順序。Action 不在其中——它不是 Tab。
    private var slotViews: [TeroTabItemView] {
        var views = itemViews
        if let moreView { views.append(moreView) }
        return views
    }

    /// 目前選取落在哪一格。選取在 More 時是最後一格。
    private var selectedSlotIndex: Int? {
        if model.isMoreSelected, moreView != nil { return itemViews.count }
        return model.selectedItemIndex
    }

    /// `.automatic` 只在 FloatingGlass 顯示：貼底滿版的 Classic 沒有這個外框。
    private var showsSelectionIndicator: Bool {
        switch itemAppearance.selectionIndicatorStyle {
        case .always: return true
        case .never: return false
        case .automatic: return style == .floatingGlass
        }
    }

    /// Bar 的內容高度，不含 home indicator 安全區與浮動的底部內縮（計畫書 §21）。
    internal var contentHeight: CGFloat {
        let expanded = contentHeight(for: .expanded)
        return expanded + (contentHeight(for: .minimized) - expanded) * minimizationProgress
    }

    internal var canMinimize: Bool {
        guard style == .floatingGlass, !traitCollection.preferredContentSizeCategory.isAccessibilityCategory else { return false }
        let available = bounds.width - floatingAppearance.horizontalInset * 2
            - (model.action == nil ? 0 : max(44, floatingAppearance.minimizedHeight) + floatingAppearance.actionSpacing)
        // 只留選取格時只要放得下一格。
        let required: CGFloat = floatingAppearance.minimizedLayout == .selectedOnly ? 44 : CGFloat(slotViews.count) * 44
        return slotViews.isEmpty || available >= required
    }

    /// 最小化時只留選取格（issue #93）。
    private var minimizesToSelectedOnly: Bool {
        style == .floatingGlass && floatingAppearance.minimizedLayout == .selectedOnly
    }

    internal func contentHeight(for presentationState: TeroTabBarPresentationState) -> CGFloat {
        switch style {
        case .classic:
            return classicAppearance.barHeight
        case .floatingGlass:
            let capsule = presentationState == .minimized
                ? floatingAppearance.minimizedHeight
                : floatingAppearance.expandedHeight
            // 只有真的有 Action、且未最小化時，Action 才可能比膠囊高。
            guard model.action != nil, presentationState != .minimized else { return capsule }
            return max(capsule, floatingAppearance.actionSize.height)
        }
    }

    /// FloatingGlass 才有的底部內縮；Classic 為 0。
    internal var floatingBottomInset: CGFloat {
        style == .floatingGlass ? floatingAppearance.bottomInset : 0
    }

    internal func apply(model newModel: Model, animated: Bool) {
        let structureChanged =
            newModel.items.count != itemViews.count ||
            (newModel.more != nil) != (moreView != nil) ||
            (newModel.action != nil) != (actionView != nil)

        modelRevision += 1
        layoutSnapshots = nil
        model = newModel
        let revision = modelRevision

        if structureChanged {
            rebuildViews()
        }
        updateActionHost()
        if style == .floatingGlass {
            actionCapsule.isHidden = (model.action == nil)
        }

        pruneContentViews()

        let update = {
            for (index, presentation) in self.model.items.enumerated() where self.itemViews.indices.contains(index) {
                let selected = (self.model.selectedItemIndex == index)
                self.configure(self.itemViews[index], with: presentation, selected: selected, animated: animated)
                guard self.modelRevision == revision else { return }
            }
            if let more = self.model.more, let moreView = self.moreView {
                self.configure(moreView, with: more, selected: self.model.isMoreSelected, animated: animated)
            }
            if let action = self.model.action, let actionView = self.actionView {
                self.configure(actionView, with: action, selected: false, animated: animated)
            }
        }

        if TeroAccessibility.resolvedAnimated(animated) && !structureChanged {
            UIView.transition(with: itemsContainer, duration: 0.2, options: .transitionCrossDissolve, animations: update)
        } else {
            update()
        }
        guard modelRevision == revision else { return }
        applyMoreMenu()
        updateSelection(animated: animated && !structureChanged)
        setNeedsLayout()
    }

    // MARK: - Selection

    /// 每格目前的選取程度。轉場途中可能同時有多格介於 0 與 1 之間——
    /// A→B 還沒走完就改去 C 的話，A、B、C 三格都在動（補充規格 §13）。
    private var slotProgress: [CGFloat] = []
    /// 本段轉場起跑時各格的進度。逐幀由它往目標值插補。
    private var segmentStartProgress: [CGFloat] = []
    private var segmentTargetSlot: Int?
    /// 本段轉場是否在動畫中。轉給 provider 的 `animated` 用它。
    private var segmentAnimated = false
    /// 上一次版面算出來的各格選取外框，由 layout engine 提供（補充規格 §26）。
    private var slotSelectionFrames: [CGRect] = []

    private func updateSelection(animated: Bool) {
        let views = slotViews
        if slotProgress.count != views.count {
            slotProgress = Array(repeating: 0, count: views.count)
        }

        guard let slot = selectedSlotIndex, views.indices.contains(slot) else {
            clearSelection()
            return
        }

        guard let frame = selectionFrame(forSlot: slot, in: views),
              frame.width > 0, frame.height > 0 else {
            clearSelection()
            return
        }

        selectionIndicator.apply(material: resolvedIndicatorMaterial)
        // 外框即使不顯示也照常定位：整段轉場的時鐘掛在它的動畫上，
        // 而 Classic 沒有外框、Icon 的連續轉場卻一樣要跑（補充規格 §6）。
        selectionIndicator.isHidden = !showsSelectionIndicator
        if !selectionIndicator.isHidden, selectionLens.isHidden { selectionIndicator.alpha = 1 }

        // 拖曳中的位置由手指決定，不要被版面拉回去。
        guard !isDraggingIndicator else { return }

        let target = TeroTabSelectionTransitionCoordinator.Target(
            frame: CGRect(x: CGFloat(slot) * 100, y: 0, width: 100, height: 100),
            cornerRadius: 0,
            slot: slot
        )
        guard target != selectionCoordinator.target || !selectionCoordinator.isRunning else {
            renderSelectionGeometry()
            return
        }

        // 第一次定位沒有「上一個位置」可言，直接就位。
        let isFirstPlacement = (selectionCoordinator.target == nil)
        // 轉場途中重新排版（旋轉、iPad 改變視窗大小）要繼續動到新的終點，
        // 而不是因為這趟 layout 沒有要求動畫就把外框硬拉過去（補充規格 §23）。
        let shouldAnimate = (animated || selectionCoordinator.isRunning) && !isFirstPlacement

        let targetChanged = (target != selectionCoordinator.target)
        let update = {
            // 減少動態效果開啟時，provider 收到的 `animated` 必須是 false，
            // 它們才知道該停止播放（計畫書 §47）。
            self.selectionCoordinator.move(to: target, animated: shouldAnimate)
        }

        guard shouldAnimate, targetChanged, usesReducedMotionCrossFade else {
            update()
            return
        }
        // 淡入淡出整個 items 容器：外框與 Icon 一起交棒，才不會只有外框在閃。
        UIView.transition(
            with: itemsContainer,
            duration: motion.contentTransitionDuration,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: update
        )
    }

    // MARK: - Selection lens

    /// 這個樣式／環境下是否用透鏡。
    ///
    /// 「減少動態效果」時不用——透鏡是動態效果的一部分，不是選取狀態本身。
    ///
    /// `.solid` 也不用。那個 case 的意思是「一律實色」，而透鏡是一片會飛過去的玻璃：
    /// 少了這道閘，選了 `.solid` 的 consumer 靜止時拿到實色、移動中仍然看到玻璃，
    /// 而 `.solid` 是唯一能表達「我不要玻璃」的方式，沒有別的出口。
    private var usesSelectionLens: Bool {
        guard itemAppearance.selectionIndicatorMaterial != .solid else { return false }
        guard style == .floatingGlass, !reducesTransparency else { return false }
        guard !TeroAccessibility.isReduceMotionEnabled() else { return false }
        guard #available(iOS 26, *) else { return false }
        return true
    }

    /// 每一幀跟著靜止膠囊的 presentation 值走。
    ///
    /// 讀 presentation layer 而不是讓透鏡自己再跑一次動畫：兩條時間軸遲早會漂開，
    /// 而透鏡必須**剛好**蓋在膠囊上。
    private func updateSelectionLens(transition: CGFloat) {
        guard usesSelectionLens,
              selectionCoordinator.isRunning,
              showsSelectionIndicator,
              !selectionIndicator.isHidden else {
            hideSelectionLens()
            return
        }

        let presented = selectionIndicator.frame
        let alpha = lensAlpha(at: transition)
        guard presented.width > 0, presented.height > 0, alpha > 0 else {
            hideSelectionLens()
            return
        }

        let origin = tabsCapsule.frame.origin
        selectionLens.apply(material: .lens)
        selectionLens.transform = .identity
        selectionLens.bounds = CGRect(origin: .zero, size: presented.size)
        selectionLens.center = CGPoint(x: presented.midX + origin.x, y: presented.midY + origin.y)
        selectionLens.layer.cornerRadius = selectionIndicator.layer.cornerRadius
        selectionLens.transform = CGAffineTransform(scaleX: lensStretch(at: transition), y: 1)
        selectionLens.alpha = alpha
        selectionLens.isHidden = false
        // 兩層疊在同一個位置會亮成一塊，交棒給透鏡的時候實色要退場。
        selectionIndicator.alpha = 1 - alpha
    }

    private func hideSelectionLens() {
        guard !selectionLens.isHidden else { return }
        selectionLens.isHidden = true
        selectionLens.alpha = 0
        selectionLens.transform = .identity
        if !selectionIndicator.isHidden { selectionIndicator.alpha = 1 }
    }

    /// 移動中把透鏡橫向拉長，接近終點再收回。起點與終點都是 1。
    private func lensStretch(at transition: CGFloat) -> CGFloat {
        let travel = abs(selectionCoordinator.segmentTravel)
        let width = selectionIndicator.bounds.width
        guard motion.selectionStretch > 0, travel > 1, width > 1 else { return 1 }
        let extra = min(travel * motion.selectionStretch, width * 1.2)
        let peak = (width + extra) / width
        return 1 + (peak - 1) * sin(.pi * min(max(transition, 0), 1))
    }

    /// 起步快速淡入，並在彈簧的尾巴**之前**就交還給實色膠囊——
    /// 否則膠囊看起來已經到了，Icon 卻還被折射著。
    private func lensAlpha(at transition: CGFloat) -> CGFloat {
        let t = min(max(transition, 0), 1)
        if t < 0.06 { return t / 0.06 }
        if t > 0.82 { return max(0, (1 - t) / 0.18) }
        return 1
    }

    /// 減少動態效果開啟、且設定為交叉淡入。
    private var usesReducedMotionCrossFade: Bool {
        TeroAccessibility.isReduceMotionEnabled() && motion.reduceMotionBehavior == .crossFade
    }

    /// 目前這一格的選取外框。
    ///
    /// 版面跑過之後由 layout engine 提供；在那之前（例如 model 剛換過、
    /// 這一輪 layout 還沒到）以同一組幾何規則從現有的格位推導，
    /// 兩條路徑共用 `TeroTabSelectionGeometry`，不會各算各的。
    private func selectionFrame(forSlot slot: Int, in views: [TeroTabItemView]) -> CGRect? {
        if slotSelectionFrames.count == views.count, slotSelectionFrames.indices.contains(slot) {
            return slotSelectionFrames[slot]
        }
        guard views.indices.contains(slot) else { return nil }
        let sizes = requestedSelectionSizes
        return TeroTabSelectionGeometry.frame(
            inSlot: views[slot].frame,
            requestedSize: sizes.indices.contains(slot) ? sizes[slot] : nil,
            insets: itemAppearance.selectionIndicatorInsets
        )
    }

    /// 各格要求的選取尺寸，順序與 `slotViews` 一致。
    private var requestedSelectionSizes: [CGSize?] {
        var sizes: [CGSize?] = model.items.map(\.selectionSize)
        if model.more != nil { sizes.append(nil) }
        return sizes
    }

    /// 解析後的材質。玻璃只在 iOS 26 且未降低透明度時成立。
    private var resolvedIndicatorMaterial: TeroTabSelectionIndicatorView.Material {
        let solid = TeroTabSelectionIndicatorView.Material.solid(itemAppearance.selectionIndicatorColor)
        guard !reducesTransparency else { return solid }
        guard #available(iOS 26, *) else { return solid }
        let glass = TeroTabSelectionIndicatorView.Material.glass(itemAppearance.selectionIndicatorGlassTint)
        switch itemAppearance.selectionIndicatorMaterial {
        case .solid: return solid
        case .glass: return glass
        // 靜止的選取不顯示 liquid glass：玻璃材質會在邊界外暈開一圈柔邊，
        // 既把內縮的 gap 填掉、也讓膠囊看起來是糊的。移動中的玻璃由透鏡負責。
        case .automatic: return solid
        }
    }

    /// 重複點擊選取中的 Tab 的回饋（補充規格 §12）。
    ///
    /// 選取本身不變，因此不開新的轉場段落——只播回饋。
    internal func playReselectFeedback() {
        guard let slot = selectedSlotIndex, slotViews.indices.contains(slot) else { return }
        selectionCoordinator.pulse(on: selectionIndicator)
        slotViews[slot].playReselectFeedback(duration: motion.reselectDuration)
        replayContent(atSlot: slot)
    }

    /// 讓自訂內容有機會重播（例如 Lottie）。狀態沒變，所以照原狀態再通知一次。
    private func replayContent(atSlot slot: Int) {
        guard let key = contentKey(forSlot: slot), let cached = contentViews[key] else { return }
        cached.provider.updateContentView?(
            cached.view,
            selected: true,
            presentationState: presentationState,
            animated: TeroAccessibility.resolvedAnimated(true)
        )
    }

    private func clearSelection() {
        selectionCoordinator.reset()
        hideSelectionLens()
        selectionIndicator.isHidden = true
        beginSelectionSegment(to: nil)
        applySelectionProgress(1)
    }

    private func beginSelectionSegment(to slot: Int?, animated: Bool = false) {
        segmentStartProgress = slotProgress
        segmentTargetSlot = slot
        segmentAnimated = animated
    }

    /// 把整段轉場的進度攤到每一格上。
    ///
    /// 目標格朝 1 走、其餘朝 0 走，起點一律是這一段開跑時的值——
    /// 中斷之後接手的那一段因此從畫面上看到的狀態繼續，不會跳值。
    private func applySelectionProgress(_ transition: CGFloat) {
        selectionTransitionProgress = transition
        let revision = modelRevision
        let views = slotViews
        for (index, view) in views.enumerated() {
            let start = index < segmentStartProgress.count ? segmentStartProgress[index] : 0
            let end: CGFloat = (index == segmentTargetSlot) ? 1 : 0
            let value = start + (end - start) * transition
            if index < slotProgress.count { slotProgress[index] = value }

            let phase: TeroTabItemView.SelectionPhase
            if index == segmentTargetSlot {
                phase = start < 1 ? .incoming : .idle
            } else {
                phase = start > 0 ? .outgoing : .idle
            }
            view.applySelection(progress: value, transition: transition, phase: phase)
            notifyInteractiveProvider(atSlot: index, progress: value)
            guard revision == modelRevision else { return }
        }
        renderSelectionGeometry()
    }

    private func renderSelectionGeometry() {
        guard !isDraggingIndicator, !slotSelectionFrames.isEmpty else { return }
        var frame = CGRect.zero
        var weight: CGFloat = 0
        for (index, value) in slotProgress.enumerated() where slotSelectionFrames.indices.contains(index) {
            let target = slotSelectionFrames[index]
            frame.origin.x += target.minX * value
            frame.origin.y += target.minY * value
            frame.size.width += target.width * value
            frame.size.height += target.height * value
            weight += value
        }
        if weight <= 0, let index = selectedSlotIndex, slotSelectionFrames.indices.contains(index) {
            frame = slotSelectionFrames[index]
        } else if weight > 0 {
            frame = CGRect(x: frame.minX / weight, y: frame.minY / weight,
                           width: frame.width / weight, height: frame.height / weight)
        }
        selectionIndicator.bounds = CGRect(origin: .zero, size: frame.size)
        selectionIndicator.center = CGPoint(x: frame.midX, y: frame.midY)
        selectionIndicator.layer.cornerRadius = itemAppearance.selectionIndicatorCornerRadius ?? frame.height / 2
        updateSelectionLens(transition: selectionTransitionProgress)
    }

    /// 把連續進度轉給採用進階協定的自訂內容（補充規格 §8）。
    ///
    /// Action 不在 `slotViews` 裡，因此永遠收不到——它是指令，不參與選取（ADR-0003）。
    private func notifyInteractiveProvider(atSlot index: Int, progress: CGFloat) {
        // 拖曳中每一次回呼都是手指的當下位置，不是一段動畫——而 `segmentAnimated` 只在
        // `beginSelectionSegment` 設定，拖曳從不走那裡，所以它會是**上一次轉場**留下的值。
        let animated = isDraggingIndicator
            ? false
            : (segmentAnimated && !TeroAccessibility.isReduceMotionEnabled())
        guard let key = contentKey(forSlot: index),
              let cached = contentViews[key],
              let interactive = cached.provider as? TeroTabInteractiveContentProvider else {
            return
        }
        interactive.updateContentView?(
            cached.view,
            selectionProgress: progress,
            animated: animated
        )
    }

    private func contentKey(forSlot index: Int) -> String? {
        if model.items.indices.contains(index) { return model.items[index].key }
        if model.more != nil, index == model.items.count { return TeroTabItemPresentation.moreKey }
        return nil
    }

    // MARK: - Swipe selection

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard swipeSelectionMode == .swipe else { return }
        handleSwipe(recognizer)
    }

    @objc private func handleDragGesture(_ recognizer: UILongPressGestureRecognizer) {
        guard swipeSelectionMode == .drag else { return }
        handleDrag(recognizer)
    }

    @objc private func handleLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
        handleLongPress(recognizer)
    }

    /// 測試用的入口，與 `simulateDrag` 同一個理由：進入點是辨識器的 action，不是更下面那層。
    internal func simulateLongPress(_ recognizer: UILongPressGestureRecognizer) {
        handleLongPressGesture(recognizer)
    }

    /// 只在 `.began` 那一次發事件；落在哪一格看手指位置。
    ///
    /// `itemViews` 不含 More 與 Action，所以那兩個天然不會發——Action 是指令、More 不是 Tab。
    private func handleLongPress(_ recognizer: UIGestureRecognizer) {
        guard recognizer.state == .began, isLongPressEnabled, swipeSelectionMode != .drag else { return }
        let point = recognizer.location(in: itemsContainer)
        guard let index = itemViews.firstIndex(where: {
            $0.isEnabled && !$0.isHidden && $0.frame.contains(point)
        }) else { return }
        onLongPressItem?(index)
    }

    /// App 或視窗失去作用中狀態時放棄拖曳。
    ///
    /// 兩條獨立的卡死路徑：吸附動畫在背景被暫停、回到前景沒有東西讓它跑完；以及連
    /// `.cancelled` 都沒送到時 `isDraggingIndicator` 永遠是 true，而它守著
    /// `updateSelection` 與 `renderSelectionGeometry`——那道守門本身是對的（拖曳中的
    /// 位置由手指決定），但它同時讓外框永久鎖在手指離開的地方。
    ///
    /// 寫成狀態式而不是補某一條路徑：放棄之後無論哪一條沒送到都已經回到一致狀態。
    ///
    /// **不吸附到最近的格、也不改選取**：使用者是切走而不是完成操作，回來看到選取被
    /// 改掉會比停在中間更難理解。
    private func abandonDragIfNeeded() {
        guard isDraggingIndicator else { return }
        isDraggingIndicator = false
        hideSelectionLens()
        // 進度也要收回來。拖曳中 `slotProgress` 跟著手指走，所以只重算幾何會算回手指
        // 的位置——那正是測試抓到的。放棄的語意是「回到模型說的樣子」，兩者都得回。
        resetProgressToSelectedSlot()
        // 不走 `updateSelection`：它處理的是「選取**改變**」，選取沒變時會在抵達渲染
        // 之前就返回（實測 update 有跑、render 沒跑）。
        renderSelectionGeometry()
    }

    private func observeResignActive() {
        let center = NotificationCenter.default
        // 兩個都聽：單一 scene 的 App 兩者都會發，而多視窗只有 scene 那個分得出是誰。
        accessibilityObservers.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil, queue: .main
            ) { [weak self] _ in self?.abandonDragIfNeeded() }
        )
        accessibilityObservers.append(
            center.addObserver(
                forName: UIScene.willDeactivateNotification,
                object: nil, queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                // 只認自己那個視窗的 scene。iPad 上另一個視窗失焦不該中斷這裡的拖曳。
                guard let scene = notification.object as? UIScene,
                      scene === self.window?.windowScene else { return }
                self.abandonDragIfNeeded()
            }
        )
    }

    /// 把外框帶回目前選取那一格，用與選取轉場同一組彈簧參數。
    private func settleIndicatorOntoSelectedSlot() {
        let views = slotViews
        guard let slot = selectedSlotIndex, views.indices.contains(slot),
              let frame = selectionFrame(forSlot: slot, in: views),
              frame.width > 0, frame.height > 0,
              selectionIndicator.frame != frame else { return }

        animateIfMotionAllowed { [weak self] in
            self?.selectionIndicator.frame = frame
        }
    }

    /// 用選取轉場那組彈簧跑一段動畫；開啟「減少動態效果」時直接套上終值。
    ///
    /// ADR-0006 寫的是「本套件內部**所有**動畫一律視為關閉」。協調器那條路徑有守，
    /// 但拖曳這兩處是自己建動畫器的，原本各自繞過了它。
    private func animateIfMotionAllowed(_ changes: @escaping () -> Void) {
        guard !TeroAccessibility.isReduceMotionEnabled() else {
            changes()
            return
        }
        let animator = UIViewPropertyAnimator(
            duration: TeroTabSpring.nominalDuration(for: motion),
            timingParameters: TeroTabSpring.timingParameters(for: motion)
        )
        animator.addAnimations(changes)
        animator.startAnimation()
    }

    /// 拖曳中透鏡比 Bar 高出去多少（單邊，佔 Bar 高度的比例）。
    ///
    /// 系統原生的透鏡會溢出容器上下緣——那是它看起來像一塊獨立的玻璃、而不是 Bar 裡面
    /// 一個色塊的原因。
    private static let dragLensOvershoot: CGFloat = 0.22

    /// 透鏡最小的長寬比。
    ///
    /// 原生的透鏡是一顆**橫躺**的橢圓：比格子寬、左右壓在鄰格上，上下再溢出 Bar。
    /// 溢出原本只加在高度上，隱含「格比 Bar 高度寬」——原生 Tab Bar 通常 3–5 格，
    /// 那個前提成立；格數一多就反過來（6 格時格寬 50 < Bar 高 56），得到的是一顆
    /// **直立**的蛋，方向正好相反。換一個溢出值救不了，寬度必須跟著高度夾限。
    private static let dragLensMinimumAspect: CGFloat = 1.3

    /// 果凍的強度上限。
    ///
    /// 與轉場那條路徑的 `selectionStretch` 不是同一回事：轉場知道終點，所以依**距離**
    /// 拉長（跨得遠就拉得長）；拖曳沒有終點，只能依**速度**。兩者的數值不可互相比較。
    private static let dragLensJelly: CGFloat = 0.38

    /// 速度到達這個值時形變封頂（pt/s）。
    private static let dragLensReferenceSpeed: CGFloat = 1800

    /// 外框跟著手指的**位置**走，尺寸與 y 沿用手勢開始時的值。
    private func moveIndicatorFollowingFinger(_ recognizer: UIGestureRecognizer) {
        let fingerX = recognizer.location(in: itemsContainer).x
        selectionIndicator.frame = swipeResolver.indicatorFrame(
            followingCenterX: fingerX,
            startFrame: dragStartFrame,
            in: itemsContainer.bounds
        )
        applyDragProgress(fingerX: fingerX)
        updateSelectionLensForDrag(fingerX: fingerX)
    }

    /// 把每一格的進度收回到模型說的選取：選中的那格 1、其餘 0。
    private func resetProgressToSelectedSlot() {
        let views = slotViews
        if slotProgress.count != views.count {
            slotProgress = Array(repeating: 0, count: views.count)
        }
        let revision = modelRevision
        for (index, view) in views.enumerated() {
            let value: CGFloat = (index == selectedSlotIndex) ? 1 : 0
            slotProgress[index] = value
            view.applySelection(progress: value, transition: value,
                                phase: value > 0 ? .incoming : .idle)
            notifyInteractiveProvider(atSlot: index, progress: value)
            guard revision == modelRevision else { return }
        }
    }

    /// 拖曳中每一格的選取進度跟著手指走。
    ///
    /// 不做的話放開時協調器從陳舊的進度起跑，第一個 callback 先把外框拉回起點那一格
    /// ——使用者看到「閃回去再滑過來」。順帶讓圖示與自訂內容在拖曳中就開始漸變，
    /// 而不是等放手才動。
    private func applyDragProgress(fingerX: CGFloat) {
        let views = slotViews
        guard !views.isEmpty else { return }
        if slotProgress.count != views.count {
            slotProgress = Array(repeating: 0, count: views.count)
        }
        let weights = swipeResolver.slotWeights(
            fingerX: fingerX, slotCenters: views.map(\.frame.midX)
        )
        guard weights.count == views.count else { return }

        let revision = modelRevision
        for (index, view) in views.enumerated() {
            let value = weights[index]
            slotProgress[index] = value
            view.applySelection(progress: value, transition: value,
                                phase: value > 0 ? .incoming : .idle)
            notifyInteractiveProvider(atSlot: index, progress: value)
            guard revision == modelRevision else { return }
        }
    }

    /// 拖曳中的透鏡。
    ///
    /// 與轉場版差在**沒有進度可用**：終點由手指決定、隨時會變，所以不套 `lensStretch`
    /// 的 sin 曲線也不套 `lensAlpha` 的淡入淡出。透鏡直接貼著手指滿版顯示，形變改由
    /// 跟手速度驅動（`lensDeformation`，兩軸相乘守恆）。
    ///
    /// 高度取 Bar 的高度再溢出上下緣，而不是沿用外框的高度——原生的透鏡比容器高。
    private func updateSelectionLensForDrag(fingerX: CGFloat) {
        guard usesSelectionLens, showsSelectionIndicator, !selectionIndicator.isHidden else {
            hideSelectionLens()
            return
        }
        let presented = selectionIndicator.frame
        guard presented.width > 0, presented.height > 0 else {
            hideSelectionLens()
            return
        }

        let now = CACurrentMediaTime()
        let elapsed = now - lastDragSampleTime
        let speed: CGFloat = (elapsed > 0.001 && lastDragSampleTime > 0)
            ? (fingerX - lastDragFingerX) / CGFloat(elapsed)
            : 0
        lastDragFingerX = fingerX
        lastDragSampleTime = now

        let barHeight = tabsCapsule.bounds.height
        let overshoot = barHeight * Self.dragLensOvershoot
        let height = barHeight + overshoot * 2
        // 兩軸都溢出，再用長寬比保證它是橫躺的（見 `dragLensMinimumAspect`）。
        let width = max(presented.width + overshoot * 2, height * Self.dragLensMinimumAspect)
        let shape = TeroTabSelectionInterpolation.lensDeformation(
            speed: speed, reference: Self.dragLensReferenceSpeed, intensity: Self.dragLensJelly
        )

        let origin = tabsCapsule.frame.origin
        selectionLens.apply(material: .lens)
        selectionLens.transform = .identity
        selectionLens.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        selectionLens.center = CGPoint(x: presented.midX + origin.x,
                                       y: barHeight / 2 + origin.y)
        // 取短邊：長邊的一半會讓 CALayer 把矩形畫成橢圓。
        selectionLens.layer.cornerRadius = min(width, height) / 2
        selectionLens.transform = CGAffineTransform(scaleX: shape.horizontal, y: shape.vertical)
        selectionLens.alpha = 1
        selectionLens.isHidden = false
        // 兩層疊在同一個位置會亮成一塊：交棒給透鏡時實色退場。
        selectionIndicator.alpha = 0
    }

    /// 測試用的入口：手勢管線本身餵不進測試，但它的**內容**可以。
    ///
    /// 進入點刻意是 `handleDragGesture`（辨識器的 action），不是更下面的 `handleDrag`。
    /// 原本接在 `handleDrag` 上，於是把 `handleDragGesture` 整個掏空，19 個測試一條都
    /// 沒紅——測試從不經過派送點。往上挪一層之後，沒被覆蓋的就只剩辨識器建構時
    /// 那一行 `#selector`，由 `Scripts/check-drag-gesture-wiring.sh` 守住。
    internal func simulateDrag(_ recognizer: UILongPressGestureRecognizer) {
        handleDragGesture(recognizer)
    }


    /// 測試用：選取轉場還在跑嗎。
    internal var isSelectionTransitionRunningForTesting: Bool {
        selectionCoordinator.isRunning
    }

    private func handleDrag(_ recognizer: UIGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard showsSelectionIndicator, !selectionIndicator.isHidden else { return }
            // 只留選取格的最小化膠囊上只有一格，沒有東西可以拖到。
            guard !(presentationState == .minimized && minimizesToSelectedOnly) else { return }
            // 手指接手：先停住轉場，外框才不會一邊跟手一邊被彈簧拉走。
            selectionCoordinator.cancel()
            isDraggingIndicator = true
            dragStartFrame = selectionIndicator.frame
            lastDragFingerX = 0
            lastDragSampleTime = 0
            // 手指接手的第一件事就是把外框帶到手指底下，而這一次要有動畫。
            //
            // 不加動畫的理由本來是「pan 有 slop，`.began` 在手指移動十幾 pt 之後才觸發，
            // 讀起來是吸過去而不是閃一下」。驅動者換成零秒 long press 之後 `.began` 在
            // touch-down 當下就到、**完全沒有 slop**，理由跟著失效——選取在 A、手指按 D
            // 時外框是瞬移的。理由消失了，決定就得跟著改。
            //
            // 只有這一次要動畫：手指開始移動後 `.changed` 直接設 frame，UIKit 就地接手。
            animateIfMotionAllowed { [weak self] in
                self?.moveIndicatorFollowingFinger(recognizer)
            }

        case .changed:
            guard isDraggingIndicator else { return }
            moveIndicatorFollowingFinger(recognizer)

        case .ended, .cancelled, .failed:
            guard isDraggingIndicator else { return }
            isDraggingIndicator = false
            let centers = slotViews.map(\.frame.midX)
            let resolved = swipeResolver.nearestSlot(
                toCenterX: selectionIndicator.frame.midX,
                slotCenters: centers
            )
            // 吸附結果就是目前選取時，協調器認為「什麼都沒變」而不產生位移——
            // 但外框此刻在手指離開的地方，不在格子上。拖曳期間 frame 歸手指所有，
            // 所以拖曳結束就得由這裡交還。
            hideSelectionLens()
            let staysOnSameSlot = (resolved == selectedSlotIndex)
            if let resolved {
                commitSwipeSelection(atSlot: resolved)
            }
            // 無論成功或被拒絕，都以目前 model 的選取為準重新定位。
            updateSelection(animated: true)
            if staysOnSameSlot { settleIndicatorOntoSelectedSlot() }

        default:
            break
        }
    }

    private func handleSwipe(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }

        guard let current = selectedSlotIndex else { return }

        let target = swipeResolver.adjacentSlot(
            from: current,
            translation: recognizer.translation(in: itemsContainer).x,
            velocity: recognizer.velocity(in: itemsContainer).x,
            layoutDirection: effectiveUserInterfaceLayoutDirection,
            selectableSlotCount: itemViews.count
        )
        guard let target else { return }
        onSelectItem?(target)
        updateSelection(animated: true)
    }

    private func commitSwipeSelection(atSlot slot: Int) {
        // 吸附到 More 時什麼都不做：滑動的語意是選 Tab，不是開選單。
        guard itemViews.indices.contains(slot) else { return }
        onSelectItem?(slot)
    }

    // MARK: - Custom content

    private func configure(
        _ view: TeroTabItemView,
        with presentation: TeroTabItemPresentation,
        selected: Bool,
        animated: Bool
    ) {
        let contentView = contentView(for: presentation)
        view.configure(
            with: presentation,
            appearance: itemAppearance,
            badgeAppearance: badgeAppearance,
            contentView: contentView
        )
        view.isSelected = selected

        if let contentView, let provider = presentation.contentProvider {
            // Provider 收到的一律是解析後的值：`false` 代表「停止播放」。
            provider.updateContentView?(
                contentView,
                selected: selected,
                presentationState: presentationState,
                animated: TeroAccessibility.resolvedAnimated(animated)
            )
            (provider as? TeroTabInteractiveContentProvider)?.updateContentView?(
                contentView, presentationProgress: minimizationProgress,
                animated: TeroAccessibility.resolvedAnimated(animated)
            )
        }
    }

    /// 每個 Item 各自呼叫一次 `makeContentView()`；只有 provider 參考本身變更才重建。
    private func contentView(for presentation: TeroTabItemPresentation) -> UIView? {
        guard let provider = presentation.contentProvider else {
            contentViews[presentation.key]?.view.removeFromSuperview()
            contentViews[presentation.key] = nil
            return nil
        }
        if let cached = contentViews[presentation.key], cached.provider === provider {
            return cached.view
        }
        contentViews[presentation.key]?.view.removeFromSuperview()
        let view = provider.makeContentView()
        contentViews[presentation.key] = (provider, view)
        return view
    }

    /// Item 從 Tab 列表消失時銷毀它的自訂內容；
    /// 只是進 Overflow 的則保留（鍵仍在 model 之外，但由 controller 傳入的鍵集合決定）。
    private func pruneContentViews() {
        var liveKeys = Set(model.items.map(\.key))
        if model.more != nil { liveKeys.insert(TeroTabItemPresentation.moreKey) }
        if model.action != nil { liveKeys.insert(TeroTabItemPresentation.actionKey) }
        liveKeys.formUnion(retainedContentKeys)

        for key in contentViews.keys where !liveKeys.contains(key) {
            contentViews[key]?.view.removeFromSuperview()
            contentViews[key] = nil
        }
    }

    /// 目前不可見但仍屬於 Tab 列表的鍵（Overflow）。由 controller 提供。
    internal var retainedContentKeys: Set<String> = []

    // MARK: - Views

    private func rebuildViews() {
        defer {
            itemsContainer.sendSubviewToBack(selectionIndicator)
            bringSubviewToFront(selectionLens)
        }
        // 格位換了一批，舊的 frame 與進度都不再對應得上。
        selectionCoordinator.reset()
        slotSelectionFrames = []
        slotProgress = []
        segmentStartProgress = []
        segmentTargetSlot = nil
        itemViews.forEach { $0.removeFromSuperview() }
        moreView?.removeFromSuperview()
        actionView?.removeFromSuperview()

        itemViews = model.items.map { _ in
            let view = TeroTabItemView(frame: .zero)
            view.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            itemsContainer.addSubview(view)
            return view
        }

        if model.more != nil {
            let view = TeroTabItemView(frame: .zero)
            view.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
            itemsContainer.addSubview(view)
            moreView = view
        } else {
            moreView = nil
        }

        if model.action != nil {
            let view = TeroTabItemView(frame: .zero)
            view.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
            itemsContainer.addSubview(view)
            actionView = view
        } else {
            actionView = nil
        }
    }

    private func applyMoreMenu() {
        guard let moreView else { return }
        moreView.menu = moreMenu
        moreView.showsMenuAsPrimaryAction = (moreMenu != nil)
    }

    private var storedScrollEdgeInteraction: AnyObject?

    @available(iOS 26, *)
    private var scrollEdgeInteraction: UIScrollEdgeElementContainerInteraction? {
        get { storedScrollEdgeInteraction as? UIScrollEdgeElementContainerInteraction }
        set { storedScrollEdgeInteraction = newValue }
    }

    /// 由捲動切片呼叫：把追蹤中的捲動視圖交給系統的邊緣效果。
    ///
    /// 互動**只在真的有追蹤對象時才裝**（issue #102）。沒有 scroll view 就沒有邊緣可處理；
    /// 而一顆裝著沒事做的互動會讓 iOS 26 的 observation tracking 把這個 view 的
    /// `updateProperties` 判成回饋迴圈——測試日誌裡上千則
    /// 「Observation tracking feedback loop detected」全部指向它，拆掉就歸零。
    /// 對象沒換就不重寫，重設同一個對象也會讓互動的模型失效一次。
    internal func updateScrollEdgeSource(_ scrollView: UIScrollView?) {
        guard #available(iOS 26, *) else { return }
        if let scrollView {
            if scrollEdgeInteraction == nil {
                let interaction = UIScrollEdgeElementContainerInteraction()
                interaction.edge = .bottom
                addInteraction(interaction)
                scrollEdgeInteraction = interaction
            }
            if scrollEdgeInteraction?.scrollView !== scrollView {
                scrollEdgeInteraction?.scrollView = scrollView
            }
        } else if let interaction = scrollEdgeInteraction {
            removeInteraction(interaction)
            scrollEdgeInteraction = nil
        }
    }

    /// 測試用：邊緣效果現在有沒有裝在 Bar 上。
    internal var hasScrollEdgeInteraction: Bool {
        if #available(iOS 26, *) { return scrollEdgeInteraction != nil }
        return false
    }

    private func observeAccessibilitySettings() {
        let center = NotificationCenter.default
        for name in [
            UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification
        ] {
            let token = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.applyBackground()
                // 剛打開「減少動態效果」時，已經在飛的轉場要立刻落定，
                // 而不是等下一次切換才生效。
                if TeroAccessibility.isReduceMotionEnabled() {
                    self.selectionCoordinator.settleImmediately()
                    self.visibilityCoordinator.settle()
                }
                self.setNeedsLayout()
            }
            accessibilityObservers.append(token)
        }
    }

    /// 降低透明度時，玻璃與模糊都退化為不透明實色。
    /// 顏色自動衍生，不新增設定旋鈕（ADR-0006）。
    private var reducesTransparency: Bool {
        TeroAccessibility.isReduceTransparencyEnabled()
    }

    private func applyBackground() {
        backgroundColor = .clear
        switch style {
        case .classic:
            if reducesTransparency {
                tabsCapsule.effect = nil
                tabsCapsule.contentView.backgroundColor =
                    classicAppearance.backgroundColor.withAlphaComponent(1)
            } else if classicAppearance.usesBlurEffect {
                tabsCapsule.effect = UIBlurEffect(style: classicAppearance.blurEffectStyle)
                tabsCapsule.contentView.backgroundColor = .clear
            } else {
                tabsCapsule.effect = nil
                tabsCapsule.contentView.backgroundColor = classicAppearance.backgroundColor
            }
            separator.backgroundColor = classicAppearance.separatorColor
            separator.isHidden = (classicAppearance.separatorColor == nil)
            actionCapsule.isHidden = true
            hideSelectionLens()

        case .floatingGlass:
            // FloatingGlass 只在 iOS 26 以上可達（ADR-0002），因此這裡一律用系統玻璃，
            // 不存在以模糊效果仿製 Liquid Glass 的路徑。
            if reducesTransparency {
                applyOpaqueFallback()
            } else {
                applyGlass()
            }
            separator.isHidden = true
            actionCapsule.isHidden = (model.action == nil)
        }
        updateActionHost()
    }

    private func applyOpaqueFallback() {
        glassContainer.effect = nil
        glassContainer.contentView.backgroundColor = .clear
        let opaque: UIColor = floatingAppearance.glassTintMode == .tinted
            ? (floatingAppearance.glassTintColor ?? .systemBackground).withAlphaComponent(1)
            : .systemBackground
        for capsule in [tabsCapsule, actionCapsule] {
            capsule.effect = nil
            capsule.contentView.backgroundColor = opaque
        }
    }

    private func applyGlass() {
        guard #available(iOS 26, *) else {
            // 理論上不可達：iOS 26 以下生效樣式一律為 classic。
            TeroDiagnostics.report("FloatingGlass 不應在 iOS 26 以下生效")
            return
        }

        let container = UIGlassContainerEffect()
        container.spacing = floatingAppearance.glassContainerSpacing
        glassContainer.effect = container
        glassContainer.contentView.backgroundColor = .clear

        let tint: UIColor? = floatingAppearance.glassTintMode == .tinted
            ? floatingAppearance.glassTintColor
            : nil

        for capsule in [tabsCapsule, actionCapsule] {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = true
            glass.tintColor = tint
            capsule.effect = glass
            capsule.contentView.backgroundColor = .clear
        }
    }

    /// Classic 的 Action 在 Tabs 列的中央，FloatingGlass 的在自己的膠囊裡。
    private func updateActionHost() {
        guard let actionView else { return }
        let host = (style == .classic) ? itemsContainer : actionCapsule.contentView
        if actionView.superview !== host {
            actionView.removeFromSuperview()
            host.addSubview(actionView)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        switch style {
        case .classic:
            layoutClassic()
        case .floatingGlass:
            layoutFloatingGlass()
        }
    }

    private func propagateLayoutDirection() {
        let direction = effectiveUserInterfaceLayoutDirection
        for view in itemViews { view.layoutDirection = direction }
        moreView?.layoutDirection = direction
        actionView?.layoutDirection = direction
    }

    private func layoutClassic() {
        propagateLayoutDirection()
        glassContainer.frame = bounds
        tabsCapsule.frame = glassContainer.contentView.bounds
        tabsCapsule.layer.cornerRadius = 0
        tabsCapsule.clipsToBounds = false
        actionCapsule.isHidden = true

        let hairline = 1 / (window?.screen.scale ?? UIScreen.main.scale)
        separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: hairline)

        itemsContainer.frame = CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: min(classicAppearance.barHeight, bounds.height)
        )

        var slotViews: [TeroTabItemView] = itemViews
        if let moreView { slotViews.append(moreView) }

        let layout = classicLayoutEngine.layout(
            itemCount: slotViews.count,
            hasCenterAction: actionView != nil,
            in: itemsContainer.bounds,
            contentInsets: classicAppearance.contentInsets,
            selectionInsets: itemAppearance.selectionIndicatorInsets,
            selectionSizes: requestedSelectionSizes,
            layoutDirection: effectiveUserInterfaceLayoutDirection
        )
        for (view, frame) in zip(slotViews, layout.itemFrames) {
            view.frame = frame
        }
        slotSelectionFrames = layout.selectionFrames
        if let actionView, let actionFrame = layout.actionFrame {
            actionView.frame = actionFrame
        }
        updateSelection(animated: false)
    }

    private func layoutFloatingGlass() {
        propagateLayoutDirection()
        glassContainer.frame = bounds
        var slotViews: [TeroTabItemView] = itemViews
        if let moreView { slotViews.append(moreView) }

        let direction = effectiveUserInterfaceLayoutDirection
        if layoutSnapshots == nil || snapshotWidth != bounds.width || snapshotDirection != direction {
            func snapshot(_ state: TeroTabBarPresentationState) -> TeroFloatingGlassLayoutEngine.Layout {
                floatingLayoutEngine.layout(
                    itemCount: slotViews.count, hasAction: actionView != nil, state: state,
                    in: CGRect(x: 0, y: 0, width: bounds.width, height: contentHeight(for: state)),
                    appearance: floatingAppearance, selectionInsets: itemAppearance.selectionIndicatorInsets,
                    selectionSizes: requestedSelectionSizes, layoutDirection: direction,
                    selectedIndex: selectedSlotIndex
                )
            }
            layoutSnapshots = (snapshot(.expanded), snapshot(.minimized))
            snapshotWidth = bounds.width
            snapshotDirection = direction
        }
        guard let snapshots = layoutSnapshots else { return }
        let layout = TeroFloatingGlassLayoutEngine.interpolate(
            snapshots.expanded, snapshots.minimized, progress: minimizationProgress
        )

        tabsCapsule.frame = layout.tabsCapsule
        tabsCapsule.layer.cornerRadius = layout.cornerRadius
        tabsCapsule.clipsToBounds = true
        separator.isHidden = true

        itemsContainer.frame = tabsCapsule.bounds
        for (index, (view, frame)) in zip(slotViews, layout.itemFrames).enumerated() {
            view.frame = frame
            view.applyPresentation(progress: minimizationProgress,
                iconSide: max(12, floatingAppearance.minimizedHeight - 12),
                hidesTitle: floatingAppearance.hidesTitlesWhenMinimized)
            // 只留選取格：其餘隨進度淡出到摸不到。uniform 一律完全可見。
            let visible: CGFloat = (minimizesToSelectedOnly && index != selectedSlotIndex)
                ? 1 - minimizationProgress : 1
            view.applyMinimizedVisibility(visible)
        }
        slotSelectionFrames = layout.selectionFrames
        updateSelection(animated: false)
        renderSelectionGeometry()

        if let actionView, let actionFrame = layout.actionCapsule {
            actionCapsule.isHidden = false
            actionCapsule.frame = actionFrame
            actionCapsule.layer.cornerRadius = min(actionFrame.width, actionFrame.height) / 2
            actionCapsule.clipsToBounds = true
            actionView.frame = actionCapsule.bounds
            actionView.applyPresentation(progress: minimizationProgress,
                iconSide: max(12, floatingAppearance.minimizedHeight - 12), hidesTitle: true)
        } else {
            actionCapsule.isHidden = true
        }
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard presentationState != .hidden else { return false }
        return bounds.insetBy(dx: 0, dy: -max(0, (44 - bounds.height) / 2)).contains(point)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled,
              self.point(inside: point, with: event) else { return nil }
        if style == .floatingGlass {
            let controls = slotViews + (actionView.map { [$0] } ?? [])
            for control in controls where control.isEnabled && !control.isHidden {
                let frame = control.convert(control.bounds, to: self)
                // Horizontal slots remain disjoint; vertical padding provides the 44pt hit height.
                let hit = frame.insetBy(dx: control === actionView ? -max(0, (44 - frame.width) / 2) : 0,
                    dy: -max(0, (44 - frame.height) / 2))
                if hit.contains(point) { return control }
            }
            return nil
        }
        return super.hitTest(point, with: event)
    }

    @objc private func itemTapped(_ sender: TeroTabItemView) {
        guard let index = itemViews.firstIndex(of: sender) else { return }
        onSelectItem?(index)
    }

    @objc private func moreTapped() {
        onSelectMore?()
    }

    @objc private func actionTapped() {
        onTriggerAction?()
    }
}
