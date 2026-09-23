import UIKit
import Tero

/// 計畫書 §47 的三個必做參考 Demo。
///
/// 每一個都用真的 `TeroNavigationContainer` 疊出來：這裡是唯一看得出「chrome 由畫面
/// 自己提供」在實際使用上長什麼樣的地方。
enum NavigationReferenceCase: String, CaseIterable {
    /// Back、Title、Trailing action。最小可用的導覽列。
    case standard
    /// 頂部玻璃控制項。與 standard 只差材質，方便並排比對。
    case glass
    /// 完整的 Instagram 參考案例（issue #98），實作在 `InstagramDemoViewController`。
    case instagram
    /// 頁面只碰 `navigationItem`，chrome 由 `bind(to:backAction:)` 鏡射（issue #89）。
    case mirror

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .glass: return "Glass"
        case .instagram: return "Instagram"
        case .mirror: return "Mirror"
        }
    }

    var summary: String {
        switch self {
        case .standard: return "Back · Title · Trailing action"
        case .glass: return "Top glass controls"
        case .instagram: return "5 icon tabs · action · avatar · dark Reels · collapsing header"
        case .mirror: return "navigationItem · KVO · synthesised back"
        }
    }
}

// MARK: - 共用的內容頁

/// 一頁長內容。交出自己的 scroll view，讓頂部 chrome 與 Tab Bar 讀同一份捲動輸入。
private class LabContentPage: UIViewController, TeroScrollProviding, UITableViewDataSource {
    private let tableView = UITableView()
    let pageTitle: String

    init(title: String) {
        self.pageTitle = title
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("未支援 storyboard") }

    var teroTrackingScrollView: UIScrollView? { tableView }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 40 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "row")
        cell.textLabel?.text = "\(pageTitle) · row \(indexPath.row)"
        cell.detailTextLabel?.text = indexPath.row == 0 ? "往上滑，看頂部 chrome 收合" : nil
        return cell
    }
}

// MARK: - Standard / Glass：同一份版面，只換材質

/// Back、Title、Trailing action。
///
/// 容器不認得標題也不認得按鈕——它只要一個 view 和一條 0…1 的進度。
private final class BarChromePage: LabContentPage, TeroNavigationChromeProviding {
    private let material: TeroNavigationButtonMaterial
    private let showsBack: Bool
    /// 容器持有頁面，頁面只能反向弱引用。
    weak var container: TeroNavigationContainer?
    var onTrailingAction: (() -> Void)?

    init(title: String, material: TeroNavigationButtonMaterial, showsBack: Bool) {
        self.material = material
        self.showsBack = showsBack
        super.init(title: title)
    }
    required init?(coder: NSCoder) { fatalError("未支援 storyboard") }

    func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        bar.title = pageTitle
        if showsBack {
            let back = TeroNavigationButton(image: UIImage(systemName: "chevron.left"), material: material)
            back.accessibilityIdentifier = "nav.back"
            back.addAction(UIAction { [weak self] _ in
                self?.container?.popViewController(animated: true)
            }, for: .touchUpInside)
            bar.leadingItems = [back]
        }
        let action = TeroNavigationButton(image: UIImage(systemName: "square.and.arrow.up"), material: material)
        action.accessibilityIdentifier = "nav.trailing"
        action.addAction(UIAction { [weak self] _ in self?.onTrailingAction?() }, for: .touchUpInside)
        bar.trailingItems = [action]
        return bar
    }

    /// Primary row 的高度。宣告值不含狀態列——容器補上自己的安全區。
    var teroNavigationChromeHeight: CGFloat { 44 }
}

// MARK: - Mirror：頁面照舊寫 navigationItem，chrome 那一側只有三行

/// 既有頁面不改寫法就能接上：這一頁只碰 `navigationItem`，右上兩顆按鈕一顆 push、一顆
/// 在執行期切自己的 `isEnabled`，鏡射要跟得上。
private final class NavigationItemPage: LabContentPage, TeroNavigationChromeProviding {
    weak var container: TeroNavigationContainer?

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = pageTitle
        let push = UIBarButtonItem(
            title: nil, image: UIImage(systemName: "plus.circle"),
            primaryAction: UIAction { [weak self] _ in
                guard let self, let container = self.container else { return }
                let detail = NavigationItemPage(title: "\(self.pageTitle) · detail")
                detail.container = container
                container.pushViewController(detail, animated: true)
            }, menu: nil
        )
        push.accessibilityIdentifier = "mirror.push"
        let toggle = UIBarButtonItem(
            title: "Save", image: nil,
            primaryAction: UIAction { [weak self] _ in
                // 執行期換按鈕狀態：鏡射要跟上，不是綁定那一刻抄一次。
                self?.navigationItem.rightBarButtonItems?.first?.isEnabled.toggle()
            }, menu: nil
        )
        toggle.style = .done
        navigationItem.rightBarButtonItems = [push, toggle]
    }

    func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        // root 沒有返回鍵；其餘頁面由呼叫端給返回動作，chrome 不必反向引用容器。
        let isRoot = container?.rootViewController === self
        bar.bind(to: navigationItem, backAction: isRoot ? nil : { [weak self] in
            self?.container?.popViewController(animated: true)
        })
        return bar
    }

    var teroNavigationChromeHeight: CGFloat { TeroNavigationBar.primaryHeight }
}

// MARK: - 入口

final class NavigationLabViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Navigation Lab"
        view.backgroundColor = .systemBackground

        let rows = NavigationReferenceCase.allCases.map { referenceCase -> UIView in
            let button = UIButton(type: .system)
            button.accessibilityIdentifier = "lab.\(referenceCase.rawValue)"
            var configuration = UIButton.Configuration.bordered()
            configuration.title = referenceCase.title
            configuration.subtitle = referenceCase.summary
            configuration.titleAlignment = .leading
            button.configuration = configuration
            button.contentHorizontalAlignment = .leading
            button.addAction(UIAction { [weak self] _ in
                self?.open(referenceCase)
            }, for: .touchUpInside)
            return button
        }

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    private func open(_ referenceCase: NavigationReferenceCase) {
        let controller: UIViewController
        switch referenceCase {
        case .standard: controller = Self.makeBarDemo(material: .plain, title: "Standard")
        case .glass: controller = Self.makeBarDemo(material: .glass, title: "Glass")
        case .instagram: controller = InstagramDemoViewController()
        case .mirror: controller = Self.makeMirrorDemo()
        }
        controller.modalPresentationStyle = .fullScreen
        addCloseControl(to: controller)
        present(controller, animated: true)
    }

    private static func makeBarDemo(
        material: TeroNavigationButtonMaterial,
        title: String
    ) -> TeroNavigationContainer {
        let root = BarChromePage(title: title, material: material, showsBack: false)
        let container = TeroNavigationContainer(rootViewController: root)
        root.container = container
        root.onTrailingAction = { [weak container] in
            guard let container else { return }
            let detail = BarChromePage(title: "\(title) · detail", material: material, showsBack: true)
            detail.container = container
            container.pushViewController(detail, animated: true)
        }
        return container
    }

    /// 單獨使用的容器：頂部 chrome 由 `navigationItem` 鏡射而來。
    private static func makeMirrorDemo() -> TeroNavigationContainer {
        let root = NavigationItemPage(title: "Mirror")
        let container = TeroNavigationContainer(rootViewController: root)
        root.container = container
        return container
    }

    /// 這幾個 Demo 都沒有系統導覽列，關閉鍵要自己放。
    private func addCloseControl(to controller: UIViewController) {
        let close = UIButton(type: .close)
        close.accessibilityIdentifier = "lab.close"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        controller.loadViewIfNeeded()
        controller.view.addSubview(close)
        NSLayoutConstraint.activate([
            close.trailingAnchor.constraint(
                equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            close.bottomAnchor.constraint(
                equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor, constant: -96)
        ])
    }
}
