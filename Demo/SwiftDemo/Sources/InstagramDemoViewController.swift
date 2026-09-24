import UIKit
import Tero

/// 計畫書 §47 的 Instagram 參考案例（issue #98）。
///
/// 目的不是做一個 Instagram clone，而是證明「IG 類型的 UI 可以用 Tero 的原語自然建立出來」
/// （§57）。每一項對應到一個原語：
///
/// | Instagram 的樣子 | Tero 的原語 |
/// |---|---|
/// | 五格、只有圖示、不透明的 Classic Bar | `style = .classic`、`title = nil`、`usesBlurEffect = false` |
/// | 中央的「＋」不是 Tab | `TeroTabActionItem`（Classic 置於中央） |
/// | Profile 是頭像、選取時多一圈 | `TeroTabInteractiveContentProvider` |
/// | 切換瞬間換圖、不縮放 | `contentTransitionDuration = 0`、`selectionIconScale = 1` |
/// | Reels 的 Bar 變黑 | `TeroTabBarAppearanceProviding` |
/// | 長按 Profile 切帳號 | `didLongPress` |
/// | 重選 Home 回頂 | `didReselect` |
/// | Home 的 header 在自己的高度內收完 | `TeroNavigationBar` ＋ `chromeCollapseDistance = 44`、收合高度 0 |
/// | Profile 的分段列留下 | `secondaryView` ＋ 收合高度 = 分段列高度 |
/// | 每個 Tab 各自一疊 | `TeroNavigationContainer` |
///
/// 全部走 SF Symbols 與程式繪製（ADR-0007）。
final class InstagramDemoViewController: UIViewController {

    private let tabController: TeroTabBarController
    private let avatarProvider = AvatarTabProvider()

    init() {
        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .classic
        configuration.compact.maximumVisibleItems = 5
        // IG 的 Bar 是不透明的實色，上緣一條 hairline。
        configuration.classicAppearance.usesBlurEffect = false
        configuration.classicAppearance.backgroundColor = .systemBackground
        configuration.classicAppearance.actionSize = CGSize(width: 44, height: 44)
        // IG 的圖示是「輪廓 → 填滿」瞬間換圖：同色、不縮放、不過衝、不交棒。
        configuration.itemAppearance.normalTintColor = .label
        configuration.itemAppearance.selectedTintColor = .label
        configuration.itemAppearance.selectionIconScale = 1
        configuration.itemAppearance.selectionIconOvershoot = 0
        configuration.itemAppearance.contentSize = CGSize(width: 26, height: 26)
        configuration.motion.contentTransitionDuration = 0
        configuration.motion.selectionDuration = 0.001
        configuration.motion.selectionResponse = nil
        tabController = TeroTabBarController(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("未支援 storyboard") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tabController.delegate = self
        addChild(tabController)
        tabController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabController.view)
        NSLayoutConstraint.activate([
            tabController.view.topAnchor.constraint(equalTo: view.topAnchor),
            tabController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        tabController.didMove(toParent: self)
        installTabs()
    }

    private func installTabs() {
        func container(_ root: InstagramPage) -> TeroNavigationContainer {
            TeroNavigationContainer(rootViewController: root)
        }
        let home = InstagramHomePage()
        let homeContainer = container(home)
        // IG 的 header 在自己的高度內就收完。
        homeContainer.chromeCollapseDistance = TeroNavigationBar.primaryHeight
        // IG 的 header 是不透明的紙色，與內容同色：edge effect 沒有東西可以處理，關掉它，
        // 免得容器把 header 的動態系統色解析成灰一階的 bar 變體。
        homeContainer.isScrollEdgeEffectEnabled = false

        let profile = InstagramProfilePage()
        let profileContainer = container(profile)
        profileContainer.isScrollEdgeEffectEnabled = false

        let tabs: [TeroTab] = [
            TeroTab(identifier: "home", viewController: homeContainer,
                    item: icon("house", "house.fill", "home")),
            TeroTab(identifier: "search", viewController: container(InstagramSearchPage()),
                    item: icon("magnifyingglass", "magnifyingglass", "search")),
            TeroTab(identifier: "reels", viewController: container(InstagramReelsPage()),
                    item: icon("play.rectangle", "play.rectangle.fill", "reels")),
            TeroTab(identifier: "profile", viewController: profileContainer, item: avatarItem())
        ]
        tabController.setTabs(tabs, selectedIdentifier: "home", animated: false)
        tabController.setBadge(.dot(), forTabWithIdentifier: "reels", animated: false)

        let create = TeroTabActionItem(identifier: "create", image: UIImage(systemName: "plus.app"))
        create.accessibilityLabel = "Create"
        create.accessibilityIdentifier = "ig.action.create"
        tabController.setActionItem(create, animated: false)
    }

    /// IG 的 Tab 沒有標題：`title` 給 nil，caption 就不佔位。
    private func icon(_ normal: String, _ selected: String, _ identifier: String) -> TeroTabItem {
        let item = TeroTabItem(title: nil, image: UIImage(systemName: normal),
                               selectedImage: UIImage(systemName: selected))
        item.accessibilityLabel = identifier.capitalized
        item.accessibilityIdentifier = "ig.tab.\(identifier)"
        return item
    }

    private func avatarItem() -> TeroTabItem {
        let item = TeroTabItem(title: nil, image: nil, selectedImage: nil)
        item.contentProvider = avatarProvider
        item.accessibilityLabel = "Profile"
        item.accessibilityIdentifier = "ig.tab.profile"
        return item
    }

    private func presentSheet(title: String, options: [String]) {
        let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        options.forEach { sheet.addAction(UIAlertAction(title: $0, style: .default)) }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = tabController.tabBar
        present(sheet, animated: true)
    }
}

extension InstagramDemoViewController: TeroTabBarControllerDelegate {

    /// 重選：回頂，不 popToRoot——IG 在 Home 的行為。
    func teroTabBarController(_ tabController: TeroTabBarController, didReselect tab: TeroTab) {
        guard let container = tab.viewController as? TeroNavigationContainer else { return }
        if container.viewControllers.count > 1 {
            container.popToRootViewController(animated: true)
        } else {
            (container.topViewController as? InstagramPage)?.scrollToTop()
        }
    }

    /// 長按 Profile：帳號切換。其他 Tab 不理。
    func teroTabBarController(_ tabController: TeroTabBarController, didLongPress tab: TeroTab) {
        guard tab.identifier == "profile" else { return }
        presentSheet(title: "Switch account", options: ["@tero", "@tero.design", "Add account"])
    }

    /// 中央的「＋」：只發事件、不改選取。
    func teroTabBarController(_ tabController: TeroTabBarController, didTrigger actionItem: TeroTabActionItem) {
        presentSheet(title: "Create", options: ["Post", "Story", "Reel", "Live"])
    }
}

// MARK: - 頭像 Tab

/// 程式繪製的頭像：漸層圓，選取時外圈一環。進階協定讓那一環跟著選取進度長出來。
final class AvatarTabProvider: NSObject, TeroTabInteractiveContentProvider {

    private final class AvatarView: UIView {
        let ring = CAShapeLayer()
        let face = CAGradientLayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            face.colors = [UIColor.systemOrange.cgColor, UIColor.systemPink.cgColor, UIColor.systemPurple.cgColor]
            face.startPoint = CGPoint(x: 0, y: 0)
            face.endPoint = CGPoint(x: 1, y: 1)
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = UIColor.label.cgColor
            ring.lineWidth = 1.5
            layer.addSublayer(face)
            layer.addSublayer(ring)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            super.layoutSubviews()
            let inset = bounds.insetBy(dx: 3, dy: 3)
            face.frame = inset
            face.cornerRadius = inset.width / 2
            ring.frame = bounds
            ring.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75)).cgPath
        }
        override func tintColorDidChange() {
            super.tintColorDidChange()
            ring.strokeColor = UIColor.label.cgColor
        }
    }

    func makeContentView() -> UIView { AvatarView(frame: .zero) }

    func updateContentView(_ contentView: UIView, selected: Bool,
                           presentationState: TeroTabBarPresentationState, animated: Bool) {
        (contentView as? AvatarView)?.ring.opacity = selected ? 1 : 0
    }

    func updateContentView(_ contentView: UIView, selectionProgress: CGFloat, animated: Bool) {
        (contentView as? AvatarView)?.ring.opacity = Float(selectionProgress)
    }
}

// MARK: - 頁面

/// IG 的每一頁：一張清單，交出自己的 scroll view，自己提供 chrome。
class InstagramPage: UIViewController, TeroScrollProviding, TeroNavigationChromeProviding, UITableViewDataSource {
    let tableView = UITableView()
    var rows: [String] { (0..<40).map { "\(pageName) · \($0)" } }
    var pageName: String { "Page" }
    /// 這一頁的 chrome 是自己畫的，返回鍵要自己決定——鏡射的返回鍵才由容器判斷。
    var hasBack: Bool { teroNavigationContainer?.rootViewController !== self }

    var teroTrackingScrollView: UIScrollView? { tableView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        // 內容不滿一頁時 `.automatic` 的頂端 inset 是 0（README 遷移第三點），主捲動容器升成 always。
        tableView.contentInsetAdjustmentBehavior = .always
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func scrollToTop() {
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: true)
    }

    /// 返回鍵：經 `teroNavigationContainer` 找容器，不持有它，chrome 因此不反向強引用（ADR-0013）。
    func makeBackButton() -> TeroNavigationButton {
        let back = TeroNavigationButton(image: UIImage(systemName: "chevron.backward"), material: .automatic)
        back.addAction(UIAction { [weak self] _ in self?.teroNavigationContainer?.popViewController(animated: true) },
                       for: .touchUpInside)
        return back
    }

    func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        bar.title = pageName
        if hasBack { bar.leadingItems = [makeBackButton()] }
        return bar
    }

    var teroNavigationChromeHeight: CGFloat { TeroNavigationBar.primaryHeight }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "row")
        cell.textLabel?.text = rows[indexPath.row]
        cell.detailTextLabel?.text = indexPath.row == 0 ? "往上滑看 header 收合；再點一次 Home 回頂" : nil
        cell.backgroundColor = .clear
        return cell
    }
}

/// Home：wordmark 標題、heart／messenger，整條 header 隨捲動收到 0。
final class InstagramHomePage: InstagramPage {
    override var pageName: String { "Home" }

    override func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        bar.showsBackdrop = false

        let wordmark = UILabel()
        wordmark.text = "Instagram"
        if let descriptor = UIFont.systemFont(ofSize: 26, weight: .bold).fontDescriptor
            .withDesign(.serif)?.withSymbolicTraits([.traitBold, .traitItalic]) {
            wordmark.font = UIFont(descriptor: descriptor, size: 26)
        }
        wordmark.translatesAutoresizingMaskIntoConstraints = false
        // titleView 要自己說得出尺寸（README「標題的外觀」）。
        wordmark.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.titleView = wordmark

        // IG 的圖示是黑的，不是系統藍。
        let heart = TeroNavigationButton(image: UIImage(systemName: "heart"), material: .automatic)
        heart.tintColor = .label
        heart.accessibilityIdentifier = "ig.home.activity"
        let messenger = TeroNavigationButton(image: UIImage(systemName: "paperplane"), material: .automatic)
        messenger.tintColor = .label
        messenger.accessibilityIdentifier = "ig.home.messages"
        messenger.addAction(UIAction { [weak self] _ in
            guard let self, let container = self.teroNavigationContainer else { return }
            container.pushViewController(InstagramDetailPage(name: "Messages"), animated: true)
        }, for: .touchUpInside)
        bar.trailingItems = [heart, messenger]

        // IG 的 header 是整條往上滑到狀態列底下消失、不淡出，而狀態列那一段維持不透明。
        // 所以 chrome 是一個會裁切的殼：殼的高度由容器內插（44 → 0，再加安全區），裡面的列
        // 釘在殼的頂邊、高度固定，收合時往上平移。狀態列那一段是一塊不透明的擋板，疊在列的
        // **上面**：列是滑到它後面消失，不是滑進狀態列的文字裡。
        let shell = UIView()
        shell.clipsToBounds = true
        // 固定色而不是 systemBackground：scroll edge effect 的容器會把動態系統色解析成 bar 的
        // 變體（白變 245 灰）。這一頁的容器已經關掉 edge effect（見 installTabs），這裡再用
        // 固定色，兩邊都守住「header 與內容同色」。
        shell.backgroundColor = Self.paper
        bar.translatesAutoresizingMaskIntoConstraints = false
        shell.addSubview(bar)
        let statusShim = UIView()
        statusShim.backgroundColor = Self.paper
        statusShim.translatesAutoresizingMaskIntoConstraints = false
        shell.addSubview(statusShim)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: shell.topAnchor),
            bar.leadingAnchor.constraint(equalTo: shell.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: shell.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: shell.safeAreaLayoutGuide.topAnchor,
                                        constant: TeroNavigationBar.primaryHeight),
            statusShim.topAnchor.constraint(equalTo: shell.topAnchor),
            statusShim.leadingAnchor.constraint(equalTo: shell.leadingAnchor),
            statusShim.trailingAnchor.constraint(equalTo: shell.trailingAnchor),
            statusShim.bottomAnchor.constraint(equalTo: shell.safeAreaLayoutGuide.topAnchor)
        ])
        return shell
    }

    // optional 成員在子類別要明寫 @objc：協定的 conformance 宣告在父類別，推論不會往下走。

    /// 收合到 0：整條 header 讓開，只剩狀態列那一段。
    @objc var teroNavigationChromeCollapsedHeight: CGFloat { 0 }

    @objc func updateTeroNavigationChrome(_ chromeView: UIView, collapseProgress: CGFloat) {
        guard let bar = chromeView.subviews.first as? TeroNavigationBar else { return }
        bar.transform = CGAffineTransform(translationX: 0, y: -TeroNavigationBar.primaryHeight * collapseProgress)
    }

    /// IG 的紙色：淺色白、深色黑。固定色，不走會被 edge effect 容器改寫的動態系統色。
    static let paper = UIColor { $0.userInterfaceStyle == .dark ? .black : .white }
}

/// Search：搜尋欄長相的標題。
final class InstagramSearchPage: InstagramPage {
    override var pageName: String { "Search" }

    override func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        let field = UISearchTextField()
        field.placeholder = "Search"
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.titleView = field
        return bar
    }
}

/// Reels：黑底、白字，Bar 也跟著變黑（`TeroTabBarAppearanceProviding`）。
final class InstagramReelsPage: InstagramPage, TeroTabBarAppearanceProviding {
    override var pageName: String { "Reels" }

    @objc var preferredTeroTabBarUserInterfaceStyle: UIUserInterfaceStyle { .dark }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        tableView.backgroundColor = .black
    }

    override func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        bar.showsBackdrop = false
        bar.title = "Reels"
        bar.titleColor = .white
        bar.titleFont = .systemFont(ofSize: 22, weight: .bold)
        let camera = TeroNavigationButton(image: UIImage(systemName: "camera"), material: .plain)
        camera.tintColor = .white
        bar.trailingItems = [camera]
        return bar
    }
}

/// Profile：使用者名稱、右上的＋與選單，底下一條會留下的分段列。
final class InstagramProfilePage: InstagramPage {
    override var pageName: String { "tero" }
    private let segmentHeight: CGFloat = 44

    override func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        bar.title = "tero"
        bar.titleFont = .systemFont(ofSize: 20, weight: .semibold)
        let add = TeroNavigationButton(image: UIImage(systemName: "plus.app"), material: .automatic)
        let menu = TeroNavigationButton(image: UIImage(systemName: "line.3.horizontal"), material: .automatic)
        bar.trailingItems = [add, menu]

        let segments = UISegmentedControl(items: [
            UIImage(systemName: "squareshape.split.3x3") as Any,
            UIImage(systemName: "play.rectangle") as Any,
            UIImage(systemName: "person.crop.square") as Any
        ])
        segments.selectedSegmentIndex = 0
        segments.translatesAutoresizingMaskIntoConstraints = false
        let holder = UIView()
        holder.addSubview(segments)
        NSLayoutConstraint.activate([
            segments.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            segments.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -16),
            segments.centerYAnchor.constraint(equalTo: holder.centerYAnchor)
        ])
        bar.secondaryView = holder
        return bar
    }

    override var teroNavigationChromeHeight: CGFloat { TeroNavigationBar.primaryHeight + segmentHeight }
    /// 收合後留下分段列：IG Profile 的 sticky segments。
    @objc var teroNavigationChromeCollapsedHeight: CGFloat { segmentHeight }

    @objc func updateTeroNavigationChrome(_ chromeView: UIView, collapseProgress: CGFloat) {
        (chromeView as? TeroNavigationBar)?.applyCollapseProgress(collapseProgress)
    }
}

/// 從 Home 推進去的一頁：標準的返回、標題、trailing。
final class InstagramDetailPage: InstagramPage {
    private let name: String
    init(name: String) {
        self.name = name
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("未支援 storyboard") }
    override var pageName: String { name }
}
