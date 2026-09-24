import UIKit

/// 把一個 `UINavigationItem` 鏡射到 `TeroNavigationBar` 上，並以 KVO 持續同步（issue #89）。
///
/// 這**不是** `UINavigationController` 相容層：不回傳假的 `navigationBar`，不做型別硬轉。
/// 它只讓頁面照舊寫 `navigationItem.title`／`leftBarButtonItems`／`rightBarButtonItems`／
/// `titleView`，由導覽列讀出來畫。接入筆記 §4 說這是遷移裡最大的一塊，也是「既有頁面
/// 不改寫法就能上」成立的關鍵；之前每個採用者都得自己重寫一次。
///
/// 由 `TeroNavigationBar` 持有；bar 釋放時觀察一起結束。
///
/// 繼承 `NSObject` 是為了當返回鍵的 target：用 target-action 而不是 `UIAction`，
/// 與 `UIBarButtonItem` 那一側的接法一致，測試也能沿同一條路徑觸發。
internal final class TeroNavigationItemMirror: NSObject {

    private weak var bar: TeroNavigationBar?
    private let item: UINavigationItem
    private let backAction: (() -> Void)?
    private var itemObservations: [NSKeyValueObservation] = []
    private var buttonObservations: [NSKeyValueObservation] = []
    /// 每顆 `UIBarButtonItem` 對應一個 view。鍵是 item 的身分：陣列沒換的話 view 不重建，
    /// 執行期換掉某一顆時只有那一顆重建。
    private var views: [ObjectIdentifier: (item: UIBarButtonItem, view: UIView)] = [:]
    private var backButton: TeroNavigationButton?

    internal init(bar: TeroNavigationBar, item: UINavigationItem, backAction: (() -> Void)?) {
        self.bar = bar
        self.item = item
        self.backAction = backAction
        super.init()
        // 有些頁面會在執行期換按鈕、換標題，所以要一直盯著，不是綁定那一刻抄一次。
        itemObservations = [
            item.observe(\.title, options: [.new]) { [weak self] _, _ in self?.sync() },
            item.observe(\.titleView, options: [.new]) { [weak self] _, _ in self?.sync() },
            item.observe(\.leftBarButtonItems, options: [.new]) { [weak self] _, _ in self?.sync() },
            item.observe(\.rightBarButtonItems, options: [.new]) { [weak self] _, _ in self?.sync() },
            // 單數的 setter 也要看。UIKit **不會**因此補發複數 key 的 KVO（實測 0 次），
            // 而單數是最常見的寫法——只觀察複數的話，`navigationItem.leftBarButtonItem = …`
            // 之後導覽列會一直停在第一次 bind 的樣子。遷移前不會有事：`UINavigationBar`
            // 直接讀 `navigationItem`，本來就不需要 KVO。
            item.observe(\.leftBarButtonItem, options: [.new]) { [weak self] _, _ in self?.sync() },
            item.observe(\.rightBarButtonItem, options: [.new]) { [weak self] _, _ in self?.sync() },
            item.observe(\.hidesBackButton, options: [.new]) { [weak self] _, _ in self?.sync() },
            item.observe(\.leftItemsSupplementBackButton, options: [.new]) { [weak self] _, _ in self?.sync() }
        ]
        sync()
    }

    /// 把 item 現在的樣子整組寫到 bar 上。
    internal func sync() {
        guard let bar else { return }
        bar.title = item.title
        bar.titleView = item.titleView

        let leftItems = item.leftBarButtonItems ?? []
        let rightItems = item.rightBarButtonItems ?? []

        var leading: [UIView] = []
        if let back = resolvedBackButton(leftItems: leftItems, canNavigateBack: bar.canNavigateBack) {
            leading.append(back)
        }
        leading.append(contentsOf: leftItems.map(view(for:)))
        bar.leadingItems = leading
        // 反轉才對得上 UIKit：`rightBarButtonItems` 的第 0 顆貼著右緣、往左排，
        // 而 `trailingItems` 是由左往右排（`trailingStack` 是水平 stack view）。
        // 兩邊的索引語意相反，原序餵進去整排按鈕的順序就會和原生相反。
        // 實測（iPhone 17, iOS 26.5）：原生 `[A, B]` 由左到右畫成 B、A。
        //
        // `leadingItems` 不必反轉——同一次實測裡原生 left items 是同序的。
        bar.trailingItems = rightItems.reversed().map(view(for:))

        prune(keeping: leftItems + rightItems)
        observeButtons(leftItems + rightItems)
    }

    /// 合成的返回鍵：有動作可接、有上一頁可以回去、頁面沒有藏返回鍵、而且沒有自己的
    /// left items（除非它說 left items 是補在返回鍵旁邊的）。
    private func resolvedBackButton(leftItems: [UIBarButtonItem], canNavigateBack: Bool) -> TeroNavigationButton? {
        guard backAction != nil, canNavigateBack, !item.hidesBackButton,
              leftItems.isEmpty || item.leftItemsSupplementBackButton else {
            backButton = nil
            return nil
        }
        if let backButton { return backButton }
        // 預設圖示一律用 SF Symbols（ADR-0007）。
        // 材質同上：建成 `.automatic`，由導覽列統一套。
        let button = TeroNavigationButton(image: UIImage(systemName: "chevron.backward"), material: .automatic)
        button.accessibilityLabel = item.backButtonTitle
        button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton = button
        return button
    }

    @objc private func backTapped() {
        backAction?()
    }

    /// `customView` 直接沿用；其餘做成 `TeroNavigationButton`。
    private func view(for barItem: UIBarButtonItem) -> UIView {
        let key = ObjectIdentifier(barItem)
        if let cached = views[key], cached.item === barItem {
            Self.apply(barItem, to: cached.view, isOwnedByTero: barItem.customView == nil)
            return cached.view
        }
        let view: UIView
        if let custom = barItem.customView {
            Self.pinMeasuredSize(of: custom)
            view = custom
        } else {
            // 三者皆 nil 的 item 畫出來是一顆有留白、沒內容的空膠囊。
            //
            // `UIBarButtonItem(barButtonSystemItem:)` 正是這種：實測 done／cancel／add
            // 的 title、image、customView **全部是 nil**。而 `systemItem` 沒有公開的
            // getter，所以 Tero 無法把它對應回 SF Symbol 或文字——能做的只有講出來。
            if barItem.image == nil, barItem.title?.isEmpty ?? true {
                TeroDiagnostics.report(
                    "UIBarButtonItem 沒有 title、image 或 customView，鏡射只能畫出空白按鈕。"
                    + "系統型的 item（barButtonSystemItem:）就是這種——請改用明確的 title 或 image。"
                )
            }
            // 材質一律建成 `.automatic`，由 `TeroNavigationBar` 在 `rebuild` 時套上它的
            // `defaultButtonMaterial`。這裡不重複讀——變異驗過：鏡射這側拿掉之後
            // 兩條材質測試一條都沒紅，表示承重的是 bar 那一份。
            let button: TeroNavigationButton
            if let image = barItem.image {
                button = TeroNavigationButton(image: image, material: .automatic)
            } else {
                button = TeroNavigationButton(title: barItem.title, material: .automatic)
            }
            if let target = barItem.target, let action = barItem.action {
                button.addTarget(target, action: action, for: .touchUpInside)
            }
            if let primary = barItem.primaryAction {
                button.addAction(primary, for: .touchUpInside)
            }
            view = button
        }
        Self.apply(barItem, to: view, isOwnedByTero: barItem.customView == nil)
        views[key] = (barItem, view)
        return view
    }

    /// 執行期會變的屬性：每次同步都重套。
    /// - Parameter isOwnedByTero: 這個 view 是不是**這裡**建的。
    ///
    ///   `customView` 是 consumer 自己建好、自己設好內容的 view，Tero 只是把它擺上去。
    ///   先前不分來源一律重設 title／image／font／tintColor，於是 consumer 若拿
    ///   `TeroNavigationButton` 當 `customView`（想沿用玻璃材質就會這樣做），
    ///   `UIBarButtonItem(customView:)` 的 `title` 是 nil，一句
    ///   `setTitle(nil, for: .normal)` 就把**文字整個清空**，只留一個空膠囊；
    ///   `tintColor` 同樣被 nil 覆蓋掉。某個接入專案有四個呼叫點中彈。
    ///
    ///   所以外來的 view 只套 Tero 真正該管的：能不能點、無障礙識別、以及停用時的外觀。
    /// 套用 item 自己的 `titleTextAttributes`。
    ///
    /// 靠 `setTitleTextAttributes(_:for:)` 設按鈕文字外觀的頁面很多，先前完全被忽略
    /// ——字型固定依 `style` 決定、顏色走導覽列的預設，接上 Tero 之後那些頁的外觀會跑掉。
    ///
    /// **逐 item 的設定贏過 bar 層級的 `buttonTitleColor`**，與「呼叫端自己 `setTitleColor`
    /// 過就不覆蓋」同一個原則：specific 的贏過預設。這裡走公開的 `setTitleColor`
    /// 而不是內部的 `applyDefaultTitleColor`，正是為了讓按鈕把自己標記成「顏色已被指定」。
    private static func applyTitleTextAttributes(of barItem: UIBarButtonItem, to button: TeroNavigationButton) {
        for state in [UIControl.State.normal, .disabled] {
            guard let attributes = barItem.titleTextAttributes(for: state) else { continue }
            if let color = attributes[.foregroundColor] as? UIColor {
                button.setTitleColor(color, for: state)
            }
            // 字型只有 `.normal` 有意義——UIButton 的 titleLabel 只有一份字型。
            if state == .normal, let font = attributes[.font] as? UIFont {
                button.titleLabel?.font = font
            }
        }
    }

    /// frame-based 的 `customView` 要把量好的尺寸釘上去。
    ///
    /// `leadingItems` / `trailingItems` 是水平 `UIStackView`，而 stack view 會把
    /// 加進去的 view 轉成 Auto Layout。沒有約束、只有 frame 的 view 因此**塌成 0×0**
    /// （實測 120×32 → 0×0）——在 `UINavigationBar` 底下那是完全合法的寫法，
    /// `initWithCustomView:` 一個 frame-based view 本來就能用。
    ///
    /// 這與 `TeroNavigationBar.titleView` 是同一個問題，但處理方式刻意不同：`titleView`
    /// 是呼叫端直接交給 Tero 的，文件明說尺寸是設定值不是量測值，呼叫端自己釘得到；
    /// 而這裡的 view 是交給 `UIBarButtonItem` 的，呼叫端從沒同意過 Tero 的契約，是鏡射
    /// 把它搬進 Auto Layout 的世界。**座標轉換是相容層的責任**，與反轉右側按鈕順序同一個道理。
    ///
    /// 兩條約束都用 `.defaultHigh`：窄螢幕上寧可讓它縮，也不要變成不可滿足的約束。
    /// 已經走 Auto Layout 的 view 不動——那是呼叫端自己安排好的。
    private static func pinMeasuredSize(of view: UIView) {
        guard view.translatesAutoresizingMaskIntoConstraints else { return }
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        view.translatesAutoresizingMaskIntoConstraints = false
        let width = view.widthAnchor.constraint(equalToConstant: size.width)
        let height = view.heightAnchor.constraint(equalToConstant: size.height)
        width.priority = .defaultHigh
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([width, height])
    }

    private static func apply(_ barItem: UIBarButtonItem, to view: UIView, isOwnedByTero: Bool) {
        view.isUserInteractionEnabled = barItem.isEnabled
        view.accessibilityIdentifier = barItem.accessibilityIdentifier
        guard let button = view as? TeroNavigationButton, isOwnedByTero else {
            view.alpha = barItem.isEnabled ? 1 : 0.35
            (view as? UIControl)?.isEnabled = barItem.isEnabled
            return
        }
        button.isEnabled = barItem.isEnabled
        button.tintColor = barItem.tintColor
        button.menu = barItem.menu
        button.showsMenuAsPrimaryAction = (barItem.menu != nil && barItem.primaryAction == nil
                                           && barItem.action == nil)
        if barItem.image != nil {
            button.setImage(barItem.image, for: .normal)
        } else {
            button.setTitle(barItem.title, for: .normal)
            // 比照 UIKit：Plain 是 17pt regular、Done 是 17pt semibold。接入筆記記過寫死
            // 16pt 不分樣式的後果——整條導覽列的文字都小一號。
            button.titleLabel?.font = barItem.style == .done
                ? .systemFont(ofSize: 17, weight: .semibold)
                : .systemFont(ofSize: 17)
            applyTitleTextAttributes(of: barItem, to: button)
        }
        button.accessibilityLabel = barItem.accessibilityLabel ?? barItem.title
    }

    private func prune(keeping items: [UIBarButtonItem]) {
        let live = Set(items.map(ObjectIdentifier.init))
        views = views.filter { live.contains($0.key) }
    }

    private func observeButtons(_ items: [UIBarButtonItem]) {
        buttonObservations = items.flatMap { barItem -> [NSKeyValueObservation] in
            [
                barItem.observe(\.isEnabled, options: [.new]) { [weak self] _, _ in self?.sync() },
                barItem.observe(\.title, options: [.new]) { [weak self] _, _ in self?.sync() },
                barItem.observe(\.image, options: [.new]) { [weak self] _, _ in self?.sync() },
                barItem.observe(\.tintColor, options: [.new]) { [weak self] _, _ in self?.sync() }
            ]
        }
    }
}
