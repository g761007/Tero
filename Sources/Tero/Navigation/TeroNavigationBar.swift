import UIKit

/// 導覽按鈕的材質。
///
/// 正字沿用 `TeroTabSelectionIndicatorMaterial`：Material 決定「這一個怎麼畫」，
/// 與 Style（版面）分開。計畫書 §21 寫的是 Appearance，但那個詞在 `CONTEXT.md` 被
/// Material 詞條列為 _Avoid_。
@objc public enum TeroNavigationButtonMaterial: Int {
    /// 純色，沒有背景。
    case plain
    /// iOS 26 的玻璃；以下的系統一律降級為 plain（ADR-0002）。
    case glass
    /// 跟隨所在階層最近的 `TeroTabBarController` 的 effective style：FloatingGlass 時等同
    /// `.glass`，其餘等同 `.plain`；不在任何 Tero Tab 容器之下時等同 `.plain`。
    ///
    /// 這讓「要不要 Liquid Glass」回到一個旗標——`configuration.style`——而不必每顆按鈕
    /// 各自指定（接入筆記 §1 那個「材質跟隨 style」的開關，現在住在套件裡）。
    /// 依 responder chain 解析，在進入視窗時重解析；Style 不支援執行期切換（ADR-0003），
    /// 所以之後不必再算。
    ///
    /// 排在最後是刻意的：插在前面會改掉既有 case 的 raw value。
    case automatic
}

/// 導覽列上的按鈕。
public final class TeroNavigationButton: UIButton {

    @objc public var material: TeroNavigationButtonMaterial = .plain {
        didSet { applyMaterial() }
    }

    private var glassBackdrop: UIVisualEffectView?

    @objc public convenience init(image: UIImage?, material: TeroNavigationButtonMaterial = .plain) {
        self.init(frame: .zero)
        setImage(image, for: .normal)
        self.material = material
        applyMaterial()
    }

    @objc public convenience init(title: String?, material: TeroNavigationButtonMaterial = .plain) {
        self.init(frame: .zero)
        setTitle(title, for: .normal)
        applyDefaultTitleColor(nil)
        self.material = material
        applyMaterial()
    }

    /// 呼叫端自己設過 title color 之後，導覽列的 `buttonTitleColor` 就不再覆蓋它。
    ///
    /// 沒有這個判斷的話，導覽列會把呼叫端指定的顏色蓋掉——那正是 `customView` 被清空
    /// 那個缺陷的同一個形狀，不要再犯一次。
    private var usesOwnTitleColor = false

    public override func setTitleColor(_ color: UIColor?, for state: UIControl.State) {
        super.setTitleColor(color, for: state)
        usesOwnTitleColor = true
    }

    /// 套用導覽列的預設色。`nil` 表示沒有指定，用系統的 `.label`。
    ///
    /// 停用色跟著走：導覽列若是深色底，寫死的 `.tertiaryLabel` 一樣看不見。
    internal func applyDefaultTitleColor(_ color: UIColor?) {
        // `color` 是 nil（導覽列沒有指定）時也一樣不覆蓋——「沒有偏好」不等於
        // 「請改回 .label」。走 `super` 才不會把自己標記成呼叫端設的。
        guard !usesOwnTitleColor else { return }
        super.setTitleColor(color ?? .label, for: .normal)
        // 停用時要看得出來。`.custom` 型的 UIButton 只設 `.normal` 的話，`isEnabled = false`
        // 完全沒有視覺變化——點不下去，但看起來是可以點的。原生 `UIBarButtonItem` 會變淡。
        super.setTitleColor(color?.withAlphaComponent(0.35) ?? .tertiaryLabel, for: .disabled)
    }

    /// 文字按鈕的左右留白。
    private static let titleHorizontalPadding: CGFloat = 14
    /// 文字按鈕的最小高度。
    private static let titleMinimumHeight: CGFloat = 36

    /// 文字按鈕要有留白與最小高度。
    ///
    /// 沒有的話 intrinsic size 就是文字本身的大小，而玻璃底又 round 到 `bounds.height / 2`
    /// ——膠囊貼著字緣、高度只有一行字高（17pt 字約 21pt）。同一條列上帶尺寸的圖示按鈕
    /// 是 44pt 的圓，兩者放在一起不是一套。由 `UIBarButtonItem` 鏡射來的文字按鈕全是這種，
    /// 因為呼叫端沒有機會釘尺寸。
    ///
    /// 走 intrinsic size 而不是釘 constraint 是刻意的：標題會在執行期換（鏡射以 KVO 重設
    /// 標題），釘死的寬度會停在舊字串上。呼叫端自己釘了尺寸的按鈕不受影響——required
    /// 的 constraint 蓋過 intrinsic size。
    public override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        guard image(for: .normal) == nil, currentTitle?.isEmpty == false else { return size }
        size.width += Self.titleHorizontalPadding * 2
        size.height = max(size.height, Self.titleMinimumHeight)
        return size
    }

    /// `.automatic` 的解析結果；其餘原封回傳。
    ///
    /// 沿 responder chain 往上找：chrome view → chrome 容器 → `TeroNavigationContainer` →
    /// 它的 view 的上層 → `TeroTabBarController`。找不到就是單獨使用，等同 `.plain`。
    private var resolvedMaterial: TeroNavigationButtonMaterial {
        guard material == .automatic else { return material }
        var responder: UIResponder? = next
        while let current = responder {
            if let tabController = current as? TeroTabBarController {
                return tabController.tabBarStyle == .floatingGlass ? .glass : .plain
            }
            responder = current.next
        }
        return .plain
    }

    /// `.automatic` 要等進了視窗、responder chain 完整之後才解析得出來。
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if material == .automatic, window != nil { applyMaterial() }
    }

    private func applyMaterial() {
        glassBackdrop?.removeFromSuperview()
        glassBackdrop = nil

        guard resolvedMaterial == .glass, #available(iOS 26, *), !TeroAccessibility.isReduceTransparencyEnabled() else {
            backgroundColor = .clear
            return
        }
        let effectView = UIVisualEffectView(effect: UIGlassEffect())
        effectView.isUserInteractionEnabled = false
        effectView.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(effectView, at: 0)
        NSLayoutConstraint.activate([
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        glassBackdrop = effectView
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // 玻璃底必須壓回最底層。`insertSubview(at: 0)` 是在 `imageView` 還不存在時做的，
        // UIButton 之後才惰性建立它並插進 index 0——底就這樣被頂到圖示上面，圖示變成
        // 玻璃裡的折射而不是圖形（實測按鈕內最暗像素 235/255，等於看不見）。
        if let glassBackdrop, subviews.first !== glassBackdrop {
            sendSubviewToBack(glassBackdrop)
        }
        glassBackdrop?.layer.cornerRadius = bounds.height / 2
        glassBackdrop?.clipsToBounds = true
    }
}

/// 預設的導覽列。**Consumer 可以完全不用**——`TeroNavigationChromeProviding` 只要求一個
/// `UIView`，這個型別只是其中一種現成答案。
///
/// 它的底預設是 `UIBlurEffect`：內容從導覽列下方捲過去時看得到模糊，iOS 26 的 scroll edge
/// effect 也才有空間做事。「降低透明度」開啟時換成實色。
///
/// Primary（標題與按鈕）與 Secondary（Stories、分段、篩選）兩個區域是**這個型別內部的
/// 結構**，不是容器契約的一部分。容器只認得「一個 view ＋ 一條收合進度」，因此換掉這個
/// 導覽列不需要動 Tero 的任何 API——那正是計畫書 §57 說的 primitives 邊界。
public final class TeroNavigationBar: UIView {

    /// Primary 區域的標題。
    @objc public var title: String? {
        didSet { titleLabel.text = title }
    }

    /// Primary 區域標題的顏色。`nil` 沿用 `.label`。
    ///
    /// `tintColor` 管不到 `UILabel.textColor`，所以沒有這個屬性的話，深色或彩色底的
    /// 導覽列上標題等於消失，而且從外面無法補救。
    @objc public var titleColor: UIColor? {
        didSet { titleLabel.textColor = titleColor ?? .label }
    }

    /// Primary 區域標題的字型。`nil` 沿用 `.headline`。
    ///
    /// **指定字型等於退出 Dynamic Type**（ADR-0006 的「部分跟隨」邊界）：這個屬性的用途
    /// 是照抄既有設計的固定尺寸，替它偷偷縮放就不是照抄了。兩者都要的話自己包一層：
    ///
    /// ```swift
    /// bar.titleFont = UIFontMetrics(forTextStyle: .headline)
    ///     .scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
    /// ```
    @objc public var titleFont: UIFont? {
        didSet {
            titleLabel.font = titleFont ?? .preferredFont(forTextStyle: .headline)
            titleLabel.adjustsFontForContentSizeCategory = (titleFont == nil)
        }
    }

    /// Primary 區域的自訂標題視圖。設了之後取代文字標題。
    ///
    /// `leadingItems`、`trailingItems`、`secondaryView` 本來就收任意 view，標題是唯一
    /// 只收文字的槽——這個不一致讓用 `UINavigationItem.titleView` 的頁面整個標題不見。
    ///
    /// **這個 view 要自己說得出尺寸**：Tero 不會呼叫 `sizeThatFits(_:)` 也不讀
    /// `intrinsicContentSize`（B18：尺寸是設定值不是量測值）。沒有 intrinsic size 的
    /// view（例如直接寫 `frame` 的自繪 label）請自己釘上寬高約束，並把水平壓縮阻力調低，
    /// 免得和「讓開兩側控制項」那兩條打架。
    @objc public var titleView: UIView? {
        didSet {
            guard titleView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            titleLabel.isHidden = (titleView != nil)
            guard let titleView else { return }
            titleView.translatesAutoresizingMaskIntoConstraints = false
            primaryRow.addSubview(titleView)
            // 與文字標題同一組規則：置中可讓步，但一定讓開兩側控制項。
            let centerX = titleView.centerXAnchor.constraint(equalTo: primaryRow.centerXAnchor)
            centerX.priority = .defaultHigh
            NSLayoutConstraint.activate([
                centerX,
                titleView.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
                titleView.leadingAnchor.constraint(
                    greaterThanOrEqualTo: leadingStack.trailingAnchor, constant: 8),
                titleView.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8)
            ])
        }
    }

    /// 鏡射建立按鈕時採用的材質。預設 `.automatic`（跟著 Tab Bar 的 style 走）。
    ///
    /// 由 `UIBarButtonItem` 鏡射來的按鈕呼叫端拿不到，所以沒有這個屬性的話，
    /// 「floatingGlass 的 Tab Bar 配樸素導覽鍵」這個組合表達不出來。
    ///
    /// 設定當下會套用到**目前還是 `.automatic`** 的按鈕；你自己指定過材質的那些不動。
    /// 注意這個判斷是看當下的值，所以把它改回 `.automatic` 不會把先前改過的按鈕還原。
    @objc public var defaultButtonMaterial: TeroNavigationButtonMaterial = .automatic {
        didSet { applyDefaultButtonMaterial() }
    }

    private func applyDefaultButtonMaterial() {
        for view in leadingItems + trailingItems {
            guard let button = view as? TeroNavigationButton, button.material == .automatic else { continue }
            button.material = defaultButtonMaterial
        }
    }

    /// 文字按鈕的顏色。`nil` 沿用 `.label`。
    ///
    /// `tintColor` 對 `UIButton` 的文字不生效，所以沒有這個屬性的話，深色或彩色底的
    /// 導覽列**沒有任何辦法**把文字按鈕染成淺色——由 `UIBarButtonItem` 鏡射來的按鈕
    /// 尤其如此，呼叫端根本拿不到那顆按鈕。（圖示按鈕走 `tintColor`，不受這個屬性影響。）
    ///
    /// 呼叫端自己對某顆按鈕設過 `setTitleColor` 的話，這裡不會覆蓋它。
    @objc public var buttonTitleColor: UIColor? {
        didSet { applyButtonTitleColor() }
    }

    /// 要不要畫內建的底。預設 `true`。
    ///
    /// 關掉之後這個導覽列完全透明，底由你自己負責——例如依捲動進度淡入一層。
    /// 契約本來就允許半透明的 chrome（見 `TeroNavigationChromeProviding`），
    /// 但沒有這個開關的話內建的底關不掉：它排在最底層，設 `backgroundColor` 只會被蓋住。
    @objc public var showsBackdrop: Bool = true {
        didSet { backdrop.isHidden = !showsBackdrop }
    }

    /// Primary 區域，leading 側的控制項。
    @objc public var leadingItems: [UIView] = [] {
        didSet { rebuild(stack: leadingStack, with: leadingItems) }
    }

    /// Primary 區域，trailing 側的控制項。
    @objc public var trailingItems: [UIView] = [] {
        didSet { rebuild(stack: trailingStack, with: trailingItems) }
    }

    /// Secondary 區域。nil 表示這個導覽列只有 Primary（§23：Secondary optional）。
    @objc public var secondaryView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            guard let secondaryView else { return }
            secondaryView.translatesAutoresizingMaskIntoConstraints = false
            secondaryContainer.addSubview(secondaryView)
            NSLayoutConstraint.activate([
                secondaryView.topAnchor.constraint(equalTo: secondaryContainer.topAnchor),
                secondaryView.bottomAnchor.constraint(equalTo: secondaryContainer.bottomAnchor),
                secondaryView.leadingAnchor.constraint(equalTo: secondaryContainer.leadingAnchor),
                secondaryView.trailingAnchor.constraint(equalTo: secondaryContainer.trailingAnchor)
            ])
        }
    }

    /// Primary 那一列的高度。收合時 Secondary 讓上來的就是這個值。
    ///
    /// 公開是因為契約要求**頁面**宣告 `teroNavigationChromeHeight`（B18：高度是設定值
    /// 不是量測值），而這個數字只有導覽列知道。不公開的話，每個採用者都只能從 Demo
    /// 抄一個 44 出來，將來調整就會全部對不上。
    @objc public static let primaryHeight: CGFloat = 44

    private var secondaryTopConstraint: NSLayoutConstraint?
    private var navigationItemMirror: TeroNavigationItemMirror?
    private let titleLabel = UILabel()

    /// 鏡射一個 `UINavigationItem`（issue #89）。
    ///
    /// 頁面照舊寫 `navigationItem.title`／`titleView`／`leftBarButtonItems`／`rightBarButtonItems`／
    /// `hidesBackButton`，這裡讀出來畫，之後以 KVO 持續同步——執行期換按鈕、換標題都會跟上。
    /// `UIBarButtonItem` 變成 `TeroNavigationButton`（`.automatic` 材質；Plain 17pt regular、
    /// Done 17pt semibold），`customView` 直接沿用。
    ///
    /// `backAction` 非 nil、有上一頁可以回去、頁面沒有 `hidesBackButton`、也沒有自己的
    /// left items 時合成一顆返回鍵。「有沒有上一頁」在容器裡由容器判斷，root 沒有返回鍵，
    /// 所以每一頁都可以照傳同一個 `backAction`。返回動作由呼叫端提供，chrome view 因此
    /// 不必反向引用容器（ADR-0013）。
    ///
    /// 再呼叫一次換對象；傳 nil 解除，bar 停在最後一次同步的樣子。
    ///
    /// 這**不是** `UINavigationController` 相容層：沒有假的 `navigationBar`、沒有型別硬轉，
    /// README「從 UINavigationController 遷移」不做相容層的理由不受影響。它收回的是接入筆記
    /// §4 那一塊——每個採用者原本都得自己重寫一次的鏡射。
    @objc(bindToNavigationItem:backAction:)
    public func bind(to navigationItem: UINavigationItem?, backAction: (() -> Void)?) {
        guard let navigationItem else {
            navigationItemMirror = nil
            return
        }
        navigationItemMirror = TeroNavigationItemMirror(bar: self, item: navigationItem, backAction: backAction)
    }

    /// 所在的容器說這一頁有沒有上一頁可以回去；鏡射據此決定要不要合成返回鍵。
    ///
    /// 這個答案只有容器知道，而且要等 stack 提交之後才對：chrome 在提交之前就建立了，
    /// 頁面在那一刻判斷不出自己會不會是 root。所以由容器在每次 stack 變更後寫進來。
    /// 不在任何容器裡的 bar 維持 `true`，與先前相同。
    internal var canNavigateBack = true {
        didSet {
            guard canNavigateBack != oldValue else { return }
            navigationItemMirror?.sync()
        }
    }
    private let backdrop = UIVisualEffectView(effect: nil)
    private var reduceTransparencyObserver: NSObjectProtocol?

    /// 半透明而不是實色：內容從導覽列底下捲過去時要看得到模糊。
    ///
    /// 這和底部 Tab Bar 的 Classic 是同一套處置——預設模糊，「降低透明度」開啟時才換成
    /// 不透明。iOS 26 上系統的 scroll edge effect 再疊在這之上，由容器接上追蹤對象。
    private func applyBackdrop() {
        if TeroAccessibility.isReduceTransparencyEnabled() {
            backdrop.effect = nil
            backdrop.contentView.backgroundColor = .systemBackground
        } else {
            backdrop.effect = UIBlurEffect(style: .systemChromeMaterial)
            backdrop.contentView.backgroundColor = .clear
        }
    }

    private func observeReduceTransparency() {
        reduceTransparencyObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.applyBackdrop() }
    }

    deinit {
        if let reduceTransparencyObserver {
            NotificationCenter.default.removeObserver(reduceTransparencyObserver)
        }
    }

    private let leadingStack = UIStackView()
    private let trailingStack = UIStackView()
    private let primaryRow = UIView()
    private let secondaryContainer = UIView()

    @objc public override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("TeroNavigationBar 不支援 Storyboard 與 XIB，請改用程式化初始化")
    }

    /// 由畫面在 `updateTeroNavigationChrome(_:collapseProgress:)` 裡轉發進來。
    ///
    /// 這個導覽列的收合方式是「Primary 淡出並上移，Secondary 留下」——也就是 §24 的
    /// `hidePrimary`。要別種收合方式，寫自己的 chrome view，不必改 Tero。
    @objc public func applyCollapseProgress(_ progress: CGFloat) {
        let clamped = min(max(progress, 0), 1)
        primaryRow.alpha = 1 - clamped
        primaryRow.transform = CGAffineTransform(translationX: 0, y: -Self.primaryHeight * clamped * 0.5)
        // Secondary 遞補 Primary 讓出的高度，而且是走 constraint 不是 transform。
        //
        // transform 只移動畫面、不改 Auto Layout 的 frame：Secondary 的高度仍然是
        // 「導覽列高 − 安全區 − 44」，收合到底就被壓成 0 或負數。它裡面的 view 四邊
        // 釘在容器上，於是靠 UIKit 打斷 constraint 才畫得出來——看起來對，實際是壞的。
        // 用 constraint 讓開，收合後 Secondary 拿到的正好是宣告的收合高度。
        secondaryTopConstraint?.constant = Self.primaryHeight * (1 - clamped)
    }

    private func build() {
        backgroundColor = .clear
        backdrop.isUserInteractionEnabled = false
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(backdrop, at: 0)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        applyBackdrop()
        observeReduceTransparency()
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        // 標題肯被壓縮。不設的話，兩側控制項一寬，Auto Layout 會挑控制項的寬度下手。
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for stack in [leadingStack, trailingStack] {
            stack.axis = .horizontal
            stack.spacing = 8
            stack.alignment = .center
        }

        for subview in [primaryRow, secondaryContainer] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        for subview in [leadingStack, titleLabel, trailingStack] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            primaryRow.addSubview(subview)
        }

        // 置中必須可以讓步。三條都是必要優先權的話，只要 leading 控制項寬過 Primary 列的
        // 一半，這組就無解：空標題被釘在中心，卻同時被要求站到控制項右邊 8pt 之外。
        // Auto Layout 只能打斷一條，而它打斷的是控制項自己的寬度——**標題縮到 0 也救不了**，
        // 置中把它的位置釘死了。
        let titleCenterX = titleLabel.centerXAnchor.constraint(equalTo: primaryRow.centerXAnchor)
        titleCenterX.priority = .defaultHigh
        titleCenterX.isActive = true

        let secondaryTop = secondaryContainer.topAnchor.constraint(
            equalTo: safeAreaLayoutGuide.topAnchor, constant: Self.primaryHeight
        )
        secondaryTopConstraint = secondaryTop

        NSLayoutConstraint.activate([
            primaryRow.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            primaryRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            primaryRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            primaryRow.heightAnchor.constraint(equalToConstant: Self.primaryHeight),

            leadingStack.leadingAnchor.constraint(equalTo: primaryRow.leadingAnchor),
            leadingStack.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
            trailingStack.trailingAnchor.constraint(equalTo: primaryRow.trailingAnchor),
            trailingStack.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: primaryRow.centerYAnchor),
            // 標題讓開兩側的控制項。少了這兩條，長標題會蓋住返回鍵、被右側按鈕蓋住，
            // 而且不截斷也不被裁掉——多出來的部分直接畫到 Primary 列之外。
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingStack.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -8),

            secondaryTop,
            secondaryContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            secondaryContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            secondaryContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func rebuild(stack: UIStackView, with items: [UIView]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        items.forEach { stack.addArrangedSubview($0) }
        // 換過 items 之後也要套一次，否則只有設定屬性的那一刻在場的按鈕吃得到。
        applyButtonTitleColor()
        applyDefaultButtonMaterial()
    }

    private func applyButtonTitleColor() {
        for view in leadingItems + trailingItems {
            (view as? TeroNavigationButton)?.applyDefaultTitleColor(buttonTitleColor)
        }
    }
}
