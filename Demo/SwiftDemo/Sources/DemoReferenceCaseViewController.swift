import UIKit
import Tero

/// 參考影片裡的四種互動樣態。每一種只調整少數變因，方便並排比對。
enum DemoReferenceCase: String, CaseIterable {
    /// 共享選取膠囊在深色底上於 Tab 間平滑滑動，Icon 同步轉場。
    case a
    /// Lottie 自訂內容 + Badge，亮色底，動畫與選取進度同步。
    case b
    /// 照片／影片底，玻璃隨 backdrop 變化，含中央 Action-like 項目。
    case c
    /// Badge + 選取膠囊 + 獨立 Search Action，深色內容。
    case d

    var title: String {
        switch self {
        case .a: return "A · Floating selection"
        case .b: return "B · Animated content"
        case .c: return "C · Changing backdrop"
        case .d: return "D · Badge + action"
        }
    }

    var backdrop: DemoBackdrop {
        switch self {
        case .a: return .night
        case .b: return .daylight
        case .c: return .motion
        case .d: return .photo
        }
    }

    var hasAction: Bool {
        switch self {
        case .c, .d: return true
        case .a, .b: return false
        }
    }

    var specs: [(identifier: String, title: String, symbol: String)] {
        switch self {
        case .a:
            return [
                ("home", "Home", "house"),
                ("reels", "Reels", "play.rectangle"),
                ("shop", "Shop", "bag"),
                ("profile", "Profile", "person.crop.circle")
            ]
        case .b:
            return [
                ("home", "Home", "house"),
                ("live", "Live", "sparkles"),
                ("chat", "Chat", "bubble.left.and.bubble.right"),
                ("me", "Me", "person.crop.circle")
            ]
        case .c:
            return [
                ("feed", "Feed", "square.grid.2x2"),
                ("watch", "Watch", "play.rectangle"),
                ("groups", "Groups", "person.3"),
                ("alerts", "Alerts", "bell")
            ]
        case .d:
            return [
                ("chats", "Chats", "bubble.left.and.bubble.right"),
                ("calls", "Calls", "phone"),
                ("news", "News", "newspaper"),
                ("wallet", "Wallet", "creditcard")
            ]
        }
    }
}


/// 用同一個 view controller 跑四種案例：差別全部由 `DemoReferenceCase` 描述，
/// 不同案例走的是同一條程式路徑，比對到的才是設定造成的差異。
final class DemoReferenceCaseViewController: UIViewController {

    private let referenceCase: DemoReferenceCase
    private let tabController: TeroTabBarController
    private let backdropView: DemoBackdropView
    private let lottieProvider = LottieTabProvider(animationName: "spinner")

    init(referenceCase: DemoReferenceCase) {
        self.referenceCase = referenceCase
        self.backdropView = DemoBackdropView(backdrop: referenceCase.backdrop)

        let configuration = TeroTabBarConfiguration.defaultConfiguration()
        configuration.style = .floatingGlass
        configuration.compact.maximumVisibleItems = 5
        configuration.itemAppearance.selectionIndicatorStyle = .always
        configuration.motion.selectionResponse = 0.4
        configuration.motion.selectionDampingRatio = 0.84
        if referenceCase == .a {
            // 參考影片裡最接近的一組：略帶回彈，但不過度。
            configuration.motion.selectionDampingRatio = 0.7
        }
        self.tabController = TeroTabBarController(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        title = referenceCase.title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Backdrop 必須延伸到 Bar 後面，玻璃才取樣得到內容（補充規格 §18）。
        overrideUserInterfaceStyle = referenceCase.backdrop.prefersLightContent ? .dark : .light
        view.backgroundColor = .clear

        addChild(tabController)
        // 容器預設是不透明的 systemBackground；不清掉的話它會蓋住 backdrop，
        // 玻璃就沒有東西可以取樣（補充規格 §18）。
        tabController.view.backgroundColor = .clear
        for subview in [backdropView, tabController.view!] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.topAnchor.constraint(equalTo: view.topAnchor),
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        tabController.didMove(toParent: self)

        installTabs()
    }

    private func installTabs() {
        let tabs = referenceCase.specs.map { spec -> TeroTab in
            let item = TeroTabItem(
                title: spec.title,
                image: UIImage(systemName: spec.symbol),
                selectedImage: UIImage(systemName: "\(spec.symbol).fill") ?? UIImage(systemName: spec.symbol)
            )
            item.accessibilityIdentifier = "tab.\(spec.identifier)"
            decorate(item, identifier: spec.identifier)

            let content = UIViewController()
            content.view.backgroundColor = .clear
            return TeroTab(identifier: spec.identifier, viewController: content, item: item)
        }
        tabController.setTabs(tabs, selectedIdentifier: referenceCase.specs[0].identifier, animated: false)

        guard referenceCase.hasAction else { return }
        let symbol = referenceCase == .d ? "magnifyingglass" : "plus"
        let action = TeroTabActionItem(identifier: "action", image: UIImage(systemName: symbol))
        action.accessibilityLabel = referenceCase == .d ? "搜尋" : "新增"
        action.accessibilityIdentifier = "tab.action"
        tabController.setActionItem(action, animated: false)
    }

    private func decorate(_ item: TeroTabItem, identifier: String) {
        switch referenceCase {
        case .a:
            break
        case .b:
            // 自訂內容 + Badge：兩者要在同一次轉場裡同步（補充規格 §9）。
            if identifier == "live" { item.contentProvider = lottieProvider }
            if identifier == "chat" { item.badge = .value("12") }
        case .c:
            // 不同 Tab 可以有不同的選取尺寸（補充規格 §4）。
            if identifier == "watch" { item.selectionSize = CGSize(width: 64, height: 44) }
        case .d:
            if identifier == "chats" { item.badge = .value("999+") }
            if identifier == "news" { item.badge = .dot() }
        }
    }
}
