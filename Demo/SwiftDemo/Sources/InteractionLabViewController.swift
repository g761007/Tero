import UIKit
import Tero

/// 選取轉場的調參台。
///
/// 存在的理由很單純：這些效果**只能用眼睛驗**。單元測試驗得了「有沒有中斷」、
/// 「進度是不是單調」，驗不了「哪一組手感最像參考影片」。與其每改一個數值就重編，
/// 不如把旋鈕做出來，拿手機直接比。
final class InteractionLabViewController: UIViewController, UINavigationControllerDelegate {

    /// 四種預設手感。對應規格裡的 Static / Slide / Fluid / Spring。
    enum SelectionStyle: Int, CaseIterable {
        case `static`, slide, fluid, spring

        var title: String {
            switch self {
            case .static: return "Static"
            case .slide: return "Slide"
            case .fluid: return "Fluid"
            case .spring: return "Spring"
            }
        }

        /// 套到 `TeroTabMotionConfiguration` 上的起點。滑桿再從這裡微調。
        func apply(to motion: inout TeroTabMotionConfiguration) {
            switch self {
            case .static:
                motion.selectionResponse = nil
                motion.selectionDuration = 0.001
                motion.selectionDampingRatio = 1
            case .slide:
                motion.selectionResponse = nil
                motion.selectionDuration = 0.25
                motion.selectionDampingRatio = 1
            case .fluid:
                motion.selectionResponse = 0.45
                motion.selectionDampingRatio = 0.95
            case .spring:
                motion.selectionResponse = 0.35
                motion.selectionDampingRatio = 0.62
            }
        }
    }

    private struct Knob {
        let title: String
        let range: ClosedRange<Float>
        let initial: Float
        let apply: (InteractionLabViewController, CGFloat) -> Void
    }

    private var directionLock: CGFloat = 8
    private var scrollThreshold: CGFloat = 40
    private var minimizeDuration: CGFloat = 0.28
    private var restoreDuration: CGFloat = 0.22
    private var expandedHeight: CGFloat = 56
    private var minimizedHeight: CGFloat = 36
    private var showsAction = false
    private let tabController: TeroTabBarController
    private let backdropView = DemoBackdropView(backdrop: .night)
    private let readout = UILabel()

    /// 所有旋鈕的值都放在這裡，改一次就存一次；下次啟動直接接續。
    private var settings = DemoSettingsStore.load()

    private var style: SelectionStyle {
        get { SelectionStyle(rawValue: settings.labStyle) ?? .fluid }
        set { settings.labStyle = newValue.rawValue }
    }
    private var tabCount: Int {
        get { settings.labTabCount }
        set { settings.labTabCount = newValue }
    }
    private var swipeMode: TeroTabSwipeSelectionMode {
        get { TeroTabSwipeSelectionMode(rawValue: settings.labSwipeMode) ?? .disabled }
        set { settings.labSwipeMode = newValue.rawValue }
    }
    /// 0 代表沿用 `selectionIndicatorInsets` 從格位推導。
    private var selectionWidth: CGFloat {
        get { settings.selectionWidth }
        set { settings.selectionWidth = newValue }
    }
    private var selectionHeight: CGFloat {
        get { settings.selectionHeight }
        set { settings.selectionHeight = newValue }
    }
    /// 0 代表膠囊。
    private var cornerRadius: CGFloat {
        get { settings.cornerRadius }
        set { settings.cornerRadius = newValue }
    }
    private var iconScale: CGFloat {
        get { settings.iconScale }
        set { settings.iconScale = newValue }
    }
    private var duration: TimeInterval {
        get { settings.duration }
        set { settings.duration = newValue }
    }
    private var damping: CGFloat {
        get { settings.damping }
        set { settings.damping = newValue }
    }
    private var response: TimeInterval {
        get { settings.response }
        set { settings.response = newValue }
    }

    private let specs: [(identifier: String, title: String, symbol: String)] = [
        ("home", "Home", "house"),
        ("video", "Video", "play.rectangle"),
        ("create", "Create", "plus.circle"),
        ("chat", "Chat", "bubble.left.and.bubble.right"),
        ("profile", "Profile", "person.crop.circle"),
        ("more", "Library", "books.vertical")
    ]

    init() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.compact.maximumVisibleItems = 6
        configuration.regular.maximumVisibleItems = 6
        configuration.itemAppearance.selectionIndicatorStyle = .always
        tabController = TeroTabBarController(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        title = "Interaction Lab"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        embedTabController()
        installTabs()
        applyLive(animated: false)
    }

    private func embedTabController() {
        addChild(tabController)
        // 容器預設是不透明的 systemBackground；不清掉的話它會蓋住 backdrop，
        // 玻璃就沒有東西可以取樣（補充規格 §18）。
        tabController.view.backgroundColor = .clear
        for subview in [backdropView, tabController.view!] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        tabController.didMove(toParent: self)

        let panel = makePanel()
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: panel.topAnchor),

            tabController.view.topAnchor.constraint(equalTo: view.topAnchor),
            tabController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabController.view.bottomAnchor.constraint(equalTo: panel.topAnchor),

            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.46)
        ])
    }

    // MARK: - Panel

    private var knobs: [Knob] {
        [
            Knob(title: "方向鎖", range: 0...30, initial: Float(directionLock)) { $0.directionLock = $1 },
            Knob(title: "收合門檻", range: 10...160, initial: Float(scrollThreshold)) { $0.scrollThreshold = $1 },
            Knob(title: "收合秒數", range: 0.05...1, initial: Float(minimizeDuration)) { $0.minimizeDuration = $1 },
            Knob(title: "恢復秒數", range: 0.05...1, initial: Float(restoreDuration)) { $0.restoreDuration = $1 },
            Knob(title: "展開高度", range: 44...80, initial: Float(expandedHeight)) { $0.expandedHeight = $1 },
            Knob(title: "收合高度", range: 32...48, initial: Float(minimizedHeight)) { $0.minimizedHeight = $1 },
            Knob(title: "Duration", range: 0.05...1.2, initial: Float(duration)) { lab, value in
                lab.duration = value
            },
            Knob(title: "Damping", range: 0.2...1.0, initial: Float(damping)) { lab, value in
                lab.damping = value
            },
            Knob(title: "Response", range: 0.1...1.2, initial: Float(response)) { lab, value in
                lab.response = value
            },
            Knob(title: "Sel. width", range: 0...110, initial: Float(selectionWidth)) { lab, value in
                lab.selectionWidth = value
            },
            Knob(title: "Sel. height", range: 0...60, initial: Float(selectionHeight)) { lab, value in
                lab.selectionHeight = value
            },
            Knob(title: "Corner", range: 0...30, initial: Float(cornerRadius)) { lab, value in
                lab.cornerRadius = value
            },
            Knob(title: "Icon scale", range: 0.6...1.0, initial: Float(iconScale)) { lab, value in
                lab.iconScale = value
            }
        ]
    }

    private func makePanel() -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.1, alpha: 1)

        let styleControl = UISegmentedControl(items: SelectionStyle.allCases.map(\.title))
        styleControl.selectedSegmentIndex = style.rawValue
        styleControl.addTarget(self, action: #selector(styleChanged(_:)), for: .valueChanged)

        let countControl = UISegmentedControl(items: ["3", "4", "5", "6"])
        countControl.selectedSegmentIndex = tabCount - 3
        countControl.addTarget(self, action: #selector(countChanged(_:)), for: .valueChanged)

        let swipeControl = UISegmentedControl(items: ["點擊", "拖曳", "輕掃"])
        swipeControl.selectedSegmentIndex = swipeMode.rawValue
        swipeControl.addTarget(self, action: #selector(swipeChanged(_:)), for: .valueChanged)

        let actionControl = UISegmentedControl(items: ["Action 關", "Action 開"])
        actionControl.selectedSegmentIndex = 0
        actionControl.addTarget(self, action: #selector(actionChanged(_:)), for: .valueChanged)
        let resetButton = UIButton(type: .system)
        resetButton.setTitle("重設滑桿", for: .normal)
        resetButton.addTarget(self, action: #selector(resetKnobs), for: .touchUpInside)

        readout.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        readout.numberOfLines = 3
        readout.textColor = .white

        let rows = knobs.enumerated().map { index, knob -> UIView in
            makeKnobRow(knob, tag: index)
        }

        let stack = UIStackView(arrangedSubviews: [styleControl, countControl, swipeControl, actionControl] + rows + [resetButton, readout])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        container.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        return container
    }

    private var sliders: [UISlider] = []

    private func makeKnobRow(_ knob: Knob, tag: Int) -> UIView {
        let label = UILabel()
        label.text = knob.title
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.widthAnchor.constraint(equalToConstant: 84).isActive = true

        let slider = UISlider()
        slider.minimumValue = knob.range.lowerBound
        slider.maximumValue = knob.range.upperBound
        slider.value = knob.initial
        slider.tag = tag
        slider.addTarget(self, action: #selector(knobChanged(_:)), for: .valueChanged)
        sliders.append(slider)

        let row = UIStackView(arrangedSubviews: [label, slider])
        row.spacing = 8
        return row
    }

    // MARK: - Tabs

    private func installTabs() {
        let tabs = specs.prefix(tabCount).map { spec -> TeroTab in
            let item = TeroTabItem(
                title: spec.title,
                image: UIImage(systemName: spec.symbol),
                selectedImage: UIImage(systemName: "\(spec.symbol).fill") ?? UIImage(systemName: spec.symbol)
            )
            item.accessibilityIdentifier = "tab.\(spec.identifier)"
            let content = DemoVisibilityFeedViewController(collection: spec.identifier == "video")
            let navigation = UINavigationController(rootViewController: content)
            navigation.delegate = self
            return TeroTab(identifier: spec.identifier, viewController: navigation, item: item)
        }
        tabController.setTabs(Array(tabs), selectedIdentifier: specs[0].identifier, animated: false)
    }

    // MARK: - Live updates

    private func applyLive(animated: Bool) {
        let configuration = tabController.currentConfiguration()

        style.apply(to: &configuration.motion)
        // 滑桿永遠覆蓋預設：預設只是起點。
        configuration.motion.selectionDampingRatio = damping
        if configuration.motion.selectionResponse != nil {
            configuration.motion.selectionResponse = response
        } else {
            configuration.motion.selectionDuration = duration
        }
        configuration.itemAppearance.selectionIconScale = iconScale
        configuration.itemAppearance.selectionIndicatorCornerRadius = cornerRadius > 0 ? cornerRadius : nil

        let size = CGSize(width: selectionWidth, height: selectionHeight)
        for tab in tabController.tabs {
            tab.item.selectionSize = (size.width > 0 && size.height > 0) ? size : .zero
        }

        configuration.scrollConfiguration.directionLockDistance = directionLock
        configuration.scrollConfiguration.downwardTranslationThreshold = scrollThreshold
        configuration.motion.minimizeDuration = TimeInterval(minimizeDuration)
        configuration.motion.restoreDuration = TimeInterval(restoreDuration)
        configuration.floatingGlassAppearance.expandedHeight = expandedHeight
        configuration.floatingGlassAppearance.minimizedHeight = min(minimizedHeight, expandedHeight)
        configuration.swipeSelectionMode = swipeMode
        tabController.applyConfiguration(configuration, animated: animated)
        DemoSettingsStore.save(settings)
        updateReadout()
    }

    private func updateReadout() {
        let responseText = style == .static || style == .slide
            ? String(format: "duration=%.2f", duration)
            : String(format: "response=%.2f", response)
        let swipeText = ["點擊", "拖曳", "輕掃"][swipeMode.rawValue]
        readout.text = """
        style=\(style.title)  tabs=\(tabCount)  swipe=\(swipeText)  \(responseText)  damping=\(String(format: "%.2f", damping))
        selection=\(Int(selectionWidth))x\(Int(selectionHeight))  corner=\(Int(cornerRadius))  iconScale=\(String(format: "%.2f", iconScale))
        """
    }

    // MARK: - Actions

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        tabController.coordinateNavigationTransition(navigationController, to: viewController, animated: animated)
    }

    @objc private func actionChanged(_ sender: UISegmentedControl) {
        showsAction = sender.selectedSegmentIndex == 1
        let action = showsAction ? TeroTabActionItem(identifier: "compose", image: UIImage(systemName: "plus")) : nil
        action?.accessibilityLabel = "Compose"
        tabController.setActionItem(action, animated: false)
    }

    @objc private func styleChanged(_ sender: UISegmentedControl) {
        style = SelectionStyle(rawValue: sender.selectedSegmentIndex) ?? .fluid
        applyLive(animated: false)
    }

    @objc private func countChanged(_ sender: UISegmentedControl) {
        tabCount = sender.selectedSegmentIndex + 3
        installTabs()
        applyLive(animated: false)
    }

    @objc private func swipeChanged(_ sender: UISegmentedControl) {
        swipeMode = TeroTabSwipeSelectionMode(rawValue: sender.selectedSegmentIndex) ?? .disabled
        applyLive(animated: false)
    }

    @objc private func knobChanged(_ sender: UISlider) {
        let knobs = self.knobs
        guard knobs.indices.contains(sender.tag) else { return }
        knobs[sender.tag].apply(self, CGFloat(sender.value))
        applyLive(animated: false)
    }

    /// 把滑桿與存檔一起復原。只清滑桿不清存檔的話，下次啟動又會變回舊值。
    @objc private func resetKnobs() {
        let defaults = DemoSettings()
        duration = defaults.duration
        damping = defaults.damping
        response = defaults.response
        selectionWidth = defaults.selectionWidth
        selectionHeight = defaults.selectionHeight
        cornerRadius = defaults.cornerRadius
        iconScale = defaults.iconScale
        for (slider, knob) in zip(sliders, knobs) {
            slider.value = knob.initial
        }
        applyLive(animated: false)
    }
}
