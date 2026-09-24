#import "ObjCNavigationItemPage.h"

@interface ObjCNavigationItemPage ()
@property (nonatomic, assign) NSInteger tapCount;
@end

@implementation ObjCNavigationItemPage

- (instancetype)initWithPageTitle:(NSString *)pageTitle
{
    self = [super initWithNibName:nil bundle:nil];
    if (self == nil) { return nil; }
    _pageTitle = [pageTitle copy];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    // 頁面照舊寫 navigationItem——這正是遷移時不想改的那些呼叫點。
    self.navigationItem.title = self.pageTitle;
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"Done"
                                                             style:UIBarButtonItemStyleDone
                                                            target:self
                                                            action:@selector(doneTapped)];
    done.accessibilityIdentifier = @"objc.mirror.done";
    self.navigationItem.rightBarButtonItems = @[done];

    UILabel *label = [UILabel new];
    label.text = @"navigationItem → TeroNavigationBar";
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [label.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20]
    ]];
}

#pragma mark - TeroNavigationChromeProviding

- (UIView *)makeTeroNavigationChromeView
{
    TeroNavigationBar *bar = [[TeroNavigationBar alloc] initWithFrame:CGRectZero];
    __weak __typeof(self) weakSelf = self;
    // 每一頁都照傳同一個返回動作：root 不會有返回鍵，這由容器判斷。
    [bar bindToNavigationItem:self.navigationItem
                   backAction:^{ [weakSelf.teroNavigationContainer popViewControllerAnimated:YES]; }];
    return bar;
}

- (CGFloat)teroNavigationChromeHeight { return TeroNavigationBar.primaryHeight; }

#pragma mark - Actions

/// 執行期改 navigationItem：鏡射要跟上，不是綁定那一刻抄一次。
- (void)doneTapped
{
    self.tapCount += 1;
    self.navigationItem.title = [NSString stringWithFormat:@"%@ · %ld", self.pageTitle, (long)self.tapCount];
}

@end
