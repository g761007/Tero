import XCTest
import UIKit
@testable import Tero

/// issue #89：`TeroNavigationBar` 鏡射 `UINavigationItem`。
final class NavigationItemMirrorTests: TeroTabBarControllerTestCase {

    private final class ActionRecorder: NSObject {
        var count = 0
        @objc func fire() { count += 1 }
    }

    private func makeBar() -> TeroNavigationBar {
        let bar = TeroNavigationBar(frame: CGRect(x: 0, y: 0, width: 390, height: 44))
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.addSubview(bar)
        return bar
    }

    private func titleLabel(in bar: TeroNavigationBar) throws -> UILabel {
        try XCTUnwrap(bar.subviews.flatMap(\.subviews).compactMap { $0 as? UILabel }.first)
    }

    private func invokeTouchUpInside(on control: UIControl) {
        for target in control.allTargets {
            for action in control.actions(forTarget: target, forControlEvent: .touchUpInside) ?? [] {
                _ = (target as AnyObject).perform(Selector(action), with: control)
            }
        }
    }

    /// 畫面上由左到右的順序，用位置讀而不是讀陣列——使用者看到的是位置。
    private func onScreenTitles(_ views: [UIView]) -> [String] {
        views.compactMap { view -> (String, CGFloat)? in
            guard let title = (view as? UIButton)?.currentTitle else { return nil }
            return (title, view.frame.minX)
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    /// 換標題之後量出來的寬度要跟著變。
    ///
    /// 鏡射會在執行期換標題（KVO 盯著），留白既然走 intrinsic size，就得確認換完會重量。
    /// 這裡刻意**不**手動呼叫 `invalidateIntrinsicContentSize()`，量的是 UIKit 自己
    /// 在 `setTitle(_:for:)` 之後有沒有失效重查——接入方指出那應該本來就會發生。
    func test_changingTheTitleRemeasuresTheButton() {
        let button = TeroNavigationButton(title: "A", material: .plain)
        let narrow = button.intrinsicContentSize.width

        button.setTitle("AAAAAAAAAAAAAAA", for: .normal)

        XCTAssertGreaterThan(button.intrinsicContentSize.width, narrow,
                             "UIKit 應該在 setTitle 之後自己失效重查")
    }

    /// 換**字型**之後也要重量——鏡射除了標題也會改 `titleLabel.font`。
    func test_changingTheFontRemeasuresTheButton() {
        let button = TeroNavigationButton(title: "AAAAA", material: .plain)
        let small = button.intrinsicContentSize.width

        button.titleLabel?.font = .systemFont(ofSize: 40, weight: .bold)

        XCTAssertGreaterThan(button.intrinsicContentSize.width, small,
                             "改字型之後量出來的寬度要變大")
    }

    // MARK: - 材質、空白按鈕、titleTextAttributes

    /// 鏡射建的按鈕呼叫端拿不到，所以「floatingGlass 的 Bar 配樸素導覽鍵」必須有地方表達。
    func test_theBarsDefaultMaterialReachesMirroredButtons() throws {
        let bar = makeBar()
        bar.defaultButtonMaterial = .plain
        let item = UINavigationItem(title: "Chat")
        item.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)

        bar.bind(to: item, backAction: nil)

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.material, .plain)
    }

    /// 設定的時機不該有差別——已經在場的按鈕也要跟上。
    func test_settingTheMaterialAfterBindingUpdatesExistingButtons() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Chat")
        item.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)
        bar.bind(to: item, backAction: nil)

        bar.defaultButtonMaterial = .glass

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.material, .glass)
    }

    /// 呼叫端自己指定過材質的按鈕不被覆蓋——與 `buttonTitleColor` 同一個原則。
    func test_aButtonWithItsOwnMaterialIsNotOverridden() {
        let bar = makeBar()
        let mine = TeroNavigationButton(title: "Mine", material: .plain)
        bar.trailingItems = [mine]

        bar.defaultButtonMaterial = .glass

        XCTAssertEqual(mine.material, .plain)
    }

    /// 三者皆 nil 的 item 只畫得出空膠囊，要講出來。
    ///
    /// `UIBarButtonItem(barButtonSystemItem:)` 正是這種——實測 done／cancel／add 的
    /// title、image、customView 全部是 nil，而 `systemItem` 沒有公開 getter，
    /// Tero 對應不回去，能做的只有診斷。
    func test_anEmptyBarButtonItemReportsADiagnostic() {
        var reported: [String] = []
        // tearDown 會還原 reportHandler，這裡不必自己收。
        TeroDiagnostics.reportHandler = { message, _, _ in reported.append(message) }

        let bar = makeBar()
        let item = UINavigationItem(title: "Chat")
        item.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: nil, action: nil)

        bar.bind(to: item, backAction: nil)

        XCTAssertTrue(reported.contains { $0.contains("空白按鈕") },
                      "系統型 item 畫不出內容，必須有診斷；實際收到：\(reported)")
    }

    /// 有內容的 item 不該吼。
    func test_anOrdinaryBarButtonItemReportsNothing() {
        var reported: [String] = []
        // tearDown 會還原 reportHandler，這裡不必自己收。
        TeroDiagnostics.reportHandler = { message, _, _ in reported.append(message) }

        let bar = makeBar()
        let item = UINavigationItem(title: "Chat")
        item.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)

        bar.bind(to: item, backAction: nil)

        XCTAssertTrue(reported.isEmpty, "有 title 的 item 不該有診斷：\(reported)")
    }

    /// item 自己設的文字樣式要套用——靠它設按鈕外觀的既有頁面很多。
    func test_titleTextAttributesAreApplied() throws {
        let bar = makeBar()
        let font = UIFont.systemFont(ofSize: 22, weight: .heavy)
        let barItem = UIBarButtonItem(title: "Next", style: .plain, target: nil, action: nil)
        barItem.setTitleTextAttributes([.foregroundColor: UIColor.systemGreen, .font: font], for: .normal)
        barItem.setTitleTextAttributes([.foregroundColor: UIColor.systemRed], for: .disabled)

        let item = UINavigationItem(title: "Chat")
        item.rightBarButtonItem = barItem
        bar.bind(to: item, backAction: nil)

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.titleColor(for: .normal), .systemGreen)
        XCTAssertEqual(button.titleColor(for: .disabled), .systemRed)
        XCTAssertEqual(button.titleLabel?.font, font, "字型也要跟著，不能只吃 style 決定的 17pt")
    }

    /// 逐 item 的設定贏過 bar 層級的預設。
    func test_titleTextAttributesWinOverTheBarsButtonTitleColor() throws {
        let bar = makeBar()
        bar.buttonTitleColor = .systemYellow
        let barItem = UIBarButtonItem(title: "Next", style: .plain, target: nil, action: nil)
        barItem.setTitleTextAttributes([.foregroundColor: UIColor.systemGreen], for: .normal)

        let item = UINavigationItem(title: "Chat")
        item.rightBarButtonItem = barItem
        bar.bind(to: item, backAction: nil)

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.titleColor(for: .normal), .systemGreen,
                       "specific 的贏過預設")
    }

    // MARK: - 文字按鈕的顏色

    /// 深色底的導覽列要有辦法把文字按鈕染成淺色。
    ///
    /// `tintColor` 對 `UIButton` 的文字不生效，而鏡射建的按鈕呼叫端根本拿不到
    /// ——沒有這個屬性的話就完全沒有出路。某個接入專案最後是在 chrome view 上翻
    /// `overrideUserInterfaceStyle` 繞過的。
    func test_theBarCanColourMirroredTitleButtons() throws {
        let bar = makeBar()
        bar.buttonTitleColor = .systemYellow
        let item = UINavigationItem(title: "Edit")
        item.rightBarButtonItem = UIBarButtonItem(title: "Next", style: .plain, target: nil, action: nil)

        bar.bind(to: item, backAction: nil)
        bar.layoutIfNeeded()

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.titleColor(for: .normal), .systemYellow)
        XCTAssertNotEqual(button.titleColor(for: .disabled), button.titleColor(for: .normal),
                          "停用色要跟著走，否則深色底上寫死的 tertiaryLabel 一樣看不見")
    }

    /// 設定的時機不該有差別——按鈕已經在場時也要套上。
    func test_settingTheColourAfterTheItemsAreInPlaceStillApplies() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Edit")
        item.rightBarButtonItem = UIBarButtonItem(title: "Next", style: .plain, target: nil, action: nil)
        bar.bind(to: item, backAction: nil)

        bar.buttonTitleColor = .systemYellow

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.titleColor(for: .normal), .systemYellow)
    }

    /// 呼叫端自己設過顏色的按鈕不可以被蓋掉——那是 customView 被清空的同一個形狀。
    func test_aButtonWithItsOwnColourIsNotOverridden() {
        let bar = makeBar()
        let mine = TeroNavigationButton(title: "Mine", material: .plain)
        mine.setTitleColor(.systemGreen, for: .normal)

        bar.trailingItems = [mine]
        bar.buttonTitleColor = .systemYellow

        XCTAssertEqual(mine.titleColor(for: .normal), .systemGreen)
    }

    /// 把顏色收回 nil 要回到預設，而不是留著上一個顏色。
    func test_clearingTheColourReturnsToTheDefault() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Edit")
        item.rightBarButtonItem = UIBarButtonItem(title: "Next", style: .plain, target: nil, action: nil)
        bar.bind(to: item, backAction: nil)
        bar.buttonTitleColor = .systemYellow

        bar.buttonTitleColor = nil

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.titleColor(for: .normal), .label)
    }

    // MARK: - 單數的 bar button item setter

    /// 為什麼必須同時觀察單數 key：UIKit **不會**在單數 setter 上補發複數 key 的 KVO。
    ///
    /// 這是實測結果，不是推論。哪天 UIKit 改了行為，這條會轉紅，屆時單數觀察就可以拿掉。
    func test_theSingularSetterDoesNotFirePluralKVO() {
        let item = UINavigationItem(title: "Probe")
        var pluralLeft = 0, pluralRight = 0
        let observations = [
            item.observe(\.leftBarButtonItems, options: [.new]) { _, _ in pluralLeft += 1 },
            item.observe(\.rightBarButtonItems, options: [.new]) { _, _ in pluralRight += 1 }
        ]
        defer { observations.forEach { $0.invalidate() } }

        item.leftBarButtonItem = UIBarButtonItem(title: "L", style: .plain, target: nil, action: nil)
        item.rightBarButtonItem = UIBarButtonItem(title: "R", style: .plain, target: nil, action: nil)

        XCTAssertEqual(pluralLeft, 0, "複數 key 沒收到通知，所以單數 key 必須自己觀察")
        XCTAssertEqual(pluralRight, 0)
    }

    /// 綁定之後才設單數 setter 也要同步。
    ///
    /// 單數是最常見的寫法，而只有「第一次版面之後才改 bar item」的頁面會中——所以不是
    /// 每頁都炸，反而更難發現。接入方是靠「右鍵用複數一路正常、左鍵用單數永遠不動」
    /// 這個不對稱找出來的。
    func test_settingASingularBarButtonItemAfterBindingSyncs() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Chat")
        bar.bind(to: item, backAction: nil)
        XCTAssertTrue(bar.leadingItems.isEmpty, "前置條件：一開始沒有左鍵")

        item.leftBarButtonItem = UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)

        let button = try XCTUnwrap(bar.leadingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.currentTitle, "Back")
    }

    /// 單數的右鍵同樣。
    func test_settingASingularRightBarButtonItemAfterBindingSyncs() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Chat")
        bar.bind(to: item, backAction: nil)

        item.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertEqual(button.currentTitle, "Done")
    }

    /// frame-based 的 `customView` 不可以塌掉。
    ///
    /// stack view 會把加進去的 view 轉成 Auto Layout，只有 frame 的 view 因此變成
    /// 0×0（實測 120×32 → 0×0）。而 `initWithCustomView:` 一個 frame-based view
    /// 在 `UINavigationBar` 底下本來就能用——是鏡射把它搬進 Auto Layout 的世界的。
    func test_aFrameBasedCustomViewKeepsItsMeasuredSize() {
        let bar = makeBar()
        let custom = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 32))
        let item = UINavigationItem(title: "Chat")
        item.rightBarButtonItem = UIBarButtonItem(customView: custom)

        bar.bind(to: item, backAction: nil)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        XCTAssertEqual(custom.bounds.width, 120, accuracy: 1, "寬度不能塌成 0")
        XCTAssertEqual(custom.bounds.height, 32, accuracy: 1)
    }

    /// 已經走 Auto Layout 的 `customView` 不動——那是呼叫端自己安排好的。
    func test_anAutoLayoutCustomViewIsLeftAlone() {
        let bar = makeBar()
        let custom = UIView()
        custom.translatesAutoresizingMaskIntoConstraints = false
        let own = custom.widthAnchor.constraint(equalToConstant: 80)
        own.isActive = true
        custom.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let item = UINavigationItem(title: "Chat")
        item.rightBarButtonItem = UIBarButtonItem(customView: custom)
        bar.bind(to: item, backAction: nil)
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        XCTAssertEqual(custom.bounds.width, 80, accuracy: 1, "呼叫端自己的約束要說話")
        XCTAssertTrue(own.isActive)
    }

    // MARK: - customView 的內容不歸 Tero 管

    /// consumer 自己建好的 `customView`，內容不可以被覆寫掉。
    ///
    /// 想沿用玻璃材質的人會拿 `TeroNavigationButton` 當 `customView`，而
    /// `UIBarButtonItem(customView:)` 的 `title` 是 nil——先前不分來源一律
    /// `setTitle(barItem.title, for: .normal)`，於是**文字整個被清空**，只留一個空膠囊。
    /// 某個接入專案有四個呼叫點中彈，在淺色底上看起來像「白字」。
    func test_aCustomViewKeepsItsOwnTitleAndTint() throws {
        let bar = makeBar()
        let custom = TeroNavigationButton(title: "Send", material: .plain)
        custom.setTitleColor(.systemGreen, for: .normal)
        custom.tintColor = .systemGreen

        let item = UINavigationItem(title: "Compose")
        item.rightBarButtonItem = UIBarButtonItem(customView: custom)

        bar.bind(to: item, backAction: nil)
        bar.layoutIfNeeded()

        XCTAssertEqual(custom.currentTitle, "Send", "customView 的文字不是 Tero 設的，不該被清掉")
        XCTAssertEqual(custom.tintColor, .systemGreen, "tint 同樣不該被 nil 覆蓋")
    }

    /// 但停用狀態仍然要套用——那是 `UIBarButtonItem` 說了算的事。
    func test_aCustomViewStillFollowsTheItemsEnabledState() throws {
        let bar = makeBar()
        let custom = TeroNavigationButton(title: "Send", material: .plain)
        let barItem = UIBarButtonItem(customView: custom)
        barItem.isEnabled = false

        let item = UINavigationItem(title: "Compose")
        item.rightBarButtonItem = barItem

        bar.bind(to: item, backAction: nil)
        bar.layoutIfNeeded()

        XCTAssertFalse(custom.isEnabled)
        XCTAssertLessThan(custom.alpha, 1)
    }

    // MARK: - 鏡射出來的文字按鈕本身

    /// 停用要看得出來。`.custom` 型的 UIButton 只設 `.normal` 的話完全沒有變化。
    func test_aMirroredTitleButtonLooksDisabled() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Edit")
        let barItem = UIBarButtonItem(title: "Next", style: .plain, target: nil, action: nil)
        barItem.isEnabled = false
        item.rightBarButtonItem = barItem

        bar.bind(to: item, backAction: nil)
        bar.layoutIfNeeded()

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertNotEqual(button.titleColor(for: .disabled), button.titleColor(for: .normal),
                          "停用的顏色要和正常不同，否則看不出按鈕是關著的")
    }

    /// 文字按鈕要有留白與最小高度，否則膠囊貼著字緣、只有一行字高。
    func test_aMirroredTitleButtonHasPaddingAndAMinimumHeight() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Edit")
        item.rightBarButtonItem = UIBarButtonItem(title: "Next", style: .plain, target: nil, action: nil)

        bar.bind(to: item, backAction: nil)
        bar.layoutIfNeeded()

        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        let textWidth = try XCTUnwrap(button.titleLabel).intrinsicContentSize.width

        XCTAssertGreaterThanOrEqual(button.intrinsicContentSize.height, 36,
                                    "同一條列上的圖示按鈕是 44pt 的圓，文字按鈕不能只有一行字高")
        XCTAssertGreaterThan(button.intrinsicContentSize.width, textWidth + 20,
                             "左右要有留白，膠囊才不會貼著字緣")
    }

    /// 圖示按鈕不受影響——留白只加在文字按鈕上。
    func test_anImageButtonDoesNotGetTheTitlePadding() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in }
        let reference = UIButton(type: .custom)
        reference.setImage(image, for: .normal)

        let button = TeroNavigationButton(image: image, material: .plain)

        XCTAssertEqual(button.intrinsicContentSize.width,
                       reference.intrinsicContentSize.width, accuracy: 0.5)
    }

    // MARK: - 與 UIKit 對得上的排列順序

    /// `rightBarButtonItems` 的第 0 顆貼**右**緣往左排，`trailingItems` 由**左**往右排
    /// ——兩邊索引語意相反，中間要反轉一次。
    ///
    /// 實測原生（iPhone 17, iOS 26.5）：`[A, B]` 由左到右畫成 B、A。少了反轉的話整排
    /// 按鈕與原生相反，而既有測試只斷言數量，看不到這件事。
    func test_rightBarButtonItemsKeepTheNativeLeftToRightOrder() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Order")
        item.rightBarButtonItems = [
            UIBarButtonItem(title: "First", style: .plain, target: nil, action: nil),
            UIBarButtonItem(title: "Second", style: .plain, target: nil, action: nil)
        ]

        bar.bind(to: item, backAction: nil)
        bar.layoutIfNeeded()

        XCTAssertEqual(onScreenTitles(bar.trailingItems), ["Second", "First"],
                       "陣列第 0 顆要落在最右邊，與原生一致")
    }

    /// 對照：left 那側原生就是同序，**不可以**跟著反轉。
    func test_leftBarButtonItemsAreNotReversed() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Order")
        item.leftBarButtonItems = [
            UIBarButtonItem(title: "First", style: .plain, target: nil, action: nil),
            UIBarButtonItem(title: "Second", style: .plain, target: nil, action: nil)
        ]

        bar.bind(to: item, backAction: nil)
        bar.layoutIfNeeded()

        XCTAssertEqual(onScreenTitles(bar.leadingItems), ["First", "Second"])
    }

    // MARK: - 綁定那一刻

    func test_bindingMirrorsTitleAndItems() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Profile")
        item.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)
        ]
        item.leftBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)

        bar.bind(to: item, backAction: nil)
        bar.layoutIfNeeded()

        XCTAssertEqual(try titleLabel(in: bar).text, "Profile")
        XCTAssertEqual(bar.trailingItems.count, 2)
        XCTAssertEqual(bar.leadingItems.count, 1)
        XCTAssertTrue(bar.trailingItems.allSatisfy { $0 is TeroNavigationButton })
    }

    func test_titleViewIsMirrored() {
        let bar = makeBar()
        let item = UINavigationItem(title: "會被取代")
        let logo = UIView()
        item.titleView = logo

        bar.bind(to: item, backAction: nil)

        XCTAssertIdentical(bar.titleView, logo)
    }

    func test_aCustomViewIsUsedAsIs() {
        let bar = makeBar()
        let item = UINavigationItem(title: "x")
        let avatar = UIView()
        item.rightBarButtonItem = UIBarButtonItem(customView: avatar)

        bar.bind(to: item, backAction: nil)

        XCTAssertIdentical(bar.trailingItems.first, avatar)
    }

    // MARK: - 持續同步

    func test_changingTheTitleLaterReachesTheBar() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Before")
        bar.bind(to: item, backAction: nil)

        item.title = "After"

        XCTAssertEqual(try titleLabel(in: bar).text, "After", "有些頁面會在執行期換標題，所以要一直盯著")
    }

    func test_replacingTheRightItemsLaterRebuildsTheTrailingItems() {
        let bar = makeBar()
        let item = UINavigationItem(title: "x")
        item.rightBarButtonItems = [UIBarButtonItem(title: "a", style: .plain, target: nil, action: nil)]
        bar.bind(to: item, backAction: nil)
        let before = bar.trailingItems.first

        item.rightBarButtonItems = [
            UIBarButtonItem(title: "b", style: .plain, target: nil, action: nil),
            UIBarButtonItem(title: "c", style: .plain, target: nil, action: nil)
        ]

        XCTAssertEqual(bar.trailingItems.count, 2)
        XCTAssertFalse(bar.trailingItems.contains { $0 === before }, "換掉的 item 不留舊 view")
    }

    func test_anUnchangedItemKeepsItsView() {
        let bar = makeBar()
        let item = UINavigationItem(title: "x")
        let keep = UIBarButtonItem(title: "keep", style: .plain, target: nil, action: nil)
        item.rightBarButtonItems = [keep]
        bar.bind(to: item, backAction: nil)
        let before = bar.trailingItems.first

        item.title = "y"   // 任何一次同步

        XCTAssertIdentical(bar.trailingItems.first, before, "陣列沒換就不重建，觀察與狀態才穩")
    }

    func test_togglingIsEnabledOnAnItemReachesItsButton() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "x")
        let barItem = UIBarButtonItem(title: "Save", style: .done, target: nil, action: nil)
        item.rightBarButtonItems = [barItem]
        bar.bind(to: item, backAction: nil)
        let button = try XCTUnwrap(bar.trailingItems.first as? TeroNavigationButton)
        XCTAssertTrue(button.isEnabled, "前提")

        barItem.isEnabled = false

        XCTAssertFalse(button.isEnabled)
    }

    // MARK: - 字型與動作

    func test_doneIsSemiboldAndPlainIsRegularAtSeventeenPoints() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "x")
        item.rightBarButtonItems = [
            UIBarButtonItem(title: "Plain", style: .plain, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)
        ]
        bar.bind(to: item, backAction: nil)

        let plain = try XCTUnwrap((bar.trailingItems[0] as? UIButton)?.titleLabel?.font)
        let done = try XCTUnwrap((bar.trailingItems[1] as? UIButton)?.titleLabel?.font)
        XCTAssertEqual(plain.pointSize, 17)
        XCTAssertEqual(done.pointSize, 17)
        XCTAssertNotEqual(plain.fontName, done.fontName, "Done 要比 Plain 重——接入筆記記過寫死一種的後果")
    }

    func test_targetActionOfTheBarButtonItemFires() throws {
        let bar = makeBar()
        let recorder = ActionRecorder()
        let item = UINavigationItem(title: "x")
        item.rightBarButtonItem = UIBarButtonItem(title: "Go", style: .plain, target: recorder,
                                                  action: #selector(ActionRecorder.fire))
        bar.bind(to: item, backAction: nil)

        invokeTouchUpInside(on: try XCTUnwrap(bar.trailingItems.first as? UIControl))

        XCTAssertEqual(recorder.count, 1)
    }

    // MARK: - 返回鍵

    func test_aBackButtonIsSynthesisedWhenThereIsAnActionAndNoLeftItems() throws {
        let bar = makeBar()
        var popped = 0
        bar.bind(to: UINavigationItem(title: "Detail"), backAction: { popped += 1 })

        XCTAssertEqual(bar.leadingItems.count, 1)
        invokeTouchUpInside(on: try XCTUnwrap(bar.leadingItems.first as? UIControl))
        XCTAssertEqual(popped, 1, "返回動作由呼叫端提供，chrome view 不必反向引用容器")
    }

    func test_noBackButtonWithoutABackAction() {
        let bar = makeBar()
        bar.bind(to: UINavigationItem(title: "Root"), backAction: nil)

        XCTAssertTrue(bar.leadingItems.isEmpty)
    }

    func test_hidesBackButtonSuppressesTheSynthesisedOne() {
        let bar = makeBar()
        let item = UINavigationItem(title: "Detail")
        item.hidesBackButton = true

        bar.bind(to: item, backAction: {})

        XCTAssertTrue(bar.leadingItems.isEmpty)
    }

    func test_leftItemsReplaceTheBackButtonUnlessTheySupplementIt() {
        let bar = makeBar()
        let item = UINavigationItem(title: "Detail")
        item.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: nil, action: nil)
        bar.bind(to: item, backAction: {})
        XCTAssertEqual(bar.leadingItems.count, 1, "與 UIKit 相同：有 left items 就沒有返回鍵")

        item.leftItemsSupplementBackButton = true

        XCTAssertEqual(bar.leadingItems.count, 2, "說了補在旁邊，返回鍵才回來")
    }

    // MARK: - 解除

    func test_unbindingStopsTheSync() throws {
        let bar = makeBar()
        let item = UINavigationItem(title: "Before")
        bar.bind(to: item, backAction: nil)

        bar.bind(to: nil, backAction: nil)
        item.title = "After"

        XCTAssertEqual(try titleLabel(in: bar).text, "Before")
    }

    func test_rebindingToAnotherItemFollowsTheNewOne() throws {
        let bar = makeBar()
        let first = UINavigationItem(title: "First")
        let second = UINavigationItem(title: "Second")
        bar.bind(to: first, backAction: nil)

        bar.bind(to: second, backAction: nil)
        first.title = "Stale"

        XCTAssertEqual(try titleLabel(in: bar).text, "Second")
    }
}
