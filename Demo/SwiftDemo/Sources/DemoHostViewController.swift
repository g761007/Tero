import UIKit
import Tero

/// Tab Bar UI 屬於下一個切片，因此這個 Demo 用普通按鈕驅動選取，
/// 用來驗證容器核心：選取規則、生命週期序列、navigation stack 保留、設定所有權。
final class DemoHostViewController: UIViewController {

    private let journal = DemoJournal()
    private let tabController: TeroTabBarController
    private let journalView = UITextView()
    private let stateLabel = UILabel()
    private var buttons: [UIButton] = []
    private var referenceCaseButtons: [UIButton] = []

    typealias Spec = (identifier: String, title: String, symbol: String, tint: UIColor, wrapped: Bool)

    // 圖示一律用 SF Symbols 或程式繪製：套件與 Demo 都不得依賴打包資源（ADR-0007）。
    private let specs: [Spec] = {
        var specs: [Spec] = [
            ("home", "Home", "house", .systemBlue, true),
            ("search", "Search", "magnifyingglass", .systemGreen, false),
            ("profile", "Profile", "person.crop.circle", .systemPurple, true)
        ]
        if DemoLaunchOptions.manyTabs {
            specs += [
                ("library", "Library", "books.vertical", .systemOrange, true),
                ("inbox", "Inbox", "tray", .systemTeal, false),
                ("settings", "Settings", "gearshape", .systemBrown, true),
                ("about", "About", "info.circle", .systemPink, false)
            ]
        }
        return specs
    }()

    /// 已存的設定。啟動參數優先於它——自動化截圖必須是確定的。
    private var settings = DemoSettingsStore.load()

    init() {
        let settings = DemoSettingsStore.load()
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        // Style 不支援 runtime 切換（ADR-0003），所以它只能在啟動時決定：
        // 啟動參數沒指定時，沿用上一次存下來的選擇。
        let usesFloatingGlass = DemoLaunchOptions.requestedStyleName.map { $0 == "floatingGlass" }
            ?? settings.styleIsFloatingGlass
        configuration.style = usesFloatingGlass ? .floatingGlass : .classic
        configuration.compact.maximumVisibleItems = 5
        configuration.regular.maximumVisibleItems = 6
        self.tabController = TeroTabBarController(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tabController.delegate = self
        addChild(tabController)
        tabController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabController.view)
        tabController.didMove(toParent: self)

        let controls = makeControlPanel()
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)

        NSLayoutConstraint.activate([
            tabController.view.topAnchor.constraint(equalTo: view.topAnchor),
            tabController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabController.view.bottomAnchor.constraint(equalTo: controls.topAnchor),

            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controls.heightAnchor.constraint(equalToConstant: 300)
        ])

        journal.onChange = { [weak self] in self?.refresh() }
        installTabs()
        if DemoLaunchOptions.showsBadgesOnLaunch { setBadges(shown: true, animated: false) }
        journal.record(lottieProvider.loadFailed ? "Lottie 動畫載入失敗" : "Lottie 動畫已載入")

        if let offset = DemoLaunchOptions.scrolledOffset {
            feed.scrollProgrammatically(to: offset)
        }

        // 啟動參數優先；沒有指定時沿用存下來的模式。
        let launchedSwipeMode: TeroTabSwipeSelectionMode? = DemoLaunchOptions.swipeModeName.map { name in
            switch name {
            case "drag": return .drag
            case "swipe": return .swipe
            default: return .disabled
            }
        }
        let restoredSwipeMode = TeroTabSwipeSelectionMode(rawValue: settings.swipeMode) ?? .disabled
        applySwipeMode(launchedSwipeMode ?? restoredSwipeMode, persists: launchedSwipeMode == nil)

        switch DemoLaunchOptions.presentationStateName {
        case "minimized": tabController.setTabBarPresentationState(.minimized, animated: false)
        case "hidden": tabController.setTabBarPresentationState(.hidden, animated: false)
        default: break
        }
    }

    private func makeControlPanel() -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemBackground

        buttons = specs.map { spec in
            let button = UIButton(type: .system)
            button.setTitle(spec.title, for: .normal)
            button.addTarget(self, action: #selector(selectTapped(_:)), for: .touchUpInside)
            return button
        }
        let selectRow = UIStackView(arrangedSubviews: buttons)
        selectRow.distribution = .fillEqually

        let reloadButton = UIButton(type: .system)
        reloadButton.setTitle("重設 Tab（保留選取）", for: .normal)
        reloadButton.addTarget(self, action: #selector(resetTabsPreservingSelection), for: .touchUpInside)

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("清空 Tab", for: .normal)
        clearButton.addTarget(self, action: #selector(clearTabs), for: .touchUpInside)

        let snapshotButton = UIButton(type: .system)
        snapshotButton.setTitle("驗證設定快照", for: .normal)
        snapshotButton.addTarget(self, action: #selector(mutateSnapshot), for: .touchUpInside)

        let badgeButton = UIButton(type: .system)
        badgeButton.setTitle("切換 Badge", for: .normal)
        badgeButton.addTarget(self, action: #selector(toggleBadges), for: .touchUpInside)

        let actionRow = UIStackView(arrangedSubviews: [reloadButton, clearButton, snapshotButton])
        actionRow.distribution = .fillEqually

        let expandButton = UIButton(type: .system)
        expandButton.setTitle("展開", for: .normal)
        expandButton.addTarget(self, action: #selector(expand), for: .touchUpInside)

        let minimizeButton = UIButton(type: .system)
        minimizeButton.setTitle("最小化", for: .normal)
        minimizeButton.addTarget(self, action: #selector(minimize), for: .touchUpInside)

        let hideButton = UIButton(type: .system)
        hideButton.setTitle("隱藏", for: .normal)
        hideButton.addTarget(self, action: #selector(hide), for: .touchUpInside)

        let swipeButton = UIButton(type: .system)
        swipeButton.setTitle("滑動模式", for: .normal)
        swipeButton.addTarget(self, action: #selector(cycleSwipeMode), for: .touchUpInside)

        let applyButton = UIButton(type: .system)
        applyButton.setTitle("套用新設定", for: .normal)
        applyButton.addTarget(self, action: #selector(applyNewConfiguration), for: .touchUpInside)

        let badgeRow = UIStackView(arrangedSubviews: [badgeButton, applyButton, swipeButton, expandButton, minimizeButton, hideButton])
        badgeRow.distribution = .fillEqually

        stateLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        stateLabel.numberOfLines = 2

        journalView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        journalView.isEditable = false
        journalView.backgroundColor = .clear

        let labButton = UIButton(type: .system)
        labButton.setTitle("Lab", for: .normal)
        labButton.addTarget(self, action: #selector(openInteractionLab), for: .touchUpInside)

        let navigationLabButton = UIButton(type: .system)
        navigationLabButton.setTitle("Nav", for: .normal)
        navigationLabButton.accessibilityIdentifier = "open.navigationLab"
        navigationLabButton.addTarget(self, action: #selector(openNavigationLab), for: .touchUpInside)

        let styleButton = UIButton(type: .system)
        styleButton.setTitle("Style↻", for: .normal)
        styleButton.addTarget(self, action: #selector(toggleStoredStyle), for: .touchUpInside)

        let clearSettingsButton = UIButton(type: .system)
        clearSettingsButton.setTitle("清除設定", for: .normal)
        clearSettingsButton.addTarget(self, action: #selector(clearStoredSettings), for: .touchUpInside)

        let caseButtons = DemoReferenceCase.allCases.map { referenceCase -> UIButton in
            let button = UIButton(type: .system)
            button.setTitle(referenceCase.rawValue.uppercased(), for: .normal)
            button.addTarget(self, action: #selector(openReferenceCase(_:)), for: .touchUpInside)
            return button
        }
        referenceCaseButtons = caseButtons
        let labRow = UIStackView(
            arrangedSubviews: [labButton, navigationLabButton, styleButton, clearSettingsButton] + caseButtons
        )
        labRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [selectRow, actionRow, badgeRow, labRow, stateLabel, journalView])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        ])
        return container
    }

    private func installTabs() {
        let tabs = specs.map { spec -> TeroTab in
            let content: UIViewController = (spec.identifier == "home")
                ? feed
                : DemoContentViewController(name: spec.title, tint: spec.tint, journal: journal)
            let item = TeroTabItem(
                title: spec.title,
                image: UIImage(systemName: spec.symbol),
                selectedImage: UIImage(systemName: "\(spec.symbol).fill") ?? UIImage(systemName: spec.symbol)
            )
            item.accessibilityIdentifier = "tab.\(spec.identifier)"
            if spec.identifier == "search" {
                item.contentProvider = lottieProvider
            }
            return TeroTab(
                identifier: spec.identifier,
                viewController: spec.wrapped ? UINavigationController(rootViewController: content) : content,
                item: item
            )
        }
        tabController.setTabs(tabs, selectedIdentifier: "home", animated: false)

        // Action 是獨立指令：兩種 Style 都支援，Classic 置於 Bar 中央（ADR-0003）
        let action = TeroTabActionItem(identifier: "compose", image: UIImage(systemName: "plus"))
        action.accessibilityLabel = "撰寫"
        action.accessibilityIdentifier = "tab.compose"
        tabController.setActionItem(action, animated: false)

        refresh()
    }

    @objc private func openNavigationLab() {
        present(wrapped(NavigationLabViewController()), animated: true)
    }

    @objc private func openInteractionLab() {
        let lab = InteractionLabViewController()
        lab.modalPresentationStyle = .fullScreen
        present(wrapped(lab), animated: true)
    }

    @objc private func openReferenceCase(_ sender: UIButton) {
        guard let index = referenceCaseButtons.firstIndex(of: sender) else { return }
        let controller = DemoReferenceCaseViewController(referenceCase: DemoReferenceCase.allCases[index])
        present(wrapped(controller), animated: true)
    }

    /// 包一層 navigation controller，才有地方放「關閉」。
    private func wrapped(_ controller: UIViewController) -> UIViewController {
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        return navigation
    }

    @objc private func selectTapped(_ sender: UIButton) {
        guard let index = buttons.firstIndex(of: sender) else { return }
        let identifier = specs[index].identifier
        let accepted = tabController.selectTab(withIdentifier: identifier, animated: true)
        journal.record("selectTab(\(identifier)) → \(accepted)")
    }

    @objc private func resetTabsPreservingSelection() {
        journal.record("── setTabs(selectedIdentifier: nil)")
        installTabsPreservingSelection()
    }

    private func installTabsPreservingSelection() {
        let tabs = specs.map { spec -> TeroTab in
            let content = DemoContentViewController(name: spec.title, tint: spec.tint, journal: journal)
            let item = TeroTabItem(
                title: spec.title,
                image: UIImage(systemName: spec.symbol),
                selectedImage: UIImage(systemName: "\(spec.symbol).fill") ?? UIImage(systemName: spec.symbol)
            )
            return TeroTab(
                identifier: spec.identifier,
                viewController: spec.wrapped ? UINavigationController(rootViewController: content) : content,
                item: item
            )
        }
        tabController.setTabs(tabs, selectedIdentifier: nil, animated: false)
        refresh()
    }

    @objc private func clearTabs() {
        journal.record("── setTabs([])")
        tabController.setTabs([], selectedIdentifier: nil, animated: false)
        refresh()
    }

    private var badgesShown = false

    /// 由 Item 強持有，因此這裡不需要另外保留參考（ADR-0005）——
    /// 留一份只是為了在畫面上回報載入是否成功。
    private let lottieProvider = LottieTabProvider(animationName: "spinner")

    /// 長清單頁面，用來實測捲動驅動的收合。
    private lazy var feed = DemoFeedViewController(
        journal: journal,
        behavior: DemoLaunchOptions.requestedStyleName == "floatingGlass"
            ? .minimizeOnScrollDown
            : .hideOnScrollDown
    )

    @objc private func toggleBadges() {
        setBadges(shown: !badgesShown, animated: true)
    }

    private func setBadges(shown: Bool, animated: Bool) {
        badgesShown = shown
        if badgesShown {
            tabController.setBadge(.dot(), forTabWithIdentifier: "search", animated: animated)

            // 單一 Badge 已指定的屬性優先於預設外觀（計畫書 §24）
            let custom = TeroTabBadge.value("99+")
            custom.backgroundColor = .systemIndigo
            custom.textColor = .white
            tabController.setBadge(custom, forTabWithIdentifier: "profile", animated: animated)

            tabController.setBadge(.value("3"), forTabWithIdentifier: "home", animated: animated)
        } else {
            for spec in specs {
                tabController.setBadge(nil, forTabWithIdentifier: spec.identifier, animated: animated)
            }
        }
        journal.record("setBadge → \(badgesShown ? "顯示" : "清除")")
    }

    private var alternateConfigurationApplied = false

    /// 三態循環：關閉 → 拖曳跟手 → 輕掃切換。
    @objc private func cycleSwipeMode() {
        let next: TeroTabSwipeSelectionMode
        switch tabController.currentConfiguration().swipeSelectionMode {
        case .disabled: next = .drag
        case .drag: next = .swipe
        case .swipe: next = .disabled
        }
        applySwipeMode(next, persists: true)
        journal.record("swipeSelectionMode → \(Self.swipeModeNames[next.rawValue])")
    }

    private static let swipeModeNames = ["關閉", "拖曳跟手", "輕掃切換"]

    private func applySwipeMode(_ mode: TeroTabSwipeSelectionMode, persists: Bool) {
        let update = tabController.currentConfiguration()
        update.swipeSelectionMode = mode
        // `.drag` 拖的就是選取膠囊：Classic 預設不顯示它，不一併打開的話
        // 手勢會沒有東西可抓，按下去像壞掉一樣。
        if mode == .drag { update.itemAppearance.selectionIndicatorStyle = .always }
        tabController.applyConfiguration(update, animated: false)
        if persists {
            settings.swipeMode = mode.rawValue
            DemoSettingsStore.save(settings)
        }
        refresh()
    }

    /// Style 只能在下一次啟動生效（ADR-0003），因此這裡只改存檔並說明。
    @objc private func toggleStoredStyle() {
        settings.styleIsFloatingGlass.toggle()
        DemoSettingsStore.save(settings)
        let name = settings.styleIsFloatingGlass ? "FloatingGlass" : "Classic"
        journal.record("下次啟動的 Style ← \(name)（Style 不支援 runtime 切換）")
    }

    @objc private func clearStoredSettings() {
        DemoSettingsStore.reset()
        settings = DemoSettings()
        applySwipeMode(.disabled, persists: false)
        journal.record("已清除存下來的設定（Style 於下次啟動回到 Classic）")
    }

    /// Runtime 套用設定：主色、可見數量上限與捲動行為都能即時改變（計畫書 §31）。
    @objc private func applyNewConfiguration() {
        alternateConfigurationApplied.toggle()
        let update = tabController.currentConfiguration()

        if alternateConfigurationApplied {
            update.selectedTintColor = .systemPink
            update.normalTintColor = .systemGray2
            update.compact.maximumVisibleItems = 3
            update.classicAppearance.barHeight = 64
            update.floatingGlassAppearance.glassTintMode = .tinted
            update.floatingGlassAppearance.glassTintColor = .systemPink
        } else {
            update.selectedTintColor = .tintColor
            update.normalTintColor = .secondaryLabel
            update.compact.maximumVisibleItems = 5
            update.classicAppearance.barHeight = 49
            update.floatingGlassAppearance.glassTintMode = .automatic
            update.floatingGlassAppearance.glassTintColor = nil
        }

        tabController.applyConfiguration(update, animated: true)
        journal.record("applyConfiguration → 上限 \(update.compact.maximumVisibleItems)、主色已換")
        refresh()
    }

    @objc private func expand() { applyState(.expanded) }
    @objc private func minimize() { applyState(.minimized) }
    @objc private func hide() { applyState(.hidden) }

    private func applyState(_ state: TeroTabBarPresentationState) {
        let accepted = tabController.setTabBarPresentationState(state, animated: true)
        journal.record("setPresentationState(\(state.rawValue)) → \(accepted)")
        refresh()
    }

    @objc private func mutateSnapshot() {
        let snapshot = tabController.currentConfiguration()
        let before = snapshot.compact.maximumVisibleItems
        snapshot.compact.maximumVisibleItems = 2
        let after = tabController.currentConfiguration().compact.maximumVisibleItems
        journal.record("改快照後 controller 仍為 \(after)（預期 \(before)）")
        refresh()
    }

    private func refresh() {
        let index = tabController.selectedTabIndex.map(String.init) ?? "nil"
        stateLabel.text = """
        selectedTab=\(tabController.selectedTab?.identifier ?? "nil")  index=\(index)  tabs=\(tabController.tabs.count)
        requested=\(tabController.requestedStyle.rawValue)  effective=\(tabController.tabBarStyle.rawValue)  state=\(tabController.tabBarPresentationState.rawValue)  swipe=\(tabController.currentConfiguration().swipeSelectionMode.rawValue)
        """
        journalView.text = journal.text
    }
}

extension DemoHostViewController: TeroTabBarControllerDelegate {

    func teroTabBarController(
        _ tabController: TeroTabBarController,
        didSelect tab: TeroTab,
        source: TeroTabSelectionSource
    ) {
        journal.record("didSelect(\(tab.identifier), source=\(source.rawValue))")
        refresh()
    }

    func teroTabBarController(_ tabController: TeroTabBarController, didReselect tab: TeroTab) {
        journal.record("didReselect(\(tab.identifier))")
    }

    /// 長按只發事件；實作了這個方法，Bar 才會裝辨識器。`.drag` 模式下不會收到。
    func teroTabBarController(_ tabController: TeroTabBarController, didLongPress tab: TeroTab) {
        journal.record("didLongPress(\(tab.identifier))")
    }

    func teroTabBarController(_ tabController: TeroTabBarController, didTrigger actionItem: TeroTabActionItem) {
        journal.record("didTrigger(\(actionItem.identifier)) — selectedTab 不變")
        refresh()
    }
}
