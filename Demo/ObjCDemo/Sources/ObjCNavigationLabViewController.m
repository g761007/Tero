#import "ObjCNavigationLabViewController.h"
#import "ObjCCustomChromePage.h"
#import "ObjCNavigationChromePage.h"
#import "ObjCNavigationItemPage.h"
// generated header 只能在 .m 引入
#import "ObjCDemo-Swift.h"

@interface ObjCNavigationLabViewController () <TeroTabBarControllerDelegate>
@property (nonatomic, strong) TeroTabBarController *tabController;
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UITextView *journalView;
@property (nonatomic, strong) NSMutableArray<NSString *> *journal;
@property (nonatomic, assign) NSInteger pushCount;
@end

@implementation ObjCNavigationLabViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.journal = [NSMutableArray array];

    TeroTabBarConfiguration *configuration = [TeroTabBarConfiguration defaultConfiguration];
    // FloatingGlass 才支援 minimized；iOS 26 以下一律降級為 Classic（ADR-0002）。
    configuration.style = TeroTabBarStyleFloatingGlass;

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
        [controls.heightAnchor constraintEqualToConstant:230]
    ]];

    [self.tabController setTabs:[self makeTabs] selectedIdentifier:@"feed" animated:NO];
    [self record:@"setTabs（3 個 TeroNavigationContainer）"];
    [self refresh];
}

#pragma mark - 建構

- (NSArray<TeroTab *> *)makeTabs
{
    NSArray<NSString *> *identifiers = @[@"feed", @"search", @"profile"];
    NSArray<NSString *> *titles = @[@"Feed", @"Search", @"Profile"];
    NSArray<NSString *> *symbols = @[@"house", @"magnifyingglass", @"person.crop.circle"];
    // search 用玻璃材質，讓兩種 Material 都進到編譯覆蓋。
    NSArray<NSNumber *> *materials = @[@(TeroNavigationButtonMaterialPlain),
                                       @(TeroNavigationButtonMaterialGlass),
                                       @(TeroNavigationButtonMaterialPlain)];

    NSMutableArray<TeroTab *> *tabs = [NSMutableArray array];
    for (NSUInteger index = 0; index < identifiers.count; index++) {
        ObjCNavigationChromePage *root = [[ObjCNavigationChromePage alloc]
            initWithPageTitle:titles[index]
                     material:(TeroNavigationButtonMaterial)materials[index].integerValue
                    showsBack:NO];

        TeroNavigationContainer *container =
            [[TeroNavigationContainer alloc] initWithRootViewController:root];
        root.container = container;

        __weak __typeof(self) weakSelf = self;
        __weak TeroNavigationContainer *weakContainer = container;
        root.onPushRequested = ^{ [weakSelf pushDetailInto:weakContainer]; };

        TeroTabItem *item = [[TeroTabItem alloc] initWithTitle:titles[index]
                                                         image:[UIImage systemImageNamed:symbols[index]]
                                                 selectedImage:nil];
        item.accessibilityIdentifier = [NSString stringWithFormat:@"objclab.tab.%@", identifiers[index]];

        [tabs addObject:[[TeroTab alloc] initWithIdentifier:identifiers[index]
                                             viewController:container
                                                       item:item]];
    }
    return tabs;
}

- (UIView *)makeControlPanel
{
    UIView *container = [UIView new];
    container.backgroundColor = UIColor.secondarySystemBackgroundColor;

    UIStackView *stackRow = [self makeRowWithTitles:@[@"Push", @"Pop", @"Root", @"替換 stack"]
                                          selectors:@[[NSValue valueWithPointer:@selector(pushTapped)],
                                                      [NSValue valueWithPointer:@selector(popTapped)],
                                                      [NSValue valueWithPointer:@selector(popToRootTapped)],
                                                      [NSValue valueWithPointer:@selector(setStackTapped)]]];
    UIStackView *miscRow = [self makeRowWithTitles:@[@"邊緣手勢", @"Action", @"Mirror", @"關閉"]
                                         selectors:@[[NSValue valueWithPointer:@selector(toggleGestureTapped)],
                                                     [NSValue valueWithPointer:@selector(toggleActionTapped)],
                                                     [NSValue valueWithPointer:@selector(pushMirrorTapped)],
                                                     [NSValue valueWithPointer:@selector(closeTapped)]]];

    self.stateLabel = [UILabel new];
    self.stateLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightSemibold];
    self.stateLabel.numberOfLines = 3;

    self.journalView = [UITextView new];
    self.journalView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.journalView.editable = NO;
    self.journalView.backgroundColor = UIColor.clearColor;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[stackRow, miscRow, self.stateLabel, self.journalView]];
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

/// selector 包在 `NSValue` 裡而不是字串：`@selector` 還會被編譯器檢查，字串不會。
- (UIStackView *)makeRowWithTitles:(NSArray<NSString *> *)titles selectors:(NSArray<NSValue *> *)selectors
{
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[index] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:13];
        [button addTarget:self
                   action:(SEL)selectors[index].pointerValue
         forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:button];
    }
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:buttons];
    row.distribution = UIStackViewDistributionFillEqually;
    return row;
}

#pragma mark - Stack 操作

/// 目前選取的那一個容器。Tab 的 viewController 就是容器本身。
- (TeroNavigationContainer *)selectedContainer
{
    UIViewController *selected = self.tabController.selectedViewController;
    return [selected isKindOfClass:TeroNavigationContainer.class]
        ? (TeroNavigationContainer *)selected
        : nil;
}

- (void)pushDetailInto:(TeroNavigationContainer *)container
{
    if (container == nil) { return; }
    self.pushCount += 1;
    ObjCCustomChromePage *detail = [[ObjCCustomChromePage alloc]
        initWithPageTitle:[NSString stringWithFormat:@"Detail %ld", (long)self.pushCount]];
    detail.container = container;

    [container pushViewController:detail animated:YES];
    // 陣列在 return 之前就已變更，不等動畫（ADR-0014）。
    [self record:[NSString stringWithFormat:@"push → depth=%lu top=%@",
                  (unsigned long)container.viewControllers.count,
                  [self titleOf:container.topViewController]]];
    [self refresh];
}

- (void)pushTapped { [self pushDetailInto:[self selectedContainer]]; }

- (void)popTapped
{
    TeroNavigationContainer *container = [self selectedContainer];
    UIViewController *removed = [container popViewControllerAnimated:YES];
    [self record:[NSString stringWithFormat:@"pop → 移除 %@，depth=%lu",
                  [self titleOf:removed],
                  (unsigned long)container.viewControllers.count]];
    [self refresh];
}

- (void)popToRootTapped
{
    TeroNavigationContainer *container = [self selectedContainer];
    [container popToRootViewControllerAnimated:YES];
    [self record:[NSString stringWithFormat:@"popToRoot → depth=%lu",
                  (unsigned long)container.viewControllers.count]];
    [self refresh];
}

/// 整組替換：root 之上直接接一頁自訂 chrome，中間不經過 push。
- (void)setStackTapped
{
    TeroNavigationContainer *container = [self selectedContainer];
    UIViewController *root = container.rootViewController;
    if (root == nil) { return; }

    self.pushCount += 1;
    ObjCCustomChromePage *replacement = [[ObjCCustomChromePage alloc]
        initWithPageTitle:[NSString stringWithFormat:@"Replaced %ld", (long)self.pushCount]];
    replacement.container = container;

    [container setViewControllers:@[root, replacement] animated:YES];
    [self record:[NSString stringWithFormat:@"setViewControllers → depth=%lu",
                  (unsigned long)container.viewControllers.count]];
    [self refresh];
}

/// 推一頁只碰 `navigationItem` 的頁面：chrome 由 `-bindToNavigationItem:backAction:` 鏡射。
- (void)pushMirrorTapped
{
    TeroNavigationContainer *container = [self selectedContainer];
    if (container == nil) { return; }
    self.pushCount += 1;
    ObjCNavigationItemPage *page = [[ObjCNavigationItemPage alloc]
        initWithPageTitle:[NSString stringWithFormat:@"Mirror %ld", (long)self.pushCount]];
    page.container = container;
    [container pushViewController:page animated:YES];
    [self record:[NSString stringWithFormat:@"push mirror → depth=%lu",
                  (unsigned long)container.viewControllers.count]];
    [self refresh];
}

- (void)toggleGestureTapped
{
    TeroNavigationContainer *container = [self selectedContainer];
    BOOL next = !container.isInteractivePopGestureEnabled;
    container.isInteractivePopGestureEnabled = next;
    [self record:[NSString stringWithFormat:@"邊緣返回手勢：%@", next ? @"開" : @"關"]];
    [self refresh];
}

- (void)toggleActionTapped
{
    if (self.tabController.actionItem != nil) {
        [self.tabController setActionItem:nil animated:YES];
        [self record:@"setActionItem(nil)"];
    } else {
        TeroTabActionItem *action =
            [[TeroTabActionItem alloc] initWithIdentifier:@"compose"
                                                    image:[UIImage systemImageNamed:@"square.and.pencil"]];
        action.accessibilityIdentifier = @"objclab.action.compose";
        [self.tabController setActionItem:action animated:YES];
        [self record:@"setActionItem(compose)"];
    }
    [self refresh];
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

#pragma mark - TeroTabBarControllerDelegate

/// 初始選取不會詢問這個方法，所以 source 永遠不會是 initial。
/// 攔截（回傳 NO）那條路徑由 `ObjCDemoHostViewController` 的「攔截 Profile」示範。
- (BOOL)teroTabBarController:(TeroTabBarController *)tabController
                shouldSelect:(TeroTab *)tab
                      source:(TeroTabSelectionSource)source
{
    [self record:[NSString stringWithFormat:@"shouldSelect(%@, source=%ld) → YES",
                  tab.identifier, (long)source]];
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
    // 重新選取同一個 Tab：慣例是回到 stack 底部。
    TeroNavigationContainer *container = [self selectedContainer];
    [container popToRootViewControllerAnimated:YES];
    [self record:[NSString stringWithFormat:@"didReselect(%@) → popToRoot", tab.identifier]];
    [self refresh];
}

- (void)teroTabBarController:(TeroTabBarController *)tabController didTrigger:(TeroTabActionItem *)actionItem
{
    // Action Item 不改變 selection，只發事件。
    [self record:[NSString stringWithFormat:@"didTrigger(%@)", actionItem.identifier]];
    [self refresh];
}

- (void)teroTabBarController:(TeroTabBarController *)tabController
    willChangeTabBarPresentationState:(TeroTabBarPresentationState)state
{
    [self record:[NSString stringWithFormat:@"willChangePresentationState(%ld)", (long)state]];
}

- (void)teroTabBarController:(TeroTabBarController *)tabController
    didChangeTabBarPresentationState:(TeroTabBarPresentationState)state
{
    [self record:[NSString stringWithFormat:@"didChangePresentationState(%ld)", (long)state]];
    [self refresh];
}

#pragma mark - Helpers

- (NSString *)titleOf:(UIViewController *)viewController
{
    return [viewController isKindOfClass:ObjCNavigationChromePage.class]
        ? ((ObjCNavigationChromePage *)viewController).pageTitle
        : @"nil";
}

- (void)record:(NSString *)line
{
    [self.journal addObject:line];
    if (self.journal.count > 12) { [self.journal removeObjectAtIndex:0]; }
    self.journalView.text = [self.journal componentsJoinedByString:@"\n"];
}

- (void)refresh
{
    TeroNavigationContainer *container = [self selectedContainer];
    self.stateLabel.text = [NSString stringWithFormat:
        @"tab=%@  depth=%lu  top=%@\npresentationState=%ld  actionItem=%@\n邊緣手勢=%@  chrome 收合請往上滑",
        self.tabController.selectedTab.identifier ?: @"nil",
        (unsigned long)container.viewControllers.count,
        [self titleOf:container.topViewController],
        (long)self.tabController.tabBarPresentationState,
        self.tabController.actionItem.identifier ?: @"nil",
        container.isInteractivePopGestureEnabled ? @"開" : @"關"];
}

@end
