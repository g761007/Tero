#import "ObjCNavigationChromePage.h"

@interface ObjCNavigationChromePage () <UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) TeroNavigationButtonMaterial material;
@property (nonatomic, assign) BOOL showsBack;
@end

@implementation ObjCNavigationChromePage

- (instancetype)initWithPageTitle:(NSString *)pageTitle
                         material:(TeroNavigationButtonMaterial)material
                        showsBack:(BOOL)showsBack
{
    self = [super initWithNibName:nil bundle:nil];
    if (self == nil) { return nil; }
    _pageTitle = [pageTitle copy];
    _material = material;
    _showsBack = showsBack;
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.accessibilityIdentifier =
        [NSString stringWithFormat:@"objc.nav.table.%@", self.pageTitle];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

#pragma mark - TeroNavigationChromeProviding

// 容器只認得「一個 view ＋ 一條 0…1 的收合進度」。標題、按鈕、Secondary 全是
// 這個 view 自己的事，所以整段都能從 Objective-C 寫。
- (UIView *)makeTeroNavigationChromeView
{
    TeroNavigationBar *bar = [[TeroNavigationBar alloc] initWithFrame:CGRectZero];
    // 底維持預設：`TeroNavigationBar` 自己畫一層 `UIBlurEffect`，「降低透明度」開啟時
    // 換成實色。內容從導覽列下方捲過去時看得到模糊。要關掉用 `showsBackdrop = NO`，
    // 之後底由自己負責。
    bar.title = self.pageTitle;

    if (self.showsBack) {
        TeroNavigationButton *back =
            [[TeroNavigationButton alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"]
                                               material:self.material];
        back.accessibilityIdentifier = @"objc.nav.back";
        [back addTarget:self action:@selector(popTapped) forControlEvents:UIControlEventTouchUpInside];
        bar.leadingItems = @[back];
    }

    TeroNavigationButton *push =
        [[TeroNavigationButton alloc] initWithImage:[UIImage systemImageNamed:@"plus.circle"]
                                           material:self.material];
    push.accessibilityIdentifier = @"objc.nav.push";
    [push addTarget:self action:@selector(pushTapped) forControlEvents:UIControlEventTouchUpInside];

    // 文字版的初始化器；與圖示版並列，兩個 initializer 都進到編譯覆蓋。
    TeroNavigationButton *edit = [[TeroNavigationButton alloc] initWithTitle:@"編輯"
                                                                    material:self.material];
    edit.accessibilityIdentifier = @"objc.nav.edit";
    [edit addTarget:self action:@selector(pushTapped) forControlEvents:UIControlEventTouchUpInside];

    bar.trailingItems = @[edit, push];

    NSArray<NSString *> *categories = @[@"All", @"Photos", @"Reels"];
    NSMutableArray<UIButton *> *chips = [NSMutableArray array];
    for (NSString *name in categories) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        [chip setTitle:name forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [chips addObject:chip];
    }
    UIStackView *secondary = [[UIStackView alloc] initWithArrangedSubviews:chips];
    secondary.distribution = UIStackViewDistributionFillEqually;
    bar.secondaryView = secondary;

    return bar;
}

/// 高度只算導覽列**自己的內容**，不含狀態列——狀態列那一段由容器補上它自己的安全區。
/// 這裡是 44 的 Primary 加 52 的 Secondary。
- (CGFloat)teroNavigationChromeHeight { return 96; }

/// optional：收合後剩下的是 Secondary 那一段——Primary 淡出並讓出它的高度。
- (CGFloat)teroNavigationChromeCollapsedHeight { return 52; }

/// optional：逐幀把進度轉給導覽列自己的收合方式。
- (void)updateTeroNavigationChrome:(UIView *)chromeView collapseProgress:(CGFloat)collapseProgress
{
    if (![chromeView isKindOfClass:TeroNavigationBar.class]) { return; }
    [(TeroNavigationBar *)chromeView applyCollapseProgress:collapseProgress];
}

#pragma mark - TeroScrollProviding

- (UIScrollView *)teroTrackingScrollView { return self.tableView; }

#pragma mark - TeroTabBarScrollBehaviorProviding

// optional：這一頁要求 Tab Bar 在下捲時縮小。FloatingGlass 以外的 Style 會忽略 minimized。
- (TeroTabBarScrollBehavior)preferredTeroTabBarScrollBehavior
{
    return TeroTabBarScrollBehaviorMinimizeOnScrollDown;
}

#pragma mark - Actions

- (void)popTapped
{
    // 回傳被移除的那一個；這裡用不到，Lab 的控制列會把它記進 journal。
    [self.container popViewControllerAnimated:YES];
}

- (void)pushTapped
{
    if (self.onPushRequested != nil) { self.onPushRequested(); }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 40;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    cell.textLabel.text = indexPath.row == 0
        ? [NSString stringWithFormat:@"%@ · 往上滑，看頂部 chrome 收合", self.pageTitle]
        : [NSString stringWithFormat:@"%@ · row %ld", self.pageTitle, (long)indexPath.row];
    return cell;
}

@end
