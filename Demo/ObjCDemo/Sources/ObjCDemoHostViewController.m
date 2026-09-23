#import "ObjCDemoHostViewController.h"
#import "ObjCNavigationLabViewController.h"
#import "ObjCRotatingProvider.h"
#import "ObjCScrollingFeedViewController.h"
// generated header 只能在 .m 引入
#import "ObjCDemo-Swift.h"

/// Objective-C 的整合示範：建立設定、Tab、Item、Badge，切換、攔截 selection、
/// 以及用 Objective-C 實作 Content Provider。
@interface ObjCDemoHostViewController () <TeroTabBarControllerDelegate>
@property (nonatomic, strong) TeroTabBarController *tabController;
@property (nonatomic, strong) ObjCRotatingProvider *provider;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UITextView *journalView;
@property (nonatomic, strong) NSMutableArray<NSString *> *journal;
@property (nonatomic, assign) BOOL blocksProfile;
@end

@implementation ObjCDemoHostViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.journal = [NSMutableArray array];
    self.provider = [ObjCRotatingProvider new];

    // Objective-C 可調整的設定：style、兩種版面的可見數量上限、主色
    //
    // 預設 Classic：這個 Demo 的主要用途是證明 Classic 從 Objective-C 設定得起來。
    // `--style=floatingGlass`（README 記載的啟動參數）換成浮動玻璃，那是唯一支援
    // minimized 的 Style，也是 `presentationProgress` 回呼唯一會動的情境。
    BOOL wantsFloatingGlass = [NSProcessInfo.processInfo.arguments
        containsObject:@"--style=floatingGlass"];
    TeroTabBarConfiguration *configuration = [TeroTabBarConfiguration defaultConfiguration];
    configuration.style = wantsFloatingGlass
        ? TeroTabBarStyleFloatingGlass
        : TeroTabBarStyleClassic;
    configuration.compact.maximumVisibleItems = 4;
    configuration.regular.maximumVisibleItems = 6;
    configuration.selectedTintColor = UIColor.systemOrangeColor;
    configuration.normalTintColor = UIColor.systemGray2Color;
    // 捲動與兩種外觀的設定從 Objective-C 也拿得到（issue #92）。這裡各動一個，
    // 讓 source drop 這條路徑真的編到那三組轉發屬性，而不只是宣告存在。
    configuration.scrollBehavior = TeroTabBarScrollBehaviorHideOnScrollDown;
    configuration.classicBarHeight = 52;
    configuration.floatingGlassMinimizedHeight = 40;

    self.tabController = [[TeroTabBarController alloc] initWithConfiguration:configuration];
    self.tabController.delegate = self;

    [self addChildViewController:self.tabController];
    self.tabController.view.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tabController.view];
    [self.tabController didMoveToParentViewController:self];

    UIView *controls = [self makeControlPanel];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:controls];

    [NSLayoutConstraint activateConstraints:@[
        [self.tabController.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tabController.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tabController.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tabController.view.bottomAnchor constraintEqualToAnchor:controls.topAnchor],
        [controls.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [controls.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [controls.heightAnchor constraintEqualToConstant:260]
    ]];

    [self installTabs];
}

- (UIView *)makeControlPanel
{
    UIView *container = [UIView new];
    container.backgroundColor = UIColor.secondarySystemBackgroundColor;

    NSArray<NSString *> *titles = @[@"Home", @"Live", @"Profile", @"Settings", @"About"];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[index] forState:UIControlStateNormal];
        button.tag = (NSInteger)index;
        [button addTarget:self action:@selector(selectTapped:) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:button];
    }
    UIStackView *selectRow = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    selectRow.distribution = UIStackViewDistributionFillEqually;

    UIButton *badgeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [badgeButton setTitle:@"Badge" forState:UIControlStateNormal];
    [badgeButton addTarget:self action:@selector(toggleBadges) forControlEvents:UIControlEventTouchUpInside];

    UIButton *blockButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [blockButton setTitle:@"攔截 Profile" forState:UIControlStateNormal];
    [blockButton addTarget:self action:@selector(toggleBlocking) forControlEvents:UIControlEventTouchUpInside];

    UIButton *hideButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [hideButton setTitle:@"隱藏／展開" forState:UIControlStateNormal];
    [hideButton addTarget:self action:@selector(toggleHidden) forControlEvents:UIControlEventTouchUpInside];

    UIButton *navigationButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [navigationButton setTitle:@"Navigation" forState:UIControlStateNormal];
    navigationButton.accessibilityIdentifier = @"objc.open.navigation";
    [navigationButton addTarget:self action:@selector(openNavigationLab) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *actionRow = [[UIStackView alloc] initWithArrangedSubviews:@[badgeButton, blockButton, hideButton]];
    actionRow.distribution = UIStackViewDistributionFillEqually;

    self.stateLabel = [UILabel new];
    self.stateLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    self.stateLabel.numberOfLines = 4;

    self.journalView = [UITextView new];
    self.journalView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.journalView.editable = NO;
    self.journalView.backgroundColor = UIColor.clearColor;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[selectRow, actionRow, navigationButton, self.stateLabel, self.journalView]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:container.safeAreaLayoutGuide.bottomAnchor constant:-8]
    ]];
    return container;
}

- (void)installTabs
{
    NSArray<NSString *> *identifiers = @[@"home", @"live", @"profile", @"settings", @"about"];
    NSArray<NSString *> *titles = @[@"Home", @"Live", @"Profile", @"Settings", @"About"];
    NSArray<NSString *> *symbols = @[@"house", @"dot.radiowaves.left.and.right", @"person.crop.circle", @"gearshape", @"info.circle"];

    NSMutableArray<TeroTab *> *tabs = [NSMutableArray array];
    for (NSUInteger index = 0; index < identifiers.count; index++) {
        // home 用真的會捲動的頁面：它採用 TeroScrollProviding，
        // 讓 source drop 這條路徑也編譯到那個協定。
        UIViewController *content = [identifiers[index] isEqualToString:@"home"]
            ? [ObjCScrollingFeedViewController new]
            : [UIViewController new];
        content.view.backgroundColor = [UIColor colorWithHue:(CGFloat)index / identifiers.count
                                                  saturation:0.12
                                                  brightness:1.0
                                                       alpha:1.0];
        if (![content isKindOfClass:ObjCScrollingFeedViewController.class]) {
            UILabel *label = [UILabel new];
            label.text = titles[index];
            label.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            [content.view addSubview:label];
            [NSLayoutConstraint activateConstraints:@[
                [label.leadingAnchor constraintEqualToAnchor:content.view.safeAreaLayoutGuide.leadingAnchor constant:20],
                [label.topAnchor constraintEqualToAnchor:content.view.safeAreaLayoutGuide.topAnchor constant:20]
            ]];
        }

        TeroTabItem *item = [[TeroTabItem alloc] initWithTitle:titles[index]
                                                        image:[UIImage systemImageNamed:symbols[index]]
                                                selectedImage:nil];
        item.accessibilityIdentifier = [NSString stringWithFormat:@"tab.%@", identifiers[index]];

        // Objective-C 實作的 Content Provider
        if ([identifiers[index] isEqualToString:@"live"]) {
            item.contentProvider = self.provider;
        }

        [tabs addObject:[[TeroTab alloc] initWithIdentifier:identifiers[index]
                                             viewController:content
                                                       item:item]];
    }

    [self.tabController setTabs:tabs selectedIdentifier:@"home" animated:NO];
    [self record:[NSString stringWithFormat:@"setTabs（%lu 個）", (unsigned long)tabs.count]];
    [self refresh];
}

#pragma mark - Actions

- (void)selectTapped:(UIButton *)sender
{
    NSArray<NSString *> *identifiers = @[@"home", @"live", @"profile", @"settings", @"about"];
    NSString *identifier = identifiers[(NSUInteger)sender.tag];
    BOOL accepted = [self.tabController selectTabWithIdentifier:identifier animated:YES];
    [self record:[NSString stringWithFormat:@"selectTab(%@) → %@", identifier, accepted ? @"YES" : @"NO"]];
    [self refresh];
}

- (void)toggleBadges
{
    // Swift 的 `.dot()`／`.value(_:)` 在 Objective-C 是 `+dotBadge`／`+badgeWithValue:`。
    TeroTabBadge *dot = [TeroTabBadge dotBadge];
    dot.accessibilityValue = @"有未讀訊息";

    TeroTabBadge *value = [TeroTabBadge badgeWithValue:@"12"];

    [self.tabController setBadge:dot forTabWithIdentifier:@"live" animated:YES];
    [self.tabController setBadge:value forTabWithIdentifier:@"about" animated:YES];
    [self record:@"setBadge（about 在 More 裡，More 應顯示圓點）"];
    [self refresh];
}

- (void)toggleBlocking
{
    self.blocksProfile = !self.blocksProfile;
    [self record:[NSString stringWithFormat:@"shouldSelect 攔截 Profile：%@", self.blocksProfile ? @"開" : @"關"]];
}

/// 導覽的完整示範另開一個畫面：那裡的每個 Tab 各自一個 `TeroNavigationContainer`。
- (void)openNavigationLab
{
    ObjCNavigationLabViewController *lab = [ObjCNavigationLabViewController new];
    lab.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:lab animated:YES completion:nil];
    [self record:@"present Navigation Lab"];
}

- (void)toggleHidden
{
    TeroTabBarPresentationState next =
        self.tabController.tabBarPresentationState == TeroTabBarPresentationStateHidden
            ? TeroTabBarPresentationStateExpanded
            : TeroTabBarPresentationStateHidden;
    BOOL accepted = [self.tabController setTabBarPresentationState:next animated:YES];
    [self record:[NSString stringWithFormat:@"setPresentationState(%ld) → %@", (long)next, accepted ? @"YES" : @"NO"]];
    [self refresh];
}

#pragma mark - TeroTabBarControllerDelegate

- (BOOL)teroTabBarController:(TeroTabBarController *)tabController
             shouldSelect:(TeroTab *)tab
                   source:(TeroTabSelectionSource)source
{
    if (self.blocksProfile && [tab.identifier isEqualToString:@"profile"]) {
        [self record:@"shouldSelect(profile) → NO（被攔截）"];
        return NO;
    }
    return YES;
}

- (void)teroTabBarController:(TeroTabBarController *)tabController
                didSelect:(TeroTab *)tab
                   source:(TeroTabSelectionSource)source
{
    [self record:[NSString stringWithFormat:@"didSelect(%@, source=%ld)", tab.identifier, (long)source]];
    [self refresh];
}

- (void)teroTabBarController:(TeroTabBarController *)tabController didReselect:(TeroTab *)tab
{
    [self record:[NSString stringWithFormat:@"didReselect(%@)", tab.identifier]];
}

/// 長按只發事件；實作了這個方法，Bar 才會裝辨識器。
- (void)teroTabBarController:(TeroTabBarController *)tabController didLongPress:(TeroTab *)tab
{
    [self record:[NSString stringWithFormat:@"didLongPress(%@)", tab.identifier]];
}

#pragma mark - Helpers

- (void)record:(NSString *)line
{
    [self.journal addObject:line];
    if (self.journal.count > 14) { [self.journal removeObjectAtIndex:0]; }
    self.journalView.text = [self.journal componentsJoinedByString:@"\n"];
}

- (void)refresh
{
    NSString *selected = self.tabController.selectedTab.identifier ?: @"nil";
    self.stateLabel.text = [NSString stringWithFormat:
        @"selectedTab=%@  index=%ld  tabs=%lu\nvisible=%lu  overflow=%lu\nprovider makeContentView 次數=%ld"
        @"\ninteractive: selection=%.2f (%ld 次)  presentation=%.2f",
        selected,
        (long)self.tabController.selectedIndex,
        (unsigned long)self.tabController.tabs.count,
        (unsigned long)self.tabController.visibleTabs.count,
        (unsigned long)self.tabController.overflowTabs.count,
        (long)self.provider.madeContentViewCount,
        self.provider.lastSelectionProgress,
        (long)self.provider.selectionProgressCallbackCount,
        self.provider.lastPresentationProgress];
    self.journalView.text = [self.journal componentsJoinedByString:@"\n"];
}

@end
