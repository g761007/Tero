# Tero

**English** · [繁體中文](README.zh-Hant.md)

A hand-built tab bar and navigation container for iOS, replacing `UITabBarController` and `UINavigationController`.

It does not exist to make a prettier tab bar. It exists so that **tab navigation behaves the way this package decides, not the way the OS version decides**. `UITabBarController` was reworked substantially in iOS 18 and again in iOS 26, and each time existing apps had to go back and adjust. It also blocks two ordinary requirements: a tab icon can only be a `UIImage` — no Lottie, no SVGA, no animated avatar — and the tab bar has no room for a command button that is not a tab.

## What it does

- **A tab's content can be any `UIView`** — Lottie, SVGA, avatars, custom controls, injected through `TeroTabContentProvider`
- **Two appearances**: Classic (flush to the bottom, full width) and FloatingGlass (floating, Liquid Glass)
- **Action items** — a command that sits on the bar without being a tab, supported in both appearances
- **Overflow and More** — items past the limit are collected automatically, and the limit follows `horizontalSizeClass`
- **Badges** — dot and text styles, configured together and overridable per item
- **One selection capsule that travels** — the whole bar has exactly one, and it moves continuously between tabs; on iOS 26 it is real glass and refracts what is behind it
- **Interruptible transitions** — tapping another tab mid-animation turns immediately rather than queueing, and the bar stays usable throughout
- **Continuous selection progress** — icons tint and cross-fade; Lottie and SVGA can read the 0…1 transition progress through `TeroTabInteractiveContentProvider`
- **Swipe selection** — drag the capsule with your finger or flick left and right, off by default
- **Scroll-driven collapse** — scroll down and the bar gets out of the way, scroll up and it returns, without taking over your `UIScrollViewDelegate`
- **A hand-built navigation container** — one stack per tab; stack changes take effect synchronously and the animation is only the picture catching up. An interrupted transition settles the running segment to its endpoint rather than dropping it or queueing behind it
- **Top chrome comes from the screen** — Tero asks for a `UIView` and a 0…1 collapse progress and knows nothing about titles or layout. When you want a title row plus a category row, `TeroNavigationBar` already has that structure
- **Cancellable interactive pop** — driven by the edge gesture, and cancelling leaves the stack untouched
- **Correct container behaviour** — view controller lifecycle, navigation stack retention, safe area, status bar, home indicator and screen-edge gesture deferral all forwarded
- **Usable from both Swift and Objective-C**

## Requirements

| | |
|---|---|
| Deployment target | iOS 15.0+ / iPadOS 15.0+ |
| Build tools | Xcode 26+ (FloatingGlass needs the iOS 26 SDK to compile) |
| Swift | 6.2+, the toolchain in Xcode 26 (the package compiles in Swift 5 language mode) |
| Dependencies | none |

**FloatingGlass only takes effect on iOS 26 and later.** Running on iOS 15–25, the effective style falls back to Classic; the package does not try to imitate Liquid Glass with a blur. Compare `requestedStyle` with `tabBarStyle` to tell whether you were downgraded.

**Classic keeps its pre-iOS-26 look on iOS 26.** Tero draws its own bars and never uses `UITabBar` or `UINavigationBar`, so the system does not apply Liquid Glass to them. Which look you get is decided by `style`, not by the OS version — that is the point of the package.

## Installation

### Swift projects: Swift Package Manager

~~~swift
dependencies: [
    .package(url: "https://github.com/g761007/Tero.git", from: "2.0.0")
]
~~~

### Objective-C projects: CocoaPods

~~~ruby
platform :ios, '15.0'
use_frameworks! :linkage => :static

target 'YourApp' do
  pod 'Tero', :git => 'https://github.com/g761007/Tero.git', :tag => '2.0.0'
end
~~~

~~~objc
#import <UIKit/UIKit.h>      // before the next line, see below
#import <Tero/Tero-Swift.h>
~~~

Two requirements, both measured rather than assumed:

- **`use_frameworks! :linkage => :static`.** It produces a real framework with a `Headers/` directory, which is what lets ObjC++ reach the generated interface, while keeping static linkage so there is nothing to embed. As a plain static library the `.mm` case fails, because `@import` then needs `-fcxx-modules`.
- **Import UIKit before the generated header in a `.mm` file.** The header reaches for its types with `@import UIKit`, and ObjC++ has modules off by default, so the other order produces a wall of `unknown type name 'UIView'`.

**An app target with no Swift sources of its own can fail to link when the Metal Toolchain component is installed.** Xcode 26 then resolves `TOOLCHAIN_DIR` to the Metal toolchain, the Swift library search path CocoaPods derives from it has no `swiftCompatibility56`, and the link stops at `__swift_FORCE_LOAD_$_swiftCompatibility56`. GitHub's macOS 26 runners have that component installed. Build with `TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault` in the environment, as this repository's CI does.

**This pod is not on CocoaPods trunk, deliberately.** Trunk becomes permanently read-only on 2 December 2026, after which it accepts no new versions even for pods already published, so publishing there would freeze this package at whatever version made the deadline. A `:git` dependency is outside trunk and unaffected.

### Objective-C projects: drop in the sources

Drag the whole `Sources/Tero/` folder into your app target, then, in a `.m` or `.h`:

~~~objc
#import "YourAppModule-Swift.h"
~~~

where `YourAppModule` is your app target's product module name.

**When you check what the generated header exposes, read the right one.** DerivedData holds several `<App>-Swift.h` files, and only the one under `Build/Intermediates.noindex/<App>.build/<Config>-<sdk>/` comes from the build you just ran — the copy under `Index.noindex/` is the indexer's, and others can be left over from earlier builds. One app's first look found a stale 376-line copy with none of Tero's types in it and nearly concluded the source drop had failed; the current one had 1,227 lines.

**Which of the two?** The pod gives you a versioned dependency and a module boundary, so `internal` actually means internal. Source drop puts the sources in your own target, which means `internal` offers no protection but nothing needs installing. Both are measured to work from `.m`, `.h` and `.mm`; importing a Swift *package* into a traditional Xcode target is the one path that has not been verified here.

## Usage

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

// Selecting returns whether it happened. It is @discardableResult, so nothing warns you.
let switched = tabController.selectTab(withIdentifier: "profile", animated: true)
~~~

**`selectTab` returns `Bool`, and ignoring it is silent.** It returns `false` when the delegate's `shouldSelect` refuses, when no tab has that identifier, or when the tab is disabled. Deep links and push notifications are where this bites: you switch, something refuses, and the code carries on believing the user is somewhere they are not. Check the result on any path where the destination is not under your control.

`selectedIndex` and `selectedTab` are KVO-observable, so you can watch them instead of tracking the delegate yourself.

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

`[TeroTabBadge dotBadge]` and `[TeroTabBadge badgeWithValue:@"3"]` are the Objective-C forms of the Swift factories `.dot()` and `.value(_:)`.

### Custom tab content

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
        // animated == false may mean the user turned on Reduce Motion
        if selected && animated { view.play() } else { view.stop() }
    }
}

item.contentProvider = LottieTabProvider()   // the item holds it strongly
~~~

Receiving only `selected: Bool` cannot produce "the capsule is halfway across, so the animation is halfway through". Adopt the advanced protocol when you need continuous progress — existing providers are unaffected:

~~~swift
extension LottieTabProvider: TeroTabInteractiveContentProvider {
    func updateContentView(_ contentView: UIView, selectionProgress: CGFloat, animated: Bool) {
        guard let view = contentView as? LottieAnimationView else { return }
        view.currentProgress = selectionProgress   // the animation goes where the selection goes
    }
}
~~~

Progress arrives from two sources: every frame of a selection transition, and every finger sample while `swipeSelectionMode = .drag` is being dragged. A transition is guaranteed to end on exactly `0.0` or `1.0`; an interrupted one continues from the current value rather than jumping. During a drag, `animated` is always `false` — each callback is where the finger is now, not an animation, so apply the progress directly.

### The selection capsule

The bar has one capsule that moves between tabs, rather than a background owned by each slot. It is shown by default under FloatingGlass and hidden under Classic, since a full-width native tab bar has no such outline:

~~~swift
configuration.itemAppearance.selectionIndicatorStyle = .automatic     // default
configuration.itemAppearance.selectionIndicatorMaterial = .automatic  // solid at rest; under FloatingGlass a lens appears while it moves, including during a .drag
configuration.itemAppearance.selectionIndicatorCornerRadius = nil     // nil = capsule

// per-item size; .zero derives it from the slot via selectionIndicatorInsets
tab.item.selectionSize = CGSize(width: 60, height: 40)
~~~

There are two colour values because the two materials need contrast in **opposite directions**: `selectionIndicatorColor` fills the solid shape, `selectionIndicatorGlassTint` tints the glass. A glass tint is absorbed by the host material, and in light mode a white tint will not surface at any opacity, so it defaults to darker in light mode and lighter in dark mode. Set both to the same value if you want one colour.

**`selectionIndicatorColor`'s default assumes the host capsule is not light.** Turn `floatingGlassAppearance.glassTintColor` light — 70% white, say — and you get white on white: one shipping app measured an average colour difference of 13.3 between capsule and host, which reads as a single smear; the same layout with a 30% neutral grey measured 26.3, double the contrast and without reaching for glass. **When you lighten the host tint, adjust `selectionIndicatorColor` with it.** This is the same reasoning as the glass tint above, pointing the other way.

### Transition motion

~~~swift
configuration.motion.selectionResponse = 0.4          // spring response; nil falls back to selectionDuration
configuration.motion.selectionDampingRatio = 0.84     // 1.0 does not overshoot; lower overshoots more
configuration.motion.minimizeDuration = 0.28          // collapsing
configuration.motion.restoreDuration = 0.22           // restoring
configuration.motion.reselectDuration = 0.28          // feedback on re-tap
configuration.motion.contentTransitionDuration = 0.3  // icon handover
configuration.motion.allowsInterruptibleTransition = true
configuration.motion.reduceMotionBehavior = .crossFade
~~~

`allowsInterruptibleTransition` is on by default: a new selection mid-transition turns **from where the capsule is on screen**. Turning it off restores the queued behaviour of letting the current segment finish first.

With Reduce Motion on, there is no spring displacement — every animation inside the package counts as off — but the selection state is kept and the travelling lens is disabled. The fallback is chosen by `reduceMotionBehavior` (`.crossFade` or `.instant`).

### Swipe selection

Off by default; pick one of two modes:

~~~swift
configuration.swipeSelectionMode = .drag    // the capsule follows your finger and settles on the nearest tab
configuration.swipeSelectionMode = .swipe   // flick left or right to move to the adjacent tab
~~~

**`.drag` needs a visible selection capsule**, because that capsule is what you are dragging. Classic hides it by default, so using `.drag` under Classic also requires `selectionIndicatorStyle = .always`, or pressing does nothing. `.swipe` has no such requirement.

Swiping acts on the tabs capsule only — an action item sits outside it and does not take part. A swipe-driven selection has source `.user` and goes through `shouldSelect` like any other; a rejected one springs back. Settling on More springs back too: the gesture means "choose a tab", not "open the menu".

### Long press

Implement the optional delegate method and pressing a tab for half a second reports it — Instagram's press-and-hold on the profile tab to switch accounts:

~~~swift
func teroTabBarController(_ tabController: TeroTabBarController, didLongPress tab: TeroTab) {
    presentAccountSwitcher(for: tab)
}
~~~

The recogniser is only installed while the delegate implements the method; More and action items never report it, and a recognised press cancels the tap so the tab is not also selected. **`.drag` and long press are mutually exclusive**: drag is driven by a zero-duration long press that takes the touch from touch-down, so no long-press events are delivered while `swipeSelectionMode == .drag`.

### Scroll-driven collapse

The screen on display decides whether it wants to be tracked:

~~~swift
extension FeedViewController: TeroScrollProviding, TeroTabBarScrollBehaviorProviding {
    // the shared input: top chrome and the bottom tab bar read the same samples
    var teroTrackingScrollView: UIScrollView? { tableView }
    // the tab bar's own preference
    var preferredTeroTabBarScrollBehavior: TeroTabBarScrollBehavior { .minimizeOnScrollDown }
}
~~~

The two protocols are deliberately separate: the scroll **input** is shared, while each side decides its own reaction. Adopt only `TeroScrollProviding` if you want to supply the input without stating a preference.

`.none` is the **preference** "this screen should not react to scrolling"; `.inherit` means **no preference**, deferring to the configuration. Leave the member unimplemented, or return `.inherit`, when you have nothing to say — a container forwarding a child's preference upward must use the latter, because an `@objc optional` member always "responds" once it is declared.

**Minimized has two layouts.** The default `.uniform` scales the whole bar down and keeps every tab — one uniform scale, width and height by the same ratio, so the selection capsule always fits its slot; `floatingGlassAppearance.minimizedHeight` sets the size and the width follows. `.selectedOnly` collapses the bar into a small capsule around the selected tab — the form iOS 26's own tab bar takes when it minimizes — and tapping that capsule expands the bar again without changing the selection:

~~~swift
configuration.floatingGlassAppearance.minimizedLayout = .selectedOnly
~~~

Only one tab is on screen in that state, so `.drag` does nothing while a `.selectedOnly` bar is minimized. Whether `.selectedOnly` should become the default is a device comparison against the system's own bar; until then `.uniform` stays.

### Per-screen policy and navigation sync

~~~swift
extension DetailViewController: TeroTabVisibilityProviding {
    var preferredTeroTabVisibilityPolicy: TeroTabVisibilityPolicy { .hidden }
}

// Put this in the app's existing UINavigationControllerDelegate; no delegate needs replacing.
func navigationController(_ navigationController: UINavigationController,
                          willShow viewController: UIViewController,
                          animated: Bool) {
    tabController.coordinateNavigationTransition(
        navigationController, to: viewController, animated: animated
    )
}
~~~

A policy is `.inherit` (defer to scrolling), `.expanded` or `.hidden`. A navigation preview changes no public state: it commits on completion and restores the source on cancellation. A custom container that is not wired up can call `refreshScrollTracking()` to re-resolve, but will not get interactive-pop synchronisation.

A programmatic `setTabBarPresentationState(.hidden, animated:)` still wins, and only `.expanded` unlocks it. A screen's own hidden policy belongs to that screen and establishes no global lock.

### Per-screen bar appearance

A screen can also say which interface style the tab bar should use while it is on display. Instagram's Reels tab turns the bar black while the other tabs keep it light:

~~~swift
extension ReelsViewController: TeroTabBarAppearanceProviding {
    var preferredTeroTabBarUserInterfaceStyle: UIUserInterfaceStyle { .dark }
}
~~~

The bar's `overrideUserInterfaceStyle` follows the visible screen, so its dynamic colours and its blur or glass material flip with it. `.unspecified`, or not adopting the protocol, means "follow the system". It resolves at the same points as the visibility policy — on tab switch, when a navigation transition settles, and on `refreshScrollTracking()` — and a `TeroNavigationContainer` forwards its top screen's declaration. The switch is not animated.

**Only the user's scrolling collapses the bar**: setting `contentOffset` programmatically does not trigger a collapse; call `setTabBarPresentationState` to collapse deliberately. Scrolling back to the top programmatically still expands when nothing is locked. `scrollConfiguration.directionLockDistance` defaults to 8pt; a negative value counts as 0 and a non-finite one falls back to the default.

A scroll collapse keeps the expanded safe area, including across rotation. During navigation the source insets are pinned and settled once on completion, and Tero only adds and removes its own inset without overwriting yours. The same applies in reverse: on a view controller Tero manages, **add to** `additionalSafeAreaInsets` rather than **assigning** it — assigning wipes out the space the container reserved for you.

### Collapse progress for custom content

~~~swift
func updateContentView(_ contentView: UIView,
                       presentationProgress: CGFloat,
                       animated: Bool) {
    // 0 = expanded, 1 = minimized; hidden is handled by the existing presentationState callback.
    contentView.alpha = 1 - presentationProgress * 0.15
}
~~~

This optional callback belongs to the existing `TeroTabInteractiveContentProvider` and action items receive it too; older providers need no changes. Reduce Motion, and anything unanimated, receives the endpoints directly. Selection and presentation progress can update at the same time, so avoid letting both drive the same animation cursor.

## Navigation container

`TeroNavigationContainer` is a hand-built stack container. It is not a subclass of `UINavigationController` and does not aim to be API-compatible with one: `UINavigationBar`'s layout is not frozen into this package's public API, and top chrome comes entirely from the screen.

~~~swift
let container = TeroNavigationContainer(rootViewController: FeedViewController())

container.pushViewController(DetailViewController(), animated: true)
container.popViewController(animated: true)
container.popToRootViewController(animated: true)
container.setViewControllers([a, b, c], animated: false)

container.topViewController   // the top one
container.viewControllers     // bottom to top
~~~

Putting one in a tab:

~~~swift
let tab = TeroTab(
    identifier: "feed",
    viewController: container,
    item: TeroTabItem(title: "Feed", image: UIImage(systemName: "house"), selectedImage: nil)
)
~~~

Each tab keeps its own stack, and switching away and back does not reset it.

A screen reaches its container through `teroNavigationContainer`, the counterpart of `navigationController` (which is `nil` inside a Tero hierarchy): the nearest `TeroNavigationContainer` up the `parent` chain.

~~~swift
teroNavigationContainer?.pushViewController(DetailViewController(), animated: true)
~~~

It is computed and holds nothing, and it already works inside `makeTeroNavigationChromeView()`. A screen that `setViewControllers(_:animated:)` places below the top is not a child until it is first shown, and sees `nil` until then.

**Stack changes are synchronous**: `viewControllers` and `topViewController` hold the new values before the method returns, and the animation is only the picture catching up. Send another change mid-transition and the running segment settles to its own endpoint immediately while the new one starts from a clean hierarchy — nothing is dropped and nothing queues. Dropping would leave a child that never received `didMove(toParent:)`.

Interactive pop is the one exception: it does not commit until the finish threshold is met, so cancelling leaves the stack untouched.

~~~swift
container.isInteractivePopGestureEnabled = false   // on by default
~~~

### Observing stack changes

~~~swift
container.delegate = self

func teroNavigationContainer(_ container: TeroNavigationContainer,
                             willShow viewController: UIViewController,
                             animated: Bool) { }

func teroNavigationContainer(_ container: TeroNavigationContainer,
                             didShow viewController: UIViewController,
                             animated: Bool) { }
~~~

`willShow` fires at **commit**: `viewControllers` already holds the new value and `pushViewController` has not returned. `didShow` fires at **settle**: the picture has caught up with the stack.

**A cancelled interactive pop fires neither.** It never commits, so the stack never changed — firing would report a transition that did not happen. That matters for impression tracking.

### Top chrome

Tero's contract for chrome has two parts: **a `UIView`**, and **a 0…1 collapse progress**. Whether it contains a title, how many regions it has, how it lays them out — Tero knows none of it.

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

Four rules produce correct chrome:

1. **The height excludes the safe area.** You declare the chrome's own content height, and the container adds its own safe area for the status bar. So `TeroNavigationBar.primaryHeight` (44) is the right value for a single title row: you neither need nor want to add the status bar height, which varies by device.
2. **The height is a setting, not a measurement.** Tero never calls `systemLayoutSizeFitting` or reads `intrinsicContentSize`. You give two endpoints and Tero interpolates between them. The height is read once, when the view controller enters the container hierarchy.
3. **Chrome views should be translucent.** Content scrolls underneath, and a solid fill hides that relationship. `TeroNavigationBar` uses a `UIBlurEffect` by default and only switches to solid when Reduce Transparency is on; custom chrome should do the same.

   On iOS 26 the container installs a `.top` `UIScrollEdgeElementContainerInteraction` (the bottom tab bar installs the symmetric `.bottom`), tracking whatever the screen returns from `teroTrackingScrollView`. Either interaction exists only while there is a scroll view to track; an idle one is removed, because it is not free — it changes colour resolution inside its container, and on the tab bar it made iOS 26's observation tracking report a feedback loop on every layout. **It does take hold, in a way that matters for opaque chrome**: inside that container, dynamic system colours resolve to their bar variants — on the iOS 26 simulator `systemBackground` renders as (245, 245, 245) rather than white, while fixed colours such as `.white` are untouched. A chrome that must match the content exactly, like an Instagram-style white header, should turn the effect off with `container.isScrollEdgeEffectEnabled = false` or use a fixed colour. Whether the soft edge itself shows on a translucent chrome still needs a device check; do any edge treatment you depend on in the chrome view yourself.
4. **A chrome view must not hold the container strongly.** The container holds the screen, the screen holds the chrome view, and a strong reference back to the container closes the cycle. To push or pop from chrome, capture `[weak self]` and go through `teroNavigationContainer`, which holds nothing.

**Chrome takes part in the transition.** During an animated push or pop both screens' chrome sit in the container: the outgoing one fades out, the incoming one fades in, and the chrome height interpolates between the two declared heights, all in the same animator as the content. During an interactive pop they follow the finger, and a cancelled gesture puts the outgoing chrome back. The reserved inset still switches at commit, so the incoming screen lays out with its own height from the first frame.

### Collapsing

Implement the optional collapse endpoint and callback and the chrome collapses as you scroll:

~~~swift
var teroNavigationChromeCollapsedHeight: CGFloat { 52 }

func updateTeroNavigationChrome(_ chromeView: UIView, collapseProgress: CGFloat) {
    (chromeView as? TeroNavigationBar)?.applyCollapseProgress(collapseProgress)
}
~~~

`TeroNavigationBar` collapses by fading the primary row out while the secondary row takes over the height it gives up. For a different collapse, write your own chrome view; nothing in Tero needs changing.

How far you have to scroll, and whether the chrome reacts at all, are settings on the container:

~~~swift
container.chromeCollapseDistance = 96     // points of downward scrolling to collapse fully; default 120
container.chromeScrollBehavior = .fixed   // .hidePrimary (default) collapses on scroll; .fixed never does
~~~

A header that should finish collapsing within its own height, the way Instagram's does, sets the distance to the chrome's expanded height. These are separate from the tab bar's `TeroTabBarScrollBehavior`: the same downward scroll can collapse the top chrome and leave the bar alone.

The screen also has to hand over its scroll view for Tero to have any input, and Tero will not replace your `delegate`:

~~~swift
extension FeedViewController: TeroScrollProviding {
    var teroTrackingScrollView: UIScrollView? { tableView }
}
~~~

Where the samples come from depends on where the container sits. Under a `TeroTabBarController` they arrive from the tab bar's tracking path, so the top chrome and the bar read the same samples; a `TeroNavigationContainer` used **on its own** — a modal flow, an onboarding stack — tracks the page's scroll view itself. The two paths are exclusive, so no scroll view is ever observed twice.

### Primary and secondary

`TeroNavigationBar` is internally two-part: primary is the title row, secondary is any view hung beneath it. That structure lives inside the navigation bar and is not part of the public API.

~~~swift
let bar = TeroNavigationBar(frame: .zero)
bar.title = "Profile"
bar.leadingItems = [TeroNavigationButton(image: UIImage(systemName: "chevron.left"))]
bar.trailingItems = [TeroNavigationButton(image: UIImage(systemName: "plus"), material: .glass)]
bar.secondaryView = categoryRow
~~~

The height with both parts is `TeroNavigationBar.primaryHeight + <secondary height>`, and the collapsed value is the secondary part alone.

### Button material

`TeroNavigationButton` draws either a plain glyph or an iOS 26 glass capsule. `.automatic` follows the nearest `TeroTabBarController`'s effective style — glass under FloatingGlass, plain under Classic or on iOS 15–25, and plain when the container is used on its own — so "Liquid Glass or not" stays one decision, `configuration.style`:

~~~swift
bar.trailingItems = [TeroNavigationButton(image: UIImage(systemName: "plus"), material: .automatic)]
~~~

The default is still `.plain`. Resolution happens when the button enters a window; the style cannot change at runtime, so nothing is recomputed later.

Buttons the mirror builds from a `UIBarButtonItem` (see [Mirroring a `UINavigationItem`](#mirroring-a-uinavigationitem)) are out of your reach, so the bar decides their material instead — for a FloatingGlass tab bar with plain navigation buttons, say:

~~~swift
bar.defaultButtonMaterial = .plain   // default .automatic
~~~

It applies to every button on the bar whose material is still `.automatic` — when you set it, and again whenever the bar's items change — and leaves alone any you set to `.plain` or `.glass`. It converts those buttons rather than following them, so setting it back to `.automatic` does not restore the ones it already changed.

### Title appearance

~~~swift
bar.titleColor = .white                                   // nil uses .label
bar.titleFont = .systemFont(ofSize: 22, weight: .bold)    // nil uses .headline
bar.titleView = twoLineHeader                             // replaces the text title when set
bar.showsBackdrop = false                                 // draw your own background
bar.buttonTitleColor = .white                             // nil uses .label
~~~

All of these behave exactly as if unset while they are `nil` or at their default.

**`buttonTitleColor` colours the bar's text buttons**, which `tintColor` cannot reach — it does not apply to a `UIButton`'s text. Without it a dark or coloured bar has no way at all to lighten them, and buttons mirrored from a `UIBarButtonItem` are the worst case, since the caller never gets a reference to them. The disabled colour follows it, because a hardcoded `.tertiaryLabel` is just as invisible on a dark bar. A button whose title colour you set yourself is left alone; icon buttons follow `tintColor` as before.

**Specifying `titleFont` opts out of Dynamic Type** — the property exists to reproduce a fixed size from an existing design. Wrap it yourself if you want both:

~~~swift
bar.titleFont = UIFontMetrics(forTextStyle: .headline)
    .scaledFont(for: .systemFont(ofSize: 22, weight: .bold))
~~~

**A `titleView` has to state its own size.** Tero calls neither `sizeThatFits(_:)` nor `intrinsicContentSize` — sizes are settings, not measurements — so a view brought over from the `frame` world, such as a hand-drawn label, needs its own width and height constraints, with a low horizontal compression resistance so it does not fight the two constraints that keep the side controls clear. The same holds for anything you put in `leadingItems` or `trailingItems`, which are stack views.

**A disabled `customView` dims twice.** Tero applies `alpha = 0.35` to the view itself, and your own disabled title colour applies on top of that — a colour at 40% alpha inside a view at 35% ends up around 14%, which is very faint. Buttons the mirror builds itself do not stack: they only take the disabled title colour. If a custom view reads too pale when disabled, raise the alpha of your own disabled colour and let Tero's 0.35 do the work alone.

A `UIBarButtonItem`'s `customView` is the exception, and deliberately so. You handed that view to UIKit, where a frame-based one works, and never agreed to this contract — the mirror is what moves it into Auto Layout, so the mirror pins its measured size for you (at `.defaultHigh`, so a narrow screen shrinks it rather than breaking). A custom view that already uses Auto Layout is left to its own constraints.

### Mirroring a `UINavigationItem`

Screens that already describe their bar through `navigationItem` do not have to be rewritten. Bind the item and the bar mirrors it, then keeps following it through KVO:

~~~swift
extension ProfileViewController: TeroNavigationChromeProviding {
    func makeTeroNavigationChromeView() -> UIView {
        let bar = TeroNavigationBar(frame: .zero)
        bar.bind(to: navigationItem, backAction: { [weak self] in
            self?.teroNavigationContainer?.popViewController(animated: true)   // weak: the chrome belongs to this screen
        })
        return bar
    }
    var teroNavigationChromeHeight: CGFloat { TeroNavigationBar.primaryHeight }
}
~~~

`title`, `titleView`, `leftBarButtonItems`, `rightBarButtonItems`, `hidesBackButton` and `leftItemsSupplementBackButton` are mirrored, and every `UIBarButtonItem`'s `isEnabled`, `title`, `image` and `tintColor` are watched afterwards, so screens that swap buttons at runtime keep working. A `UIBarButtonItem` becomes a `TeroNavigationButton` with the bar's `defaultButtonMaterial` and UIKit's sizes — 17pt regular for `.plain`, 17pt semibold for `.done` — and keeps its target-action, `primaryAction` and `menu`; a `customView` is used as is. An image whose rendering mode is `.automatic` is drawn as a template and takes the bar's tint, as it does in `UINavigationBar`; use `.alwaysOriginal` to keep its colours. A `TeroNavigationButton` you create yourself is a plain `UIButton` and keeps an `.automatic` image's own colours, so pass a template image or an SF Symbol there when you want the tint. A text button also takes the item's own `titleTextAttributes`, and they win over the bar's defaults: the colours for the normal and disabled states beat `buttonTitleColor`, and the normal state's font replaces the 17pt default. A back button is synthesised when you pass a `backAction`, there is a screen to go back to, the item does not hide its back button, and there are no left items (or they supplement it), which is how UIKit decides too. Inside a `TeroNavigationContainer` the container answers the second condition and keeps it current as the stack changes — so the root never shows one, and every screen can pass the same `backAction`. Pass `nil` to unbind. Objective-C: `-bindToNavigationItem:backAction:`.

**System items come out empty.** `UIBarButtonItem(barButtonSystemItem:)` — done, cancel, add — has no title, image or custom view, and UIKit has no public way to read which system item it is, so the mirror can only draw an empty button. Debug builds stop on an assertion when that happens; Release builds show the empty button. Give those items an explicit title or image.

This is not a `UINavigationController` compatibility layer: there is no fake `navigationBar` and nothing is cast. It covers what `navigationItem` expresses; bar-level appearance still goes through `TeroNavigationBar`'s own properties.

## Configuration

`TeroTabBarConfiguration` is the only entry point for configuration. The controller takes a **deep copy** at initialisation and again on `applyConfiguration(_:animated:)`, so mutating your original object afterwards has no effect on it.

Read the current configuration with `currentConfiguration()` — a **method** rather than a property, because what comes back is a snapshot: changing it does nothing until you call `applyConfiguration`.

| Group | What it holds | Objective-C |
|---|---|---|
| `style` | Classic or FloatingGlass | ✅ |
| `compact` / `regular` | the visible-item limit for each (including More, excluding the action slot) | ✅ |
| `normalTintColor` / `selectedTintColor` | tint colours (forwarded to `itemAppearance`) | ✅ |
| `morePresentationStyle` / `moreItem` | how More is presented, and its appearance | ✅ |
| `itemAppearance` / `badgeAppearance` | item and badge detail | Swift only |
| `classicAppearance` / `floatingGlassAppearance` | per-style detail | ✅ (see below) |
| `scrollConfiguration` | scroll behaviour and thresholds | ✅ (see below) |
| `motion` | transition durations, springs and fallbacks | ✅ (see below) |
| `swipeSelectionMode` | how swipe selection works | ✅ |

`motion`, `scrollConfiguration`, `classicAppearance` and `floatingGlassAppearance` are Swift-only value types; Objective-C reaches them through prefixed forwarding properties on `TeroTabBarConfiguration` — ten `motion*`, five `scroll*`, seven `classic*` and thirteen `floatingGlass*`, one per field:

~~~objc
configuration.motionSelectionDuration = 0.5;
configuration.motionSelectionDampingRatio = 0.9;
configuration.motionReduceMotionBehavior = TeroTabReduceMotionBehaviorInstant;

// selectionResponse is Optional in Swift; in Objective-C 0 means "unspecified",
// so use motionSelectionDuration together with motionSelectionDampingRatio.
configuration.motionSelectionResponse = 0;

configuration.scrollBehavior = TeroTabBarScrollBehaviorHideOnScrollDown;
configuration.classicBarHeight = 52;
configuration.classicUsesBlurEffect = NO;
configuration.floatingGlassBottomInset = 21;
configuration.floatingGlassTintMode = TeroTabGlassTintModeTinted;
configuration.floatingGlassTintColor = UIColor.systemPinkColor;
~~~

`itemAppearance` and `badgeAppearance` have no forwarding entry point beyond the two tint colours. When you need that detail from Objective-C, build the `TeroTabBarConfiguration` on the Swift side and hand it over.

**`floatingGlassAppearance.bottomInset` is measured from the screen edge**, not stacked on top of the safe area, and its default of 21 puts the bar where the system's own floating tab bar sits. The inset that child screens clear follows it: the part of the bar inside the home indicator band is already in the window's own safe area and is not counted twice.

## Development

Run this before merging; it runs the same commands as the five CI jobs:

~~~bash
./Scripts/verify-local.sh
~~~

CI (`.github/workflows/ci.yml`) runs those five jobs on every push to `main` and on every pull request. Pushes to a fork do not trigger it; to run it there, start it from the Actions tab with Run workflow.

Individual commands:

~~~bash
# tests — the destination must be an iOS 26+ simulator, resolved to a UDID
xcodebuild test -scheme Tero \
  -destination "$(./Scripts/resolve-simulator.sh)"

# Swift demo
cd Demo/SwiftDemo && xcodegen generate && open SwiftDemo.xcodeproj

# Objective-C demo (source drop)
cd Demo/ObjCDemo && xcodegen generate && open ObjCDemo.xcodeproj

# guard: the package must contain no resource files
./Scripts/check-no-resources.sh

# guard: public API and Objective-C interface diff
./Scripts/check-public-api.sh
~~~

`Scripts/resolve-simulator.sh` picks the simulator. It always resolves to a UDID, because passing a name to `xcodebuild` fails on some machines even when the device exists, is available and is already booted. It also refuses anything below iOS 26: FloatingGlass does not exist there, and the 71 tests guarded by `XCTSkipUnless(isFloatingAvailable)` would all skip while the run still reported no failures. Choose a model with `TERO_DEVICE`, or pass a full destination as the first argument to `verify-local.sh`.

Demo project files are generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen); the repository keeps only `project.yml`.

The demos accept launch arguments so screenshots can be automated: `--badges`, `--many-tabs`, `--style=floatingGlass`, `--state=minimized`, `--scrolled=300`, `--swipe=drag`, `--reset-settings`, `--instagram`.

**Settings persist across launches.** The Interaction Lab's motion preset, tab count, gesture mode and seven slider values, along with the main screen's swipe mode and style, are written to `UserDefaults` so you do not have to dial them in again. Three rules:

- **Launch arguments win over saved settings**, and are not written back — automated screenshots have to be deterministic and must not inherit the last manual session.
- **Style only takes effect on the next launch.** It cannot be switched at runtime (see [Known limitations](#known-limitations)), so the main screen's `Style↻` button only updates the saved value. This is also the only way to switch style without launch arguments.
- To get back to a clean slate: the `清除設定` (reset settings) button on the main screen, or launch with `--reset-settings`.

Persistence lives in the demos only. The package never touches `UserDefaults` — a configuration's lifetime is the app's business, which is also why `TeroTabBarConfiguration` is a deep-copied snapshot rather than something that remembers state.

**The Interaction Lab** (`--lab`, or the `Lab` button) adjusts duration, damping, response, selection size, corner radius and icon scale live on the device, and switches between the Static / Slide / Fluid / Spring presets, 3–6 tabs, and tap / drag / flick. These can only be judged by eye: a unit test can prove a transition is interruptible, not which set of numbers feels the way you want.

Four reference cases (`--case=a` … `--case=d`, or the `A`/`B`/`C`/`D` buttons):

| | Focus |
|---|---|
| A | dark background, one capsule sliding smoothly, icons transitioning with it |
| B | Lottie content plus badges on a light background, animation synchronised to selection progress |
| C | a shifting colourful backdrop with glass reacting to it, and a different selection size per slot |
| D | a `999+` badge, a dot badge, and a standalone search action |

**The Instagram reference case** (`--instagram`, or `Nav` → `Instagram`) builds an Instagram-shaped app out of the primitives: five icon-only tabs on an opaque Classic bar, the centre "+" as an action item, an avatar tab drawn by a content provider with a ring that follows selection progress, instant icon swaps (`contentTransitionDuration = 0`), a Home header that slides away within its own height and comes back, tap-again-to-scroll-to-top, a Reels tab that turns the bar dark, a profile tab whose segment row stays while the title collapses, and press-and-hold on the profile tab for the account switcher. Each tab is its own `TeroNavigationContainer`.

When the public API changes on purpose, regenerate the baselines and say so in the commit message:

~~~bash
./Scripts/extract-swift-api.sh > Scripts/api/swift-api-baseline.txt
./Scripts/extract-objc-interface.sh > Scripts/api/objc-interface-baseline.txt
~~~

## Known limitations

**Dynamic Type is only partly followed.** Tab item captions and `TeroNavigationBar` titles scale with the text size; other appearance fonts and content sizes are fixed. That is a deliberate trade-off, not a bug.

If your custom chrome's declared height changes with the text size, the container recomputes it when the text size changes. When you change the chrome's structure yourself — a new title, a secondary row appearing or disappearing — call `setNeedsChromeGeometryUpdate()`.

**Custom back gestures are not supported.** The interactive pop's driving entry point is not public, and 2.0 offers only Tero's own edge gesture. When you need gesture arbitration, because a screen has horizontally scrolling content along its leading edge, `interactivePopGestureRecognizer` hands you the recogniser:

~~~swift
carousel.panGestureRecognizer.require(toFail: container.interactivePopGestureRecognizer)
~~~

**Custom transitions are not supported.** The transition style — push, pull and parallax — is fixed, and only `transitionDuration` is adjustable. A custom transition protocol is out of scope for 2.0.

Two effects are still within reach without one; both were checked on the iOS 26.5 simulator.

- **A cross-fade.** Wrap a stack change without animation in a view transition:

  ~~~swift
  UIView.transition(with: container.view, duration: 0.3, options: .transitionCrossDissolve) {
      container.pushViewController(detail, animated: false)
  }
  ~~~

  It works because a change without animation completes before the method returns, views included, so it happens inside the block. The content and both screens' chrome fade. The lifecycle calls and the delegate report `animated: false`. Going back is still the push-and-pull slide, edge gesture included; wrap `popViewController(animated: false)` the same way to fade a back button's pop. A tab bar that the new screen hides or shows does not fade: it slides for the length of the transition.

- **A drop-down menu.** Present it over the current context, with the container as that context:

  ~~~swift
  container.definesPresentationContext = true
  menu.modalPresentationStyle = .overCurrentContext
  present(menu, animated: true)
  ~~~

  A screen's content sits beneath the container's chrome, so a menu scoped to the screen — the screen setting `definesPresentationContext` itself — ends up under the chrome too, in a sheet or not. Scoped to the container, it covers the chrome.

**More has no extension point.** `TeroTabMorePresentationStyle` offers only its built-in presentations and does not take a custom container.

**There is no FloatingGlass below iOS 26.** The effective style always falls back to Classic, so there is no scroll minimisation on those versions either. **The fallback target is "hide", not "do nothing"** — under Classic, `.minimizeOnScrollDown` becomes `.hideOnScrollDown`. To get no reaction at all on older systems, return `.none` from that screen explicitly.

**The package ships no localised strings.** More shows only its icon when given no title, and a `.dot` badge has no underlying value to announce, so VoiceOver wording has to come from you via `badge.accessibilityValue`. This keeps the package out of your app's existing localisation pipeline.

**Storyboards and XIBs are not supported.** Programmatic initialisation only; `init(coder:)` is marked unavailable.

**Style cannot be switched at runtime.** `applyConfiguration` ignores the `style` field.

**With the Objective-C source drop, `internal` offers no real protection.** The sources share a module with your app, so the package's internal types are visible and mutable from your code. Depend on the public API anyway, or future refactoring will break you.

**Lottie cannot be used directly from Objective-C** (Lottie 4.x is pure Swift). Add a Swift adapter file in the same target if you need it.

**The glass capsule is subdued over light content.** A glass tint is absorbed by the host material, so contrast over light content is limited by nature — the floating tab bars this follows all sit on dark backgrounds, and "brighter than the bar" only holds there. Set `selectionIndicatorMaterial` to `.solid` when you need a stronger distinction.

### Migrating from `UINavigationController`

`TeroNavigationContainer` is **not** a subclass of `UINavigationController`, so `self.navigationController` is `nil` inside a Tero hierarchy; `teroNavigationContainer` is its counterpart. Tero **provides no compatibility layer**; the reasoning is below.

The common move is a shim on the consumer side that casts the container to `UINavigationController *` and fills in the missing members with a category. That road has two pits, both of them stepped in for real:

**One: an Objective-C category silently overrides a member the package already provides.** Someone shimmed `interactivePopGestureRecognizer` to return `nil`, while `TeroNavigationContainer` already had that property and returned the real recogniser. The category won, and four call sites that turned off swipe-to-go-back failed silently — the gesture stayed on the whole time. **Check here before you shim anything.**

**And check again every time you update Tero.** A shim written before the package had a member turns into an override once it does. The same app later found two more: `delegate`, which left `TeroNavigationContainerDelegate` unusable in that app, and `popToViewController:animated:`. The compiler warns only for protocol methods (`-Wobjc-protocol-method-implementation`); every other case is silent.

**Two: appearance members fail silently no matter how you shim them.** A `navigationBar` that returns a `UINavigationBar` wired to nothing compiles, runs, and does nothing. One migration had 51 such call sites, and **almost every visual regression after the switch came from them** — translucency, shadows, dark backgrounds, title colours and fonts — and not one was found by the compiler or by a test.

Route navigation bar appearance through chrome instead: `TeroNavigationBar`'s `title` / `titleColor` / `titleFont` / `titleView` / `leadingItems` / `trailingItems` / `secondaryView` / `showsBackdrop`, or simply write your own chrome view. Screens that already speak `navigationItem` can keep doing so: `bind(to:backAction:)` mirrors it (see [Mirroring a `UINavigationItem`](#mirroring-a-uinavigationitem)).

**Why Tero does not ship this layer**: the only form it could take is the silent failure above, and the form that would actually help — turning those call sites into compile errors that name the replacement — is not something Tero can do, since the cast is the consumer's, on a UIKit type the package cannot reach. Putting the layer behind a global switch is worse: whether appearance takes effect would then vary with build settings, and appearance failures are the hardest kind to see in code.

**What works better: move the call sites onto an abstraction of your own first.** Another shipping app — about 600 `.m` files and 194 view controllers — went the other way at a fraction of the cost. Before touching Tero, it added a `UIViewController` category of its own (`navigationStack`, `tabBarHost`) that for now just forwards to UIKit, and renamed 92 `.navigationController` and 24 `.tabBarController` call sites to it. That step changes no behaviour and can be verified on its own; adopting Tero then only changes the category's implementation. The difference is whose type it is: a shim casts Tero to UIKit's `UINavigationController *`, so every mismatch fails silently at run time, while with your own type the compiler points at each one.

The container's own responsibilities are a different matter, and Tero provides all of them: `pushViewController` / `popViewController` / `popToViewController` / `popToRootViewController` / `setViewControllers` / `topViewController` / `viewControllers` / `interactivePopGestureRecognizer` / `isInteractivePopGestureEnabled`, plus `TeroNavigationContainerDelegate`'s `willShow` / `didShow`.

**Three: `contentInsetAdjustmentBehavior = .automatic` loses a clause.** It is defined as "the same as `.scrollableAxes`, **plus**: always adjust the top inset inside a view controller managed by a `UINavigationController`". `TeroNavigationContainer` is not one, so only `.scrollableAxes` remains — and **when the content does not fill a page, the vertical axis does not count as scrollable and the top inset is zero**, putting full-bleed content underneath the navigation bar. The insidious part is that **pages with a lot of content are fine and pages with little content break**.

The fix is to promote the main scroll view to `.always`. **Promote only the main scroll view; do not sweep the whole tree** — a horizontal pager and the lists inside it see the same safe area, so promoting both applies the inset twice, and changing `contentInset` moves `contentOffset`, while `pagingEnabled` snaps by `bounds.width`. The symptom is pages that land off-centre.

**Four: search for `[UINavigationBar appearance]` first.** Plenty of older projects carry a global `setTranslucent:NO` or similar, which makes every screen's `view` start **below** the navigation bar. Swapping the container removes that premise, and screens that relied on it — especially ones that turned off automatic inset adjustment themselves — shift upwards.

**Five: `scrollsToTop` needs sweeping to exactly one.** UIKit's rule is that when several visible scroll views have `scrollsToTop` on, none of them scrolls. After the switch there is often more than one alive at once — a horizontal pager, a top row, each page's list — and the symptom is that tapping the status bar either does nothing or scrolls the wrong list.

**Six: do not wrap a bottom sheet in a navigation container.** iOS 26 takes over the presentation of a navigation container, so the sheet's corner radius and position stop being your animator's decision — the corners become the system's and your specified height stops applying. Wrapping one just to get a title row is a bad trade; build a plain view for the title row instead.

**Seven: hide the back button with `hidesBackButton`.** Under `UINavigationController`, an empty left item — `initWithTitle:nil target:nil action:nil` — was a common way to hide it. The mirror cannot tell that item from a broken one, so Debug builds stop on the empty-button assertion (see [Mirroring a `UINavigationItem`](#mirroring-a-uinavigationitem)); set `navigationItem.hidesBackButton = YES` instead. Legacy `fixedSpace` and `flexibleSpace` spacers stop there too and can simply be deleted: the bar spaces its own items.

**A suggested order: swap the container first and keep the old look, then change the appearance.** Give navigation buttons the `.automatic` material so they follow the tab bar style: with `.classic` the whole app returns to its previous appearance, letting you confirm that swapping the container caused no regressions; once that is clean, turn on `.floatingGlass`, and every problem you then see is definitely an appearance problem.

## API stability

Minor versions only add API, patch versions only fix bugs, and breaking changes go into the next major version.

**2.1.0 is the one exception so far.** It renames four Objective-C property names to UIKit's `getter=is…` convention — `interactivePopGestureEnabled` and `scrollEdgeEffectEnabled` on `TeroNavigationContainer`, and `enabled` on `TeroTabItem` and `TeroTabActionItem` — while the Swift names stay the same. Reading through the old name still compiles; assigning through it does not, and the compiler names the missing `setIs…:` setter at each call site. The release notes list all four.

**The public surface is pinned by two baselines** under `Scripts/api/`, one for Swift and one for Objective-C. `Scripts/check-public-api.sh` compares every build against them, so any addition or removal turns CI red until the baselines are regenerated on purpose (see [Development](#development)).

## Licence

MIT. See [`LICENSE`](LICENSE).
