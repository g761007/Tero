import XCTest
import UIKit
@testable import Tero

/// 跨物件共用的事件記錄，用來斷言事件的**順序**而不只是有無。
final class EventLog {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
    func reset() { events.removeAll() }
    func events(matching prefix: String) -> [String] {
        events.filter { $0.hasPrefix(prefix) }
    }
}

/// 記錄自身 appearance 事件的 child view controller。
final class LifecycleSpyViewController: UIViewController {

    let name: String
    private let log: EventLog

    init(name: String, log: EventLog) {
        self.name = name
        self.log = log
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        log.record("\(name).willAppear")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        log.record("\(name).didAppear")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        log.record("\(name).willDisappear")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        log.record("\(name).didDisappear")
    }
}

/// 記錄 delegate 回呼的內容與順序。`shouldSelectResult` 為 nil 時不實作該回呼的答案（回傳 true）。
final class DelegateRecorder: NSObject, TeroTabBarControllerDelegate {

    private let log: EventLog

    var shouldSelectResult: Bool?
    var shouldSelectCalls: [(identifier: String, source: TeroTabSelectionSource)] = []
    var didSelectCalls: [(identifier: String, source: TeroTabSelectionSource)] = []
    var didReselectCalls: [String] = []

    init(log: EventLog) {
        self.log = log
        super.init()
    }

    func teroTabBarController(
        _ tabController: TeroTabBarController,
        shouldSelect tab: TeroTab,
        source: TeroTabSelectionSource
    ) -> Bool {
        shouldSelectCalls.append((tab.identifier, source))
        log.record("delegate.shouldSelect(\(tab.identifier))")
        return shouldSelectResult ?? true
    }

    func teroTabBarController(
        _ tabController: TeroTabBarController,
        didSelect tab: TeroTab,
        source: TeroTabSelectionSource
    ) {
        didSelectCalls.append((tab.identifier, source))
        log.record("delegate.didSelect(\(tab.identifier))")
    }

    func teroTabBarController(_ tabController: TeroTabBarController, didReselect tab: TeroTab) {
        didReselectCalls.append(tab.identifier)
        log.record("delegate.didReselect(\(tab.identifier))")
    }
}

/// 所有測試都透過 controller 的公開 API 驅動（見 #19 的 Testing Decisions）。
///
/// `@testable` 只用於一件事：替換 `TeroDiagnostics.reportHandler`，
/// 好讓計畫書 §54 的「Release 安全 fallback」在 Debug 下也能被驗證，
/// 而不是一碰就 crash。除此之外不觸及任何內部型別。
class TeroTabBarControllerTestCase: XCTestCase {

    var window: UIWindow!
    var log: EventLog!
    var recorder: DelegateRecorder!
    var reportedDiagnostics: [String] = []

    private var originalReportHandler: ((String, StaticString, UInt) -> Void)!
    private var originalReduceTransparency: (() -> Bool)!
    private var originalReduceMotion: (() -> Bool)!

    override func setUp() {
        super.setUp()
        log = EventLog()
        recorder = DelegateRecorder(log: log)
        reportedDiagnostics = []
        originalReportHandler = TeroDiagnostics.reportHandler
        TeroDiagnostics.reportHandler = { [weak self] message, _, _ in
            self?.reportedDiagnostics.append(message)
        }
        originalReduceTransparency = TeroAccessibility.isReduceTransparencyEnabled
        originalReduceMotion = TeroAccessibility.isReduceMotionEnabled
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    /// 覆寫輔助功能設定。這兩個設定無法在測試中真的開啟，因此以注入點模擬。
    func overrideAccessibility(reduceTransparency: Bool? = nil, reduceMotion: Bool? = nil) {
        if let reduceTransparency {
            TeroAccessibility.isReduceTransparencyEnabled = { reduceTransparency }
        }
        if let reduceMotion {
            TeroAccessibility.isReduceMotionEnabled = { reduceMotion }
        }
    }

    override func tearDown() {
        TeroDiagnostics.reportHandler = originalReportHandler
        originalReportHandler = nil
        TeroAccessibility.isReduceTransparencyEnabled = originalReduceTransparency
        TeroAccessibility.isReduceMotionEnabled = originalReduceMotion
        originalReduceTransparency = nil
        originalReduceMotion = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        recorder = nil
        log = nil
        super.tearDown()
    }

    // MARK: Builders

    func makeTab(_ identifier: String, enabled: Bool = true) -> TeroTab {
        let item = TeroTabItem(title: identifier, image: nil, selectedImage: nil)
        item.isEnabled = enabled
        item.accessibilityIdentifier = "tab.\(identifier)"
        return TeroTab(
            identifier: identifier,
            viewController: LifecycleSpyViewController(name: identifier, log: log),
            item: item
        )
    }

    func makeController(
        configuration: TeroTabBarConfiguration = .defaultConfiguration()
    ) -> TeroTabBarController {
        // 讓 More 也能用同一套 accessibilityIdentifier 查找
        configuration.moreItem.accessibilityIdentifier = "tab.more"
        let controller = TeroTabBarController(configuration: configuration)
        controller.delegate = recorder
        return controller
    }

    /// 以 `setOverrideTraitCollection` 強制子 controller 的 size class，
    /// 用來驗證 Compact / Regular 的選用與 runtime 切換。
    final class TraitHostViewController: UIViewController {
        private weak var embedded: UIViewController?

        func embed(_ child: UIViewController, horizontalSizeClass: UIUserInterfaceSizeClass) {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.topAnchor.constraint(equalTo: view.topAnchor),
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            child.didMove(toParent: self)
            embedded = child
            override(horizontalSizeClass: horizontalSizeClass)
        }

        func override(horizontalSizeClass: UIUserInterfaceSizeClass) {
            guard let embedded else { return }
            setOverrideTraitCollection(
                UITraitCollection(horizontalSizeClass: horizontalSizeClass),
                forChild: embedded
            )
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    /// 把 controller 放進可覆寫 size class 的 host 並上螢幕。
    @discardableResult
    func presentWithSizeClass(
        _ controller: TeroTabBarController,
        _ horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> TraitHostViewController {
        let host = TraitHostViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        host.embed(controller, horizontalSizeClass: horizontalSizeClass)
        RunLoop.current.run(until: Date())
        return host
    }

    /// 等某個狀態成立，而不是等固定秒數。
    ///
    /// 動畫推進多少取決於 runloop 排程，而排程取決於機器當下的負載。
    /// 「跑 0.25 秒再斷言動畫已落定」在快的機器上通過、在忙碌的 runner 上量到中途的值——
    /// 那不是被測行為變了，是測試問錯了問題。逾時仍然失敗，所以「動畫根本沒跑」不會被誤判成通過。
    @discardableResult
    func waitUntil(
        _ description: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTFail("等不到：\(description)", file: file, line: line)
        return false
    }

    /// 讓 controller 真正上螢幕，appearance 事件才會發生。
    func present(_ controller: TeroTabBarController) {
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.current.run(until: Date())
    }

    /// 只載入 view，不上螢幕。用來驗證「容器不可見時不發 appearance 事件」。
    func loadWithoutPresenting(_ controller: TeroTabBarController) {
        controller.loadViewIfNeeded()
        controller.view.layoutIfNeeded()
    }

    /// 從公開的 `tabBar` 視圖階層裡找出某個 Tab 的可點擊控制項。
    /// 只用公開的 UIKit API（`UIControl`、`accessibilityIdentifier`），不觸及內部型別。
    func tabBarControl(for identifier: String, in controller: TeroTabBarController) -> UIControl? {
        func search(_ view: UIView) -> UIControl? {
            if let control = view as? UIControl,
               control.accessibilityIdentifier == "tab.\(identifier)" {
                return control
            }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(controller.tabBar)
    }

    /// 模擬點擊。
    ///
    /// 不用 `UIControl.sendActions(for:)`——它會繞經 `UIApplication`，在沒有宿主 App 的
    /// 測試環境下不會派送。改為直接呼叫控制項自己註冊的 target-action，那與真實點擊
    /// 走的是同一條路徑，且一樣只用公開 API。
    func tapTabBarItem(_ identifier: String, in controller: TeroTabBarController) {
        guard let control = tabBarControl(for: identifier, in: controller) else {
            XCTFail("找不到 \(identifier) 的 Tab 控制項")
            return
        }
        guard control.isEnabled else { return }  // UIKit 不會把觸控送給 disabled 控制項
        invokeTouchUpInside(on: control)
    }

    /// 略過 `isEnabled` 檢查，直接觸發動作。
    /// 用來驗證即使動作被強行觸發，controller 自己的守門仍然成立。
    func forceTapTabBarItem(_ identifier: String, in controller: TeroTabBarController) {
        guard let control = tabBarControl(for: identifier, in: controller) else {
            XCTFail("找不到 \(identifier) 的 Tab 控制項")
            return
        }
        invokeTouchUpInside(on: control)
    }

    private func invokeTouchUpInside(on control: UIControl) {
        for target in control.allTargets {
            let actions = control.actions(forTarget: target, forControlEvent: .touchUpInside) ?? []
            for action in actions {
                _ = (target as AnyObject).perform(Selector(action), with: control)
            }
        }
    }

    /// 找出包含某控制項的膠囊：由該控制項往上走，第一個 `UIVisualEffectView` 祖先。
    /// 比寫死 superview 鏈穩——中間會夾著 `contentView`，外面還有玻璃容器。
    func capsule(containing view: UIView, in controller: TeroTabBarController) -> UIVisualEffectView? {
        var current: UIView? = view.superview
        while let candidate = current {
            if let effectView = candidate as? UIVisualEffectView { return effectView }
            if candidate === controller.tabBar { return nil }
            current = candidate.superview
        }
        return nil
    }

    /// 膠囊外面的玻璃容器（若有）。
    func glassContainer(around capsule: UIVisualEffectView, in controller: TeroTabBarController) -> UIVisualEffectView? {
        var current: UIView? = capsule.superview
        while let candidate = current {
            if let effectView = candidate as? UIVisualEffectView { return effectView }
            if candidate === controller.tabBar { return nil }
            current = candidate.superview
        }
        return nil
    }

    // MARK: Colours

    /// 比較兩個顏色**畫出來的結果**。
    ///
    /// 不用 `XCTAssertEqual`：`UIColor` 的相等會連色彩空間一起比，而插補出來的
    /// 顏色是 sRGB 分量組出來的，和系統顏色即使肉眼相同也不會相等。
    func assertSameColor(
        _ actual: UIColor?,
        _ expected: UIColor?,
        accuracy: CGFloat = 0.01,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual, let expected else {
            XCTAssertEqual(actual, expected, message, file: file, line: line)
            return
        }
        var lhs = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        var rhs = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        guard actual.getRed(&lhs.0, green: &lhs.1, blue: &lhs.2, alpha: &lhs.3),
              expected.getRed(&rhs.0, green: &rhs.1, blue: &rhs.2, alpha: &rhs.3) else {
            return XCTFail("取不到顏色分量 \(message)", file: file, line: line)
        }
        XCTAssertEqual(lhs.0, rhs.0, accuracy: accuracy, "red \(message)", file: file, line: line)
        XCTAssertEqual(lhs.1, rhs.1, accuracy: accuracy, "green \(message)", file: file, line: line)
        XCTAssertEqual(lhs.2, rhs.2, accuracy: accuracy, "blue \(message)", file: file, line: line)
        XCTAssertEqual(lhs.3, rhs.3, accuracy: accuracy, "alpha \(message)", file: file, line: line)
    }

    func isContentViewInstalled(_ tab: TeroTab, in controller: TeroTabBarController) -> Bool {
        guard let contentView = tab.viewController.viewIfLoaded else { return false }
        var candidate: UIView? = contentView.superview
        while let current = candidate {
            if current === controller.view { return true }
            candidate = current.superview
        }
        return false
    }
}
