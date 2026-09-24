# Tero

**繁體中文** · [English](README.md)

自建的 iOS Tab Bar 與 Navigation 容器，取代 `UITabBarController` 與 `UINavigationController`。

它存在的理由不是「做一個更漂亮的 tab bar」，而是**讓 Tab 導覽的行為由這個套件決定，而不是由系統版本決定**。`UITabBarController` 在 iOS 18 與 iOS 26 連續兩次大幅改版，每次都迫使既有 App 回頭調整。此外它擋住兩類需求：Tab 圖示只能是 `UIImage`（塞不進 Lottie、SVGA、會動的頭像），以及 Tab Bar 上放不了獨立於 selection 之外的指令按鈕。

## 能力

- **Tab 內容可以是任意 `UIView`** —— Lottie、SVGA、頭像、自訂控制項，透過 `TeroTabContentProvider` 注入
- **兩種外觀**：Classic（貼齊底部、滿版）與 FloatingGlass（浮動、Liquid Glass）
- **Action Item** —— 位於 Bar 上但不是 Tab 的獨立指令，兩種外觀都支援
- **Overflow 與 More** —— 超過上限自動收納，上限依 `horizontalSizeClass` 選用
- **Badge** —— 圓點與文字兩種樣式，可統一設定外觀並個別覆寫
- **選取膠囊會滑過去** —— 全 Bar 只有一顆，在 Tab 之間連續移動；iOS 26 上它是真的玻璃，會反映底下的內容
- **可中斷的轉場** —— 動畫進行中再點別的 Tab 會立刻轉向，不排隊；動畫期間 Bar 照樣可以操作
- **連續的選取進度** —— Icon 漸變、兩張圖交叉淡入；Lottie／SVGA 可透過 `TeroTabInteractiveContentProvider` 取得 0…1 的轉場進度
- **滑動選取** —— 拖曳跟手或左右輕掃換 Tab，預設關閉
- **捲動驅動的收合** —— 往下捲讓開、往上捲回來，不奪取你的 `UIScrollViewDelegate`
- **自建的 Navigation Container** —— 每個 Tab 各自一疊 stack，stack 變更同步生效、動畫只是追上來的畫面；轉場被打斷時正在跑的那一段結算到終點，不丟棄也不排隊
- **頂部 chrome 由畫面自己提供** —— Tero 只要一個 `UIView` 和一條 0…1 的收合進度，不認得標題與版面；需要標題列＋分類列的話 `TeroNavigationBar` 內建那個結構
- **可取消的互動式返回** —— 邊緣手勢驅動，取消之後 stack 一個字都沒變過
- **正確的容器行為** —— ViewController 生命週期、navigation stack 保留、safe area、status bar、home indicator 與螢幕邊緣手勢延後的轉發
- **Swift 與 Objective-C 都能用**

## 需求

| 項目 | 版本 |
|---|---|
| 部署目標 | iOS 15.0+ / iPadOS 15.0+ |
| 建置工具 | Xcode 26+（FloatingGlass 需要 iOS 26 SDK 才能編譯） |
| Swift | 6.2+，即 Xcode 26 內附的工具鏈（套件以 Swift 5 語言模式編譯） |
| 依賴 | 無 |

**FloatingGlass 只在 iOS 26 以上生效。** 在 iOS 15–25 上執行時，實際樣式自動降級為 Classic；套件不嘗試以模糊效果仿製 Liquid Glass。你可以用 `requestedStyle` 與 `tabBarStyle` 分辨自己是否被降級。

**Classic 在 iOS 26 上維持 26 以前的外觀。** Tero 自己畫 Bar，完全不用 `UITabBar` 與 `UINavigationBar`，系統不會把它們玻璃化。看到哪一種外觀由 `style` 決定，不由系統版本決定——這正是本套件存在的理由。

## 安裝

### Swift 專案：Swift Package Manager

~~~swift
dependencies: [
    .package(url: "https://github.com/g761007/Tero.git", from: "2.0.0")
]
~~~

### Objective-C 專案：CocoaPods

~~~ruby
platform :ios, '15.0'
use_frameworks! :linkage => :static

target 'YourApp' do
  pod 'Tero', :git => 'https://github.com/g761007/Tero.git', :tag => '2.0.0'
end
~~~

~~~objc
#import <UIKit/UIKit.h>      // 必須在下一行之前，理由見下
#import <Tero/Tero-Swift.h>
~~~

兩個條件，都是實測出來的、不是推測：

- **`use_frameworks! :linkage => :static`**。它產出真的 framework（有 `Headers/`），ObjC++ 才匯入得到產生的介面；同時維持靜態連結，不必處理 embed。純靜態程式庫模式下 `.mm` 會失敗——那時 `@import` 需要 `-fcxx-modules`。
- **`.mm` 裡要先匯入 UIKit 再匯入產生的標頭**。那個標頭用 `@import UIKit` 取得型別，而 ObjC++ 預設沒有開 modules，順序顛倒會得到一整排 `unknown type name 'UIView'`。

**App target 自己沒有 Swift 原始碼、而機器上裝了 Metal Toolchain 元件時，可能連結失敗。** 這時 Xcode 26 會把 `TOOLCHAIN_DIR` 解析成 Metal 的 toolchain，CocoaPods 據此設的 Swift 程式庫搜尋路徑裡沒有 `swiftCompatibility56`，連結就停在 `__swift_FORCE_LOAD_$_swiftCompatibility56`。GitHub 的 macOS 26 runner 就裝了這個元件。建置時在環境變數設 `TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault`，本 repo 的 CI 也是這樣做。

**這個 pod 刻意不上 CocoaPods trunk。** Trunk 於 2026-12-02 永久唯讀，之後連既有 pod 的新版本都不再接受——上架等於把這個套件永遠凍在趕上期限的那一版。`:git` 不經 trunk，不受影響。

### Objective-C 專案：原始碼直接加入

把 `Sources/Tero/` 整個資料夾拖進你的 App target，然後在 `.m` 或 `.h` 中：

~~~objc
#import "YourAppModule-Swift.h"
~~~

其中 `YourAppModule` 是你 App target 的 product module 名稱。

**檢查產生的標頭露出了什麼時，先確認讀的是對的那一份。** DerivedData 裡有好幾份 `<App>-Swift.h`，只有 `Build/Intermediates.noindex/<App>.build/<Config>-<sdk>/` 底下那一份是這次編譯的產物——`Index.noindex/` 底下的是 index build 的，其他的可能是更早留下的舊檔。某個 App 第一次查就抓到一份 376 行的舊檔，裡面一個套件型別都沒有，差點判定 source drop 失敗；真正那份有 1227 行。

**兩種怎麼選？** pod 給你的是有版本的依賴與 module 邊界，`internal` 真的是 internal。source drop 是把原始碼放進你自己的 target，`internal` 因此不提供保護，但什麼都不用裝。兩種都實測過 `.m`、`.h`、`.mm` 皆可用；唯一沒有驗證過的路徑是「傳統 Xcode target 匯入 Swift **package**」。

## 使用

### Swift

~~~swift
let configuration = TeroTabBarConfiguration.defaultConfiguration()
configuration.style = .floatingGlass
configuration.compact.maximumVisibleItems = 5
configuration.regular.maximumVisibleItems = 6
configuration.scrollConfiguration.behavior = .minimizeOnScrollDown

let tabController = TeroTabBarController(configuration: configuration)
tabController.delegate = self

let homeItem = TeroTabItem(
    title: "Home",
    image: UIImage(systemName: "house"),
    selectedImage: UIImage(systemName: "house.fill")
)
let homeTab = TeroTab(
    identifier: "home",
    viewController: UINavigationController(rootViewController: HomeViewController()),
    item: homeItem
)

tabController.setTabs([homeTab, profileTab], selectedIdentifier: "home", animated: false)

// 切換會回傳有沒有成功。它是 @discardableResult，忽略回傳值不會有任何警告。
let switched = tabController.selectTab(withIdentifier: "profile", animated: true)
~~~

**`selectTab` 回傳 `Bool`，而且忽略它是完全靜默的。** 回 `false` 的情況有三種：delegate 的 `shouldSelect` 拒絕、沒有那個識別碼、那個 Tab 被停用。**deep link 與推播是最會踩的地方**——切換被拒絕，程式碼卻以為使用者已經到了。凡是目的地不由你決定的路徑，都該檢查回傳值。

`selectedIndex` 與 `selectedTab` 支援 KVO，需要持續追蹤時可以觀察它們，不必自己從 delegate 記狀態。

### Objective-C

~~~objc
TeroTabBarConfiguration *configuration = [TeroTabBarConfiguration defaultConfiguration];
configuration.style = TeroTabBarStyleClassic;
configuration.compact.maximumVisibleItems = 5;
configuration.selectedTintColor = UIColor.systemOrangeColor;

TeroTabBarController *tabController =
    [[TeroTabBarController alloc] initWithConfiguration:configuration];

TeroTabItem *item = [[TeroTabItem alloc] initWithTitle:@"Home"
                                                 image:[UIImage systemImageNamed:@"house"]
                                         selectedImage:nil];
TeroTab *tab = [[TeroTab alloc] initWithIdentifier:@"home"
                                    viewController:homeNavigationController
                                              item:item];

[tabController setTabs:@[tab] selectedIdentifier:@"home" animated:NO];
~~~

`[TeroTabBadge dotBadge]` 與 `[TeroTabBadge badgeWithValue:@"3"]` 是 Swift 那側 `.dot()` 與 `.value(_:)` 的 Objective-C 寫法。

### 自訂 Tab 內容

~~~swift
final class LottieTabProvider: NSObject, TeroTabContentProvider {
    func makeContentView() -> UIView {
        LottieAnimationView(name: "home")
    }

    func updateContentView(
        _ contentView: UIView,
        selected: Bool,
        presentationState: TeroTabBarPresentationState,
        animated: Bool
    ) {
        guard let view = contentView as? LottieAnimationView else { return }
        // animated == false 可能代表使用者開啟了「減少動態效果」
        if selected && animated { view.play() } else { view.stop() }
    }
}

item.contentProvider = LottieTabProvider()   // Item 會強持有它
~~~

只收得到 `selected: Bool` 做不出「膠囊滑到一半、動畫也播到一半」的效果。需要連續進度時改採進階協定——既有 provider 完全不受影響：

~~~swift
extension LottieTabProvider: TeroTabInteractiveContentProvider {
    func updateContentView(_ contentView: UIView, selectionProgress: CGFloat, animated: Bool) {
        guard let view = contentView as? LottieAnimationView else { return }
        view.currentProgress = selectionProgress   // 選取走到哪，動畫走到哪
    }
}
~~~

進度有兩個來源：選取轉場的每一幀，以及 `swipeSelectionMode = .drag` 拖曳進行中的每一次跟手。一段轉場保證以精確的 `0.0` 或 `1.0` 收尾；被中斷時從當下的值接續，不跳值。**拖曳中的 `animated` 一律是 `false`**——每一次回呼都是手指的當下位置，不是一段動畫，直接把進度套上去即可。

### 選取膠囊

全 Bar 只有一顆膠囊，在 Tab 之間移動——不是每格各自持有一個背景。預設在 FloatingGlass 顯示、Classic 不顯示（貼底滿版的原生 tab bar 沒有這個外框）：

~~~swift
configuration.itemAppearance.selectionIndicatorStyle = .automatic     // 預設
configuration.itemAppearance.selectionIndicatorMaterial = .automatic  // 靜態實色；FloatingGlass 移動時顯示透鏡（含 .drag 拖曳中）
configuration.itemAppearance.selectionIndicatorCornerRadius = nil     // nil = 膠囊

// 逐格指定尺寸；.zero 代表沿用 selectionIndicatorInsets 從格位推導
tab.item.selectionSize = CGSize(width: 60, height: 40)
~~~

顏色有兩個值，因為兩種材質需要**相反方向**的對比：`selectionIndicatorColor` 是實色的填色，`selectionIndicatorGlassTint` 是玻璃的 tint。玻璃的 tint 會被宿主材質吸收，淺色模式下白色 tint 不論多高的不透明度都浮不出來，所以它預設在淺色模式偏暗、深色模式偏亮。想同色的話把兩個值設成一樣即可。

**`selectionIndicatorColor` 的預設假設宿主膠囊不是淺色的。** 把 `floatingGlassAppearance.glassTintColor` 調成淺色（例如白色 70%）之後就成了白疊白：某個上線 App 實測膠囊與宿主的平均色差只有 13.3，看起來就是糊成一塊；同一個版面改成中性灰 30% 之後是 26.3，對比翻倍而且不必動用玻璃。**宿主的 tint 改淺色時，`selectionIndicatorColor` 要跟著調。** 這與上一段玻璃 tint 的理由同源，只是方向相反。

### 轉場的動態

~~~swift
configuration.motion.selectionResponse = 0.4          // 彈簧回應時間；nil 改用 selectionDuration
configuration.motion.selectionDampingRatio = 0.84     // 1.0 不回彈，越小回彈越明顯
configuration.motion.minimizeDuration = 0.28          // 收合
configuration.motion.restoreDuration = 0.22           // 恢復
configuration.motion.reselectDuration = 0.28          // 重複點擊的回饋
configuration.motion.contentTransitionDuration = 0.3  // Icon 交棒
configuration.motion.allowsInterruptibleTransition = true
configuration.motion.reduceMotionBehavior = .crossFade
~~~

`allowsInterruptibleTransition` 預設開啟：轉場途中收到新的選取會**從畫面上當下的位置**直接轉向。關掉它會退回「先讓目前這段跑完」的排隊行為。

開啟「減少動態效果」時不做彈簧位移——套件內部**所有**動畫一律視為關閉——但選取狀態保留，移動透鏡停用；降級方式由 `reduceMotionBehavior` 決定（`.crossFade` 交叉淡入、`.instant` 直接換狀態）。

### 滑動選取

滑動選取預設關閉，兩種模式擇一：

~~~swift
configuration.swipeSelectionMode = .drag    // 外框連續跟手，放開吸附最近的 Tab
configuration.swipeSelectionMode = .swipe   // 左右輕掃，跳到相鄰的 Tab
~~~

**`.drag` 需要看得見的選取膠囊才拖得動**——它拖的就是那顆膠囊。Classic 預設不顯示膠囊，所以在 Classic 上用 `.drag` 要同時把 `selectionIndicatorStyle` 設為 `.always`，否則按下去不會有反應。`.swipe` 沒有這個限制。

滑動只作用於 Tabs 膠囊——Action 在膠囊之外，不參與。滑動觸發的選取來源是 `.user`，一樣走 `shouldSelect`，被拒絕時外框回彈。吸附到 More 時也回彈：滑動的語意是選 Tab，不是開選單。

### 長按

實作 optional 的 delegate 方法，在某個 Tab 上按住半秒就會回報——Instagram 長按 Profile 切帳號那一類：

~~~swift
func teroTabBarController(_ tabController: TeroTabBarController, didLongPress tab: TeroTab) {
    presentAccountSwitcher(for: tab)
}
~~~

只在 delegate 實作了這個方法時才裝辨識器；More 與 Action 不發，辨識成功時 Tab 自己的點擊會被取消，不會順帶選取。**`.drag` 與長按互斥**：拖曳由零秒長按驅動、touch-down 當下就接手，半秒的長按永遠等不到，所以 `swipeSelectionMode == .drag` 時不會收到這個事件。

### 捲動驅動的收合

由目前顯示的畫面自行決定要不要被追蹤：

~~~swift
extension FeedViewController: TeroScrollProviding, TeroTabBarScrollBehaviorProviding {
    // 共用的輸入：頂部 chrome 與底部 Tab Bar 讀同一份樣本
    var teroTrackingScrollView: UIScrollView? { tableView }
    // Tab Bar 專屬的偏好
    var preferredTeroTabBarScrollBehavior: TeroTabBarScrollBehavior { .minimizeOnScrollDown }
}
~~~

兩個協定分開是刻意的：捲動**輸入**是共用的，反應方式則各側自己決定。只要輸入不要偏好的話只採用 `TeroScrollProviding`。

`.none` 是「這個畫面不要有捲動反應」這個**偏好**；`.inherit` 是**沒有偏好**、交回設定決定。不想表達偏好就別實作那個成員，或回 `.inherit`——把下層偏好往上傳的容器一定要用後者，因為 `@objc optional` 的成員只要宣告了就永遠「有回應」。

**最小化有兩種版面。** 預設的 `.uniform` 是整條 Bar 等比縮小、所有格都留著——寬與高用同一個比例，選取外框因此一定塞得進格位；大小由 `floatingGlassAppearance.minimizedHeight` 決定，寬度跟著走。`.selectedOnly` 把 Bar 收成只包著選取格的一顆小膠囊——iOS 26 原生 Tab Bar 最小化後的形態——點那顆膠囊就展開，不改選取：

~~~swift
configuration.floatingGlassAppearance.minimizedLayout = .selectedOnly
~~~

那個狀態下畫面上只有一格，所以 `.selectedOnly` 的 Bar 最小化時 `.drag` 不動。`.selectedOnly` 要不要成為預設，得拿真機跟系統自己的 Bar 比過再說；之前維持 `.uniform`。

### 頁面 Policy 與 Navigation 同步

~~~swift
extension DetailViewController: TeroTabVisibilityProviding {
    var preferredTeroTabVisibilityPolicy: TeroTabVisibilityPolicy { .hidden }
}

// 寫在 App 既有的 UINavigationControllerDelegate，不需要替換 delegate。
func navigationController(_ navigationController: UINavigationController,
                          willShow viewController: UIViewController,
                          animated: Bool) {
    tabController.coordinateNavigationTransition(
        navigationController, to: viewController, animated: animated
    )
}
~~~

Policy 可為 `.inherit`（交給 Scroll）、`.expanded` 或 `.hidden`。捲動行為那一側同樣有 `.inherit`：`TeroTabBarScrollBehavior.none` 是「這一頁不要有捲動反應」這個**偏好**，`.inherit` 是**沒有偏好**、交回設定決定。把下層偏好往上傳的容器要回 `.inherit`——`@objc optional` 的成員只要宣告了就永遠「有回應」，沒有「這次不表態」這回事。Navigation preview 不改公開 state；完成時提交，取消時還原來源。未接線的自訂容器可呼叫 `refreshScrollTracking()` 重新解析，但不會獲得互動返回同步。

程式 `setTabBarPresentationState(.hidden, animated:)` 的鎖定仍最高，須以 `.expanded` 解鎖。頁面 hidden 則只屬於該頁面，不建立全域鎖。

### 頁面決定 Bar 的介面風格

頁面也可以宣告它在畫面上時 Tab Bar 該用哪一種介面風格。Instagram 的 Reels 把 Bar 變成黑底，其餘 Tab 維持淺色：

~~~swift
extension ReelsViewController: TeroTabBarAppearanceProviding {
    var preferredTeroTabBarUserInterfaceStyle: UIUserInterfaceStyle { .dark }
}
~~~

Bar 的 `overrideUserInterfaceStyle` 跟著可見頁面走，動態色與模糊或玻璃材質一起翻轉。`.unspecified` 或不採用協定都表示「跟隨系統」。解析時點與 visibility policy 相同——切 Tab、導覽轉場結算、`refreshScrollTracking()`——`TeroNavigationContainer` 原封轉發 top 的宣告。切換不帶動畫。

**只有使用者的捲動會觸發收合**：程式設定 `contentOffset` 不會觸發收合；要用程式收合請呼叫 `setTabBarPresentationState`。未鎖定時程式回頂仍會展開。`scrollConfiguration.directionLockDistance` 預設 8pt；負值視為 0、非有限值回退預設。

捲動收合保留 expanded safe area，旋轉後仍保留。Navigation 期間固定來源 inset，完成時一次結算；Tero 只增減自己的 inset，不覆寫 Consumer 原有值。反過來也一樣：在 Tero 管理的 View Controller 上請**累加**而不要**指派** `additionalSafeAreaInsets`，指派會把容器為你保留的那一段一併抹掉。

### 自訂內容的收合進度

~~~swift
func updateContentView(_ contentView: UIView,
                       presentationProgress: CGFloat,
                       animated: Bool) {
    // 0 = expanded，1 = minimized；Hidden 由既有 presentationState 回呼處理。
    contentView.alpha = 1 - presentationProgress * 0.15
}
~~~

此 optional 回呼屬於既有 `TeroTabInteractiveContentProvider`，Action 也可接收；舊 Provider 不需修改。Reduce Motion／無動畫直接送端點。Selection 與收合進度可同時更新，Consumer 應避免讓兩者搶寫同一動畫游標。

## Navigation Container

`TeroNavigationContainer` 是自建的 stack 容器。它不是 `UINavigationController` 的子類，也不追求與它 API 相容——`UINavigationBar` 的版面沒有被凍進這個套件的公開 API，頂部 chrome 完全由畫面自己提供。

~~~swift
let container = TeroNavigationContainer(rootViewController: FeedViewController())

container.pushViewController(DetailViewController(), animated: true)
container.popViewController(animated: true)
container.popToRootViewController(animated: true)
container.setViewControllers([a, b, c], animated: false)

container.topViewController   // 最上層的那一個
container.viewControllers     // 由底到頂
~~~

放進 Tab：

~~~swift
let tab = TeroTab(
    identifier: "feed",
    viewController: container,
    item: TeroTabItem(title: "Feed", image: UIImage(systemName: "house"), selectedImage: nil)
)
~~~

每個 Tab 各自保有自己的 stack，切走再切回來不會被重置。

**Stack 的變更是同步的**：方法 return 之前 `viewControllers` 與 `topViewController` 已經是新值，動畫只是追上來的畫面。轉場進行中再送一次變更，正在跑的那一段會立刻結算到自己的終點，新的一段從乾淨的階層起跑——不丟棄、不排隊。丟棄會留下沒收到 `didMove(toParent:)` 的 child。

互動式返回是唯一的例外：它在 finish 判定成立之前不提交，所以取消之後 stack 一個字都沒變過。

~~~swift
container.isInteractivePopGestureEnabled = false   // 預設開啟
~~~

### 觀察 stack 變更

~~~swift
container.delegate = self

func teroNavigationContainer(_ container: TeroNavigationContainer,
                             willShow viewController: UIViewController,
                             animated: Bool) { }

func teroNavigationContainer(_ container: TeroNavigationContainer,
                             didShow viewController: UIViewController,
                             animated: Bool) { }
~~~

`willShow` 落在 **commit**：`viewControllers` 已經是新值，`pushViewController` 還沒 return。`didShow` 落在 **settle**：畫面追上了 stack。

**取消的互動式返回兩個事件都不發。** 它在 finish 判定成立之前不提交，stack 一個字都沒變過——發事件等於報告一次沒有發生的切換。做曝光追蹤時這一點很重要。

### 頂部 Chrome

Tero 對 chrome 的契約只有兩件事：**一個 `UIView`**，以及**一條 0…1 的收合進度**。裡面有沒有標題、有幾個區域、怎麼排版，Tero 一律不認得。

~~~swift
extension FeedViewController: TeroNavigationChromeProviding {
    func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        bar.title = "Feed"
        bar.trailingItems = [TeroNavigationButton(image: UIImage(systemName: "square.and.arrow.up"))]
        return bar
    }

    var teroNavigationChromeHeight: CGFloat { TeroNavigationBar.primaryHeight }
}
~~~

四條規則，寫出來的 chrome 才會正確：

1. **高度不含安全區。** 宣告的是 chrome 自己的內容高度；狀態列那一段由容器補上它自己的安全區。所以 `TeroNavigationBar.primaryHeight`（44）就是一列標題列的正確值，不必也不該自己加上狀態列高度——那個高度依裝置而異。
2. **高度是設定值，不是量測值。** Tero 不呼叫 `systemLayoutSizeFitting`、不讀 `intrinsicContentSize`。你給兩個端點，中間由 Tero 內插。帶高只在這個 View Controller 進入容器階層時讀一次。
3. **chrome view 建議半透明。** 內容從它底下捲過去，實色底會把那層關係蓋掉。`TeroNavigationBar` 預設是 `UIBlurEffect`，「降低透明度」開啟時才換成實色；自訂 chrome 照抄這個做法即可。

   iOS 26 上容器會裝一個 `.top` 的 `UIScrollEdgeElementContainerInteraction`（底部 Tab Bar 裝對稱的 `.bottom`），追蹤對象取自這一頁的 `teroTrackingScrollView`。兩顆互動都只在有 scroll view 可追蹤時才存在，閒著的會被拆掉——它不是免費的：會改寫容器裡動態色的解析，在 Tab Bar 上還會讓 iOS 26 的 observation tracking 每次版面都回報回饋迴圈。**它確實會生效，而且生效的方式對不透明的 chrome 有影響**：在那個容器裡，動態系統色會解析成 bar 的變體——iOS 26 模擬器上 `systemBackground` 畫出來是 (245, 245, 245) 而不是白，固定色（`.white`）不受影響。要與內容同色的 chrome（Instagram 那種白底 header）請用 `container.isScrollEdgeEffectEnabled = false` 關掉，或改用固定色。半透明 chrome 上的邊緣效果本身還需要真機確認；需要依賴的邊緣處理請自己在 chrome view 上做。
4. **chrome view 不得強引用容器。** 容器持有頁面，頁面持有 chrome view，chrome view 再強引用容器就是一個循環。要在 chrome 上做 push／pop，用 `weak var`。

**chrome 參與轉場。** 有動畫的 push／pop 期間兩頁的 chrome 都在容器裡：離開的淡出、進來的淡入，chrome 的高度在兩頁宣告的帶高之間內插，與內容走同一個 animator。互動式返回時跟著手指，取消的話離開的那一個回來。reserved inset 仍在 commit 那一刻就切換，所以進來的頁面從第一幀就用自己的帶高排版。

### 收合

實作 optional 的收合端點與回呼，chrome 就會隨捲動收合：

~~~swift
var teroNavigationChromeCollapsedHeight: CGFloat { 52 }

func updateTeroNavigationChrome(_ chromeView: UIView, collapseProgress: CGFloat) {
    (chromeView as? TeroNavigationBar)?.applyCollapseProgress(collapseProgress)
}
~~~

`TeroNavigationBar` 的收合方式是「Primary 淡出，Secondary 遞補它讓出的高度」。要別種收合方式，寫自己的 chrome view，不必改 Tero。

要捲多遠才收完、以及 chrome 要不要對捲動反應，是容器上的設定：

~~~swift
container.chromeCollapseDistance = 96     // 往下捲多少 pt 算完全收合；預設 120
container.chromeScrollBehavior = .fixed   // .hidePrimary（預設）隨捲動收合；.fixed 永遠不收
~~~

Instagram 那種「header 在自己的高度內就收完」，把距離設成 chrome 的展開高度即可。這兩個值與 Tab Bar 的 `TeroTabBarScrollBehavior` 是兩套：同一次下捲，頂部可以收起來、底部可以不動。

畫面還要交出自己的 scroll view，Tero 才有輸入可讀；它不會替換你的 `delegate`：

~~~swift
extension FeedViewController: TeroScrollProviding {
    var teroTrackingScrollView: UIScrollView? { tableView }
}
~~~

樣本從哪來取決於容器放在哪。在 `TeroTabBarController` 底下時由 Tab Bar 的追蹤路徑轉進來，頂部 chrome 與 Bar 讀同一份樣本；**單獨使用**的 `TeroNavigationContainer`（modal 流程、onboarding）自己觀察頁面的 scroll view。兩條路徑互斥，同一個 scroll view 不會被觀察兩次。

### Primary 與 Secondary

`TeroNavigationBar` 內部就是兩段式的：Primary 是標題列，Secondary 是掛在它下面的任意 view。這個結構住在導覽列裡，不是公開 API 的一部分。

~~~swift
let bar = TeroNavigationBar(frame: .zero)
bar.title = "Profile"
bar.leadingItems = [TeroNavigationButton(image: UIImage(systemName: "chevron.left"))]
bar.trailingItems = [TeroNavigationButton(image: UIImage(systemName: "plus"), material: .glass)]
bar.secondaryView = categoryRow
~~~

帶兩段時的高度：`TeroNavigationBar.primaryHeight + <Secondary 的高度>`，收合值就是 Secondary 那一段。

### 按鈕材質

`TeroNavigationButton` 畫的是純色圖形或 iOS 26 的玻璃膠囊。`.automatic` 跟隨最近的 `TeroTabBarController` 的 effective style——FloatingGlass 底下是玻璃、Classic 或 iOS 15–25 是純色、單獨使用的容器也是純色——於是「要不要 Liquid Glass」只剩一個決定：`configuration.style`。

~~~swift
bar.trailingItems = [TeroNavigationButton(image: UIImage(systemName: "plus"), material: .automatic)]
~~~

預設仍是 `.plain`。解析在按鈕進入視窗時發生；Style 不支援執行期切換，之後不必重算。

鏡射從 `UIBarButtonItem` 建出來的按鈕（見[鏡射 `UINavigationItem`](#鏡射-uinavigationitem)）你拿不到，所以改由導覽列替它們決定材質——例如 FloatingGlass 的 Tab Bar 配純色的導覽列按鈕：

~~~swift
bar.defaultButtonMaterial = .plain   // 預設 .automatic
~~~

它套用在導覽列上所有材質**仍是 `.automatic`** 的按鈕——設定的當下，以及之後每次導覽列的 items 改變時——你自己設成 `.plain` 或 `.glass` 的不動。它是把那些按鈕改掉，而不是讓它們跟著這個值走，所以把它改回 `.automatic` 不會把先前改過的按鈕還原。

### 標題的外觀

~~~swift
bar.titleColor = .white                                   // nil 沿用 .label
bar.titleFont = .systemFont(ofSize: 22, weight: .bold)    // nil 沿用 .headline
bar.titleView = twoLineHeader                             // 設了就取代文字標題
bar.showsBackdrop = false                                 // 底自己畫
bar.buttonTitleColor = .white                             // nil 沿用 .label
~~~

這幾個都是 `nil`／預設時行為與不設完全相同。

**`buttonTitleColor` 管的是導覽列上文字按鈕的顏色**，`tintColor` 到不了那裡——它對 `UIButton` 的文字不生效。沒有這個屬性的話，深色或彩色底的導覽列**沒有任何辦法**把文字按鈕染淺，由 `UIBarButtonItem` 鏡射來的按鈕尤其如此，呼叫端根本拿不到那顆按鈕。停用色會跟著走，因為寫死的 `.tertiaryLabel` 在深色底上一樣看不見。呼叫端自己設過顏色的按鈕不會被覆蓋；圖示按鈕照舊走 `tintColor`。

**指定 `titleFont` 等於退出 Dynamic Type**——這個屬性是用來照抄既有設計的固定尺寸。兩者都要的話自己包一層：

~~~swift
bar.titleFont = UIFontMetrics(forTextStyle: .headline)
    .scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
~~~

**`titleView` 要自己說得出尺寸。** Tero 不呼叫 `sizeThatFits(_:)` 也不讀 `intrinsicContentSize`（尺寸是設定值不是量測值），所以從 `frame` 世界搬過來的 view（例如自繪的 label）要自己釘寬高約束，並把水平壓縮阻力調低，免得和「讓開兩側控制項」那兩條打架。放進 `leadingItems` 或 `trailingItems` 的 view 同理，那兩個槽是 stack view。

**停用的 `customView` 會淡兩次。** Tero 對那個 view 套 `alpha = 0.35`，而你自己的停用顏色再疊上去——40% alpha 的顏色放在 35% 的 view 裡，最終大約是 **14%**，非常淡。鏡射自己建的按鈕不會疊，它只吃停用的文字顏色。如果自訂 view 停用時太淡，把你自己那個顏色的 alpha 拉高，讓 Tero 的 0.35 單獨生效即可。

**`UIBarButtonItem` 的 `customView` 是刻意的例外。** 那個 view 是你交給 UIKit 的，在那裡 frame-based 完全可用，你從沒同意過 Tero 的契約——是鏡射把它搬進 Auto Layout 的世界，所以由鏡射替你把量好的尺寸釘上去（用 `.defaultHigh`，窄螢幕上寧可讓它縮也不要變成不可滿足的約束）。已經走 Auto Layout 的 customView 不動，由它自己的約束決定。

### 鏡射 `UINavigationItem`

已經用 `navigationItem` 描述導覽列的頁面不必改寫。把 item 綁上去，導覽列就鏡射它，之後以 KVO 持續跟隨：

~~~swift
extension ProfileViewController: TeroNavigationChromeProviding {
    func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        bar.bind(to: navigationItem, backAction: { [weak self] in
            self?.container?.popViewController(animated: true)   // weak：chrome 不得強引用容器
        })
        return bar
    }
    var teroNavigationChromeHeight: CGFloat { TeroNavigationBar.primaryHeight }
}
~~~

鏡射的有 `title`、`titleView`、`leftBarButtonItems`、`rightBarButtonItems`、`hidesBackButton`、`leftItemsSupplementBackButton`，之後每顆 `UIBarButtonItem` 的 `isEnabled`、`title`、`image`、`tintColor` 也持續盯著，執行期換按鈕的頁面照樣能用。`UIBarButtonItem` 變成套用導覽列 `defaultButtonMaterial` 的 `TeroNavigationButton`，字型比照 UIKit——`.plain` 17pt regular、`.done` 17pt semibold——並保留 target-action、`primaryAction` 與 `menu`；`customView` 直接沿用。rendering mode 為 `.automatic` 的圖會當成 template 畫、吃導覽列的 tint，與 `UINavigationBar` 相同；要原色請用 `.alwaysOriginal`。自己建的 `TeroNavigationButton` 就是 `UIButton`，`.automatic` 的圖會照原色畫，要吃 tint 請給 template 圖或 SF Symbol。文字按鈕還會採用 item 自己的 `titleTextAttributes`，而且優先於導覽列的預設：normal 與 disabled 的顏色贏過 `buttonTitleColor`，normal 的字型取代 17pt 的預設。傳了 `backAction`、有上一頁可以回去、item 沒有藏返回鍵、也沒有自己的 left items（或它們是補在返回鍵旁的）時合成一顆返回鍵，判準與 UIKit 相同。在 `TeroNavigationContainer` 裡，「有沒有上一頁」由容器回答，並隨 stack 變更保持正確——所以 root 不會有返回鍵，每一頁都可以照傳同一個 `backAction`。傳 `nil` 解除。Objective-C 是 `-bindToNavigationItem:backAction:`。

**系統型的 item 會變成空按鈕。** `UIBarButtonItem(barButtonSystemItem:)`（done、cancel、add 這類）的 title、image、customView 全是 nil，而 UIKit 沒有公開的方法讀出它是哪一種系統 item，所以鏡射只能畫出一顆空按鈕。Debug build 遇到時會停在 assertion，Release build 則顯示那顆空按鈕。請改用明確的 title 或 image 建立這些 item。

這不是 `UINavigationController` 相容層：沒有假的 `navigationBar`、沒有型別硬轉。它只涵蓋 `navigationItem` 表達得出來的東西；導覽列本身的外觀仍走 `TeroNavigationBar` 自己的屬性。

## 設定

`TeroTabBarConfiguration` 是唯一的設定入口。Controller 於初始化與 `applyConfiguration(_:animated:)` 時各做一次**深拷貝**，因此建立之後修改原本那份物件不會影響它。

讀取目前設定用 `currentConfiguration()`——它是**方法**而不是屬性，因為回傳的是快照：改它不會生效，要生效必須呼叫 `applyConfiguration`。

| 群組 | 內容 | Objective-C |
|---|---|---|
| `style` | Classic 或 FloatingGlass | ✅ |
| `compact` / `regular` | 各自的可見數量上限（含 More，不含 Action slot） | ✅ |
| `normalTintColor` / `selectedTintColor` | 主色（轉發至 `itemAppearance`） | ✅ |
| `morePresentationStyle` / `moreItem` | More 的呈現方式與外觀 | ✅ |
| `itemAppearance` / `badgeAppearance` | Item 與 Badge 的細部外觀 | Swift only |
| `classicAppearance` / `floatingGlassAppearance` | 各樣式的細部外觀 | ✅（見下） |
| `scrollConfiguration` | 捲動行為與門檻 | ✅（見下） |
| `motion` | 選取轉場的時長、彈簧與降級方式 | ✅（見下） |
| `swipeSelectionMode` | 滑動選取的操作方式 | ✅ |

`motion`、`scrollConfiguration`、`classicAppearance`、`floatingGlassAppearance` 都是 Swift-only 的值型別，Objective-C 透過 `TeroTabBarConfiguration` 上帶前綴的轉發屬性存取——`motion*` 十個、`scroll*` 五個、`classic*` 七個、`floatingGlass*` 十三個，每個欄位一個：

~~~objc
configuration.motionSelectionDuration = 0.5;
configuration.motionSelectionDampingRatio = 0.9;
configuration.motionReduceMotionBehavior = TeroTabReduceMotionBehaviorInstant;

// selectionResponse 在 Swift 是 Optional；Objective-C 以 0 表示「不指定」，
// 改用 motionSelectionDuration 搭配 motionSelectionDampingRatio。
configuration.motionSelectionResponse = 0;

configuration.scrollBehavior = TeroTabBarScrollBehaviorHideOnScrollDown;
configuration.classicBarHeight = 52;
configuration.classicUsesBlurEffect = NO;
configuration.floatingGlassBottomInset = 21;
configuration.floatingGlassTintMode = TeroTabGlassTintModeTinted;
configuration.floatingGlassTintColor = UIColor.systemPinkColor;
~~~

`itemAppearance` 與 `badgeAppearance` 除了兩個主色之外沒有轉發入口——需要那些細部時，在 Swift 端建好 `TeroTabBarConfiguration` 再交給 Objective-C 使用。

**`floatingGlassAppearance.bottomInset` 從螢幕邊緣量起**，不是疊在安全區之上；預設 21 讓 Bar 落在系統原生浮動 Tab Bar 的位置。子畫面讓開的邊距跟著調整：Bar 落在 home indicator 帶子裡的那一段已經在視窗自己的 safe area 裡，不重複計算。

## 開發

合併前的完整驗證跑這一支，它執行的是與 CI 五個 job 相同的指令：

~~~bash
./Scripts/verify-local.sh
~~~

CI（`.github/workflows/ci.yml`）在每次 push 到 `main` 與每個 pull request 上跑這五個 job。push 到 fork 不會觸發；要在 fork 上跑，用 Actions 頁面的 Run workflow。

個別指令：

~~~bash
# 測試——destination 必須是 iOS 26+ 的模擬器，而且要解析成 UDID
xcodebuild test -scheme Tero \
  -destination "$(./Scripts/resolve-simulator.sh)"

# Swift Demo
cd Demo/SwiftDemo && xcodegen generate && open SwiftDemo.xcodeproj

# Objective-C Demo（source drop）
cd Demo/ObjCDemo && xcodegen generate && open ObjCDemo.xcodeproj

# 守門：套件內不得有資源檔
./Scripts/check-no-resources.sh

# 守門：公開 API 與 Objective-C 介面 diff
./Scripts/check-public-api.sh
~~~

模擬器由 `Scripts/resolve-simulator.sh` 挑。它**一律解析成 UDID**——在某些機器上把名稱直接餵給 `xcodebuild` 會解析不到，即使那台裝置存在、可用而且已經開機。它也**拒絕 iOS 26 以下**：那裡沒有 FloatingGlass，71 個由 `XCTSkipUnless(isFloatingAvailable)` 守著的測試會整批跳過，而整輪仍然回報 0 failures。要指定機型用 `TERO_DEVICE`，或把完整的 destination 當 `verify-local.sh` 的第一個參數。

Demo 的專案檔以 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 產生，repo 只保留 `project.yml`。

Demo 支援啟動參數以便自動化截圖：`--badges`、`--many-tabs`、`--style=floatingGlass`、`--state=minimized`、`--scrolled=300`、`--swipe=drag`、`--reset-settings`、`--instagram`。

**設定會存下來，重啟後沿用。** Interaction Lab 的手感預設、Tab 數、操作方式與七個滑桿值，以及主畫面的滑動模式與 Style 都寫進 `UserDefaults`，調好之後重開 App 不必重來。規則有三條：

- **啟動參數優先於存檔**，而且不會被寫回去——自動化截圖必須是確定的，不能受上一次手動調參影響。
- **Style 只在下次啟動生效**。它不支援 runtime 切換（見[已知限制](#已知限制)），所以主畫面的 `Style↻` 按鈕只改存檔；重開才會換成另一種樣式。這也是在不用啟動參數的情況下切換 Style 的唯一方法。
- 想回到乾淨起點：主畫面的 `清除設定` 按鈕，或用 `--reset-settings` 啟動。

保存只做在 Demo 端。套件本身不碰 `UserDefaults`——設定的生命週期是 App 的事，這也是 `TeroTabBarConfiguration` 做深拷貝快照、而不是自己記住狀態的原因。

**Interaction Lab**（`--lab`，或主畫面的 `Lab` 按鈕）可以在裝置上即時調整 duration、damping、response、選取寬高、圓角與 icon scale，並切換 Static / Slide / Fluid / Spring 四種手感、3–6 個 Tab、以及點擊／拖曳／輕掃三種操作方式。這些效果只能用眼睛驗——單元測試驗得了「有沒有中斷」，驗不了「哪一組最像你要的感覺」。

四組參考案例（`--case=a` … `--case=d`，或主畫面的 `A`/`B`/`C`/`D` 按鈕）：

| | 重點 |
|---|---|
| A | 深色底、共享膠囊平滑滑動、Icon 同步轉場 |
| B | Lottie 自訂內容 + Badge，亮色底，動畫與選取進度同步 |
| C | 會變化的彩色 backdrop、玻璃隨之反應、逐格不同的選取尺寸 |
| D | `999+` Badge、圓點 Badge、獨立的 Search Action |

**Instagram 參考案例**（`--instagram`，或 `Nav` → `Instagram`）用原語拼出一個 Instagram 形狀的 App：不透明 Classic Bar 上五格只有圖示的 Tab、中央的「＋」是 Action Item、由 Content Provider 畫的頭像 Tab（外圈跟著選取進度長出來）、瞬間換圖（`contentTransitionDuration = 0`）、Home 的 header 在自己的高度內滑走再回來、再點一次回頂、切到 Reels 時 Bar 變黑、Profile 的分段列在標題收合後留下、長按 Profile 開帳號切換。每個 Tab 各自一個 `TeroNavigationContainer`。

公開 API 有意變更時，重新產生基準並在 commit 訊息說明：

~~~bash
./Scripts/extract-swift-api.sh > Scripts/api/swift-api-baseline.txt
./Scripts/extract-objc-interface.sh > Scripts/api/objc-interface-baseline.txt
~~~

## 已知限制

**Dynamic Type 只部分跟隨。** Tab Item 的 caption 與 `TeroNavigationBar` 的標題會跟著字級放大；其餘的 Appearance 字型與內容尺寸是固定值。這是明確的取捨，不是 bug。

自訂 chrome 的帶高若會隨字級改變，容器會在字級變動時自己重算；你自己改變了 chrome 的結構（換標題、Secondary 列出現或消失）則呼叫 `setNeedsChromeGeometryUpdate()`。

**不支援自訂返回手勢。** 互動式返回的驅動入口不公開，2.0 只提供 Tero 自己的邊緣手勢。需要做手勢仲裁（頁面左緣有橫向捲動內容）時，`interactivePopGestureRecognizer` 拿得到那顆辨識器：

~~~swift
carousel.panGestureRecognizer.require(toFail: container.interactivePopGestureRecognizer)
~~~

**不支援自訂轉場。** 轉場的樣式（推拉與 parallax）是固定的，只有 `transitionDuration` 可調。自訂轉場協定不在 2.0 的範圍內。

**More 沒有擴充點。** `TeroTabMorePresentationStyle` 只有內建的幾種呈現方式，不接受自訂容器。

**iOS 26 以下沒有 FloatingGlass。** 實際樣式一律降級為 Classic，因此在這些版本上也沒有捲動最小化。**降級的目標是「隱藏」，不是「不動」**——Classic 之下 `.minimizeOnScrollDown` 會被換成 `.hideOnScrollDown`。要讓舊系統上完全不反應，請在該頁明確回傳 `.none`。

**套件不含任何在地化字串。** More 未設定標題時只顯示圖示；`.dot` 樣式的 Badge 沒有可播報的原始值，VoiceOver 的措辭需由你在 `badge.accessibilityValue` 提供。這是為了不與你 App 既有的在地化管線衝突。

**不支援 Storyboard 與 XIB。** 僅支援程式化初始化，`init(coder:)` 標記為 unavailable。

**不支援 runtime 切換 Style。** `applyConfiguration` 會忽略 `style` 欄位。

**Objective-C 以 source drop 整合時，`internal` 不提供實際保護。** 原始碼與你的 App 同屬一個 module，套件的內部型別對你可見可改。請仍然只依賴公開 API，否則未來的重構會造成破壞。

**Lottie 無法從 Objective-C 直接使用**（Lottie 4.x 是純 Swift）。若需要，在同一個 target 內加一個 Swift 轉接檔。

**玻璃選取膠囊在淺色內容上比較含蓄。** 玻璃的 tint 會被宿主材質吸收，底下是淺色內容時對比本來就有限——參考中的浮動 Tab Bar 全是深色底，「比 Bar 更亮」在那些情境才成立。需要更強的區別時把 `selectionIndicatorMaterial` 設為 `.solid`。

### 從 `UINavigationController` 遷移

`TeroNavigationContainer` **不是** `UINavigationController` 的子類，所以 `self.navigationController` 在 Tero 的階層裡是 `nil`。Tero **不提供相容層**，理由見下。

常見的做法是在 consumer 端補一層 shim，把容器硬轉成 `UINavigationController *` 再用 category 補齊成員。這條路有兩個坑，都是實際踩過的：

**一、Objective-C 的 category 會無聲覆蓋套件已經提供的成員。** 有人為 shim 補了 `interactivePopGestureRecognizer` 回傳 `nil`，而 `TeroNavigationContainer` 本來就有這個屬性、回傳真的辨識器。category 贏了，於是 4 個「關掉側滑返回」的呼叫點全部靜默失效——側滑一直是開著的。**補 shim 之前先查這裡有沒有。**

**而且每次更新 Tero 都要再查一次。** shim 寫的時候套件還沒有那個成員，等套件有了，它就從補洞變成蓋掉好的。同一個 App 後來又發現兩個：`delegate`，讓 `TeroNavigationContainerDelegate` 在那個 App 裡完全無法使用；以及 `popToViewController:animated:`。編譯器只在協定方法那一種情況會提醒（`-Wobjc-protocol-method-implementation`），其餘一律安靜。

**二、外觀相關的成員無論怎麼 shim 都是靜默失效。** `navigationBar` 回傳一顆沒有接到任何東西的 `UINavigationBar`：編得過、跑得動、什麼都沒發生。有一次遷移裡 51 個這樣的呼叫點，換套件後**幾乎每一個視覺回歸都出自它們**——半透明導覽列、陰影、黑底、標題顏色與字型，沒有一個是編譯器或測試找到的。

導覽列的外觀請改走 chrome：`TeroNavigationBar` 的 `title` / `titleColor` / `titleFont` / `titleView` / `leadingItems` / `trailingItems` / `secondaryView` / `showsBackdrop`，或乾脆寫自己的 chrome view。已經在講 `navigationItem` 的頁面可以照舊：`bind(to:backAction:)` 會鏡射它（見[鏡射 `UINavigationItem`](#鏡射-uinavigationitem)）。

**Tero 為什麼不做這一層**：它唯一能提供的形式就是上面那種靜默失效，而真正有用的形式（讓那些呼叫點變成帶指引的編譯錯誤）Tero 做不到——那是 consumer 對 UIKit 型別的強制轉換，套件插不上手。用全域開關控制相容層更糟：外觀有沒有生效會隨 build 設定改變，而外觀失效偏偏是最難從程式碼看出來的一類。

**更好的做法：先把呼叫點搬到你自己的抽象上。** 另一個上線 App（約 600 個 `.m`、194 個 VC）走相反的路，成本低得多。它在碰 Tero 之前，先加一層自己的 `UIViewController` category（`navigationStack`、`tabBarHost` 之類的成員），目前只是原樣轉呼叫 UIKit，然後把 92 處 `.navigationController` 與 24 處 `.tabBarController` 改名過去。這一步行為完全沒變，可以單獨驗證；換 Tero 時只動 category 的實作。差別在於型別是誰的：shim 把 Tero 硬轉成 UIKit 的 `UINavigationController *`，對不上的地方只能在執行期靜默失效；型別是你自己的，換實作時編譯器會逐一指出。

容器自己的職責另當別論，那些 Tero 都提供：`pushViewController` / `popViewController` / `popToViewController` / `popToRootViewController` / `setViewControllers` / `topViewController` / `viewControllers` / `interactivePopGestureRecognizer` / `isInteractivePopGestureEnabled`，以及 `TeroNavigationContainerDelegate` 的 `willShow` / `didShow`。

**三、`contentInsetAdjustmentBehavior = .automatic` 會少一條子句。** 它的定義是「等同 `.scrollableAxes`，**外加**：在 `UINavigationController` 管理的 VC 裡永遠調整頂端 inset」。`TeroNavigationContainer` 不是 `UINavigationController`，所以只剩 `.scrollableAxes`——**內容不滿一頁時垂直軸不算可捲，頂端 inset 就是 0**，滿版的內容整個鑽到導覽列底下。陰險之處是**內容多的頁面正常、內容少的頁面壞掉**。

解法是把主捲動容器升成 `.always`。**只升主捲動容器，不要掃整棵樹**——水平分頁容器與裡面的清單看到同一個安全區，一起升就套兩層 inset，而 `contentInset` 一改就會動 `contentOffset`，`pagingEnabled` 按 `bounds.width` 吸附，症狀是分頁會歪掉。

**四、先搜一次 `[UINavigationBar appearance]`。** 很多老專案有 `setTranslucent:NO` 之類的全域設定，那讓每一頁的 `view` 從導覽列**底下**開始。換掉容器之後那個前提消失，依賴它的頁面（尤其是自己關掉 inset 自動調整的）會整個往上跑。

**五、`scrollsToTop` 要掃整棵樹、只留一個。** UIKit 的規則是「同時有多個可見的 scroll view 開著 `scrollsToTop`，就一個都不捲」。換成容器之後同時活著的常常不只一個（水平分頁容器、頂端的橫向列、各分頁的清單），症狀是點狀態列不是沒反應就是捲到別的清單。

**六、底部 sheet 不要包導覽容器。** iOS 26 會接管導覽容器的呈現，於是 sheet 的圓角與位置就不再由你的 animator 決定——圓角變成系統的、指定的高度失效。為了一條標題列而包一層並不划算，做一個純 view 的標題列即可。

**建議的順序：先換容器、長得跟以前一樣，之後才換外觀。** 導覽列按鈕的材質用 `.automatic`，讓它跟著 Tab Bar 的 style 走：切 `.classic` 時整個 App 退回原本的外觀，先確認「換容器」沒有造成回歸；乾淨之後再開 `.floatingGlass`，這時看到的每一個問題都確定是外觀造成的。

## API 穩定性

minor 版本僅新增 API，patch 版本僅修 bug，破壞性變更進下一個 major 版本。

**2.1.0 是目前唯一的例外。** Objective-C 端有四個屬性的名稱改成 UIKit 的 `getter=is…` 慣例——`TeroNavigationContainer` 的 `interactivePopGestureEnabled` 與 `scrollEdgeEffectEnabled`，以及 `TeroTabItem`、`TeroTabActionItem` 的 `enabled`——Swift 名稱不變。沿用舊名讀取仍然編譯得過，沿用舊名賦值則會失敗，編譯器會在每個呼叫點指出找不到的 `setIs…:` setter。release note 列出四組對照。

**公開表面由兩份基準釘住**：`Scripts/api/` 下 Swift 與 Objective-C 各一份。`Scripts/check-public-api.sh` 每次都拿建置結果與它們比對，任何增刪都會讓 CI 轉紅，直到有意地重新產生基準為止（見[開發](#開發)）。

## 授權

MIT，見 [`LICENSE`](LICENSE)。
