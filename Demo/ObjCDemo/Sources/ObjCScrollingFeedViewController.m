#import "ObjCScrollingFeedViewController.h"

@interface ObjCScrollingFeedViewController () <UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation ObjCScrollingFeedViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.accessibilityIdentifier = @"objc.feed.table";
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"cell"];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

#pragma mark - TeroScrollProviding / TeroTabBarScrollBehaviorProviding

// required：回傳 nil 表示這個畫面不參與捲動追蹤。
- (UIScrollView *)teroTrackingScrollView {
    return self.tableView;
}

// optional：未實作時沿用設定中的行為。這裡刻意實作，讓 optional 成員也進到編譯覆蓋。
- (TeroTabBarScrollBehavior)preferredTeroTabBarScrollBehavior {
    return TeroTabBarScrollBehaviorMinimizeOnScrollDown;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.textLabel.text = [NSString stringWithFormat:@"Row %ld", (long)indexPath.row];
    return cell;
}

@end
