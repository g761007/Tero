#import "ObjCCustomChromePage.h"

@interface ObjCCustomChromeView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *hairline;
@end

@implementation ObjCCustomChromeView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self == nil) { return nil; }

    self.backgroundColor = UIColor.secondarySystemBackgroundColor;

    _backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_backButton setImage:[UIImage systemImageNamed:@"chevron.backward"] forState:UIControlStateNormal];
    _backButton.accessibilityIdentifier = @"objc.custom.back";

    _titleLabel = [UILabel new];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _titleLabel.adjustsFontForContentSizeCategory = YES;

    // 收合進度的即時讀數。它是這個 Demo 唯一看得出
    // `updateTeroNavigationChrome:collapseProgress:` 真的在逐幀被呼叫的地方。
    _progressLabel = [UILabel new];
    _progressLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _progressLabel.textColor = UIColor.secondaryLabelColor;
    _progressLabel.accessibilityIdentifier = @"objc.custom.progress";
    _progressLabel.text = @"collapse 0.00";

    _subtitleLabel = [UILabel new];
    _subtitleLabel.font = [UIFont systemFontOfSize:13];
    _subtitleLabel.textColor = UIColor.secondaryLabelColor;
    _subtitleLabel.text = @"自訂 chrome：Tero 不認得這個型別";

    _hairline = [UIView new];
    _hairline.backgroundColor = UIColor.separatorColor;

    for (UIView *subview in @[_backButton, _titleLabel, _progressLabel, _subtitleLabel, _hairline]) {
        subview.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:subview];
    }

    // displayScale 在還沒進入階層時可能是 0，除下去會得到 inf，NSLayoutConstraint 會丟例外。
    CGFloat scale = self.traitCollection.displayScale > 0 ? self.traitCollection.displayScale : 2;

    // **刻意不把任何東西釘在自己的下緣。** 總高度是容器依 provider 的兩個端點算出來的，
    // 這個 view 只從自己的 safe area 上緣往下排；釘下緣會在收合時把高度壓成負值。
    [NSLayoutConstraint activateConstraints:@[
        [_backButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_backButton.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor],
        [_backButton.heightAnchor constraintEqualToConstant:44],
        [_backButton.widthAnchor constraintEqualToConstant:44],

        [_titleLabel.leadingAnchor constraintEqualToAnchor:_backButton.trailingAnchor constant:8],
        [_titleLabel.centerYAnchor constraintEqualToAnchor:_backButton.centerYAnchor],

        [_progressLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_progressLabel.centerYAnchor constraintEqualToAnchor:_backButton.centerYAnchor],
        [_progressLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:_titleLabel.trailingAnchor constant:8],

        [_subtitleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_subtitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],
        [_subtitleLabel.topAnchor constraintEqualToAnchor:_backButton.bottomAnchor constant:2],

        [_hairline.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_hairline.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_hairline.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_hairline.heightAnchor constraintEqualToConstant:1.0 / scale]
    ]];
    return self;
}

- (void)setChromeTitle:(NSString *)chromeTitle
{
    _chromeTitle = [chromeTitle copy];
    self.titleLabel.text = _chromeTitle;
}

- (void)applyCollapseProgress:(CGFloat)progress
{
    CGFloat clamped = MIN(MAX(progress, 0), 1);
    self.progressLabel.text = [NSString stringWithFormat:@"collapse %.2f", clamped];
    self.subtitleLabel.alpha = 1 - clamped;
    self.subtitleLabel.transform = CGAffineTransformMakeTranslation(0, -8 * clamped);
}

@end

#pragma mark -

@implementation ObjCCustomChromePage

- (instancetype)initWithPageTitle:(NSString *)pageTitle
{
    // material 與 showsBack 只餵給父類的 `TeroNavigationBar` 版 chrome，
    // 這一頁整個覆寫掉它，所以傳什麼都不會被用到。
    return [super initWithPageTitle:pageTitle
                           material:TeroNavigationButtonMaterialPlain
                          showsBack:NO];
}

#pragma mark - TeroNavigationChromeProviding

- (UIView *)makeTeroNavigationChromeView
{
    ObjCCustomChromeView *chrome = [[ObjCCustomChromeView alloc] initWithFrame:CGRectZero];
    chrome.chromeTitle = self.pageTitle;
    [chrome.backButton addTarget:self
                          action:@selector(customBackTapped)
                forControlEvents:UIControlEventTouchUpInside];
    return chrome;
}

- (CGFloat)teroNavigationChromeHeight { return 140; }

- (CGFloat)teroNavigationChromeCollapsedHeight { return 100; }

- (void)updateTeroNavigationChrome:(UIView *)chromeView collapseProgress:(CGFloat)collapseProgress
{
    if (![chromeView isKindOfClass:ObjCCustomChromeView.class]) { return; }
    [(ObjCCustomChromeView *)chromeView applyCollapseProgress:collapseProgress];
}

#pragma mark - TeroTabVisibilityProviding

// optional：這一頁要求 Tab Bar 收起來。政策由頁面表態，Navigation Container 原封
// 往上傳，Tab Bar 容器仲裁——轉發鏈少一段就停在中途。
- (TeroTabVisibilityPolicy)preferredTeroTabVisibilityPolicy
{
    return TeroTabVisibilityPolicyHidden;
}

#pragma mark - Actions

- (void)customBackTapped
{
    [self.teroNavigationContainer popViewControllerAnimated:YES];
}

@end
