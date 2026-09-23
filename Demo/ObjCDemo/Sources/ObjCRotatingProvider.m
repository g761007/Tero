#import "ObjCRotatingProvider.h"
#import "ObjCDemo-Swift.h"

/// 以 Objective-C 實作 `TeroTabContentProvider`，證明自訂內容不必先改寫成 Swift。
///
/// 這裡用 Core Animation 而不是 Lottie：Lottie 4.x 是**純 Swift** 函式庫，
/// Objective-C 無法直接使用它（與本套件無關，是該函式庫本身的限制）。
/// 若 App 需要從 Objective-C 使用 Lottie，慣例做法是在同一個 target 內
/// 加一個 Swift 轉接檔，再由 Objective-C 透過 generated header 取用。
@interface ObjCRotatingProvider ()
@property (nonatomic, assign) NSInteger madeCount;
@property (nonatomic, assign) CGFloat selectionProgress;
@property (nonatomic, assign) CGFloat presentationProgress;
@property (nonatomic, assign) NSInteger progressCount;
@end

@implementation ObjCRotatingProvider

- (NSInteger)madeContentViewCount { return self.madeCount; }
- (CGFloat)lastSelectionProgress { return self.selectionProgress; }
- (CGFloat)lastPresentationProgress { return self.presentationProgress; }
- (NSInteger)selectionProgressCallbackCount { return self.progressCount; }

- (UIView *)makeContentView
{
    self.madeCount += 1;

    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    container.backgroundColor = UIColor.clearColor;

    CALayer *bar = [CALayer layer];
    bar.frame = CGRectMake(2, 11, 24, 6);
    bar.cornerRadius = 3;
    bar.backgroundColor = UIColor.systemOrangeColor.CGColor;
    [container.layer addSublayer:bar];

    return container;
}

- (void)updateContentView:(UIView *)contentView
                 selected:(BOOL)selected
        presentationState:(TeroTabBarPresentationState)presentationState
                 animated:(BOOL)animated
{
    CALayer *bar = contentView.layer.sublayers.firstObject;
    if (bar == nil) { return; }

    // animated == NO 可能代表使用者開啟了「減少動態效果」，此時不播放。
    if (selected && animated) {
        if ([bar animationForKey:@"spin"] == nil) {
            CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
            spin.fromValue = @0;
            spin.toValue = @(M_PI * 2);
            spin.duration = 1.2;
            spin.repeatCount = HUGE_VALF;
            [bar addAnimation:spin forKey:@"spin"];
        }
    } else {
        [bar removeAnimationForKey:@"spin"];
    }

    bar.backgroundColor = selected
        ? UIColor.systemOrangeColor.CGColor
        : UIColor.systemGray3Color.CGColor;
}

#pragma mark - TeroTabInteractiveContentProvider

/// 選取膠囊滑動途中的每一幀都會進來，0.0…1.0。
///
/// Bool 版的回呼只說得出「選取／未選取」，做不出跟著膠囊同步變化的動畫；這個方法就是
/// 為此存在的。兩端點刻意與 Bool 版算出同樣的顏色，狀態落定時才不會跳一下。
///
/// `CATransaction` 要關掉隱含動畫：CALayer 改 `backgroundColor` 預設會自己補 0.25 秒的
/// 動畫，而進度回呼每一幀都來——不關的話畫面追的是上一幀的動畫，不是手上的進度。
- (void)updateContentView:(UIView *)contentView
        selectionProgress:(CGFloat)selectionProgress
                 animated:(BOOL)animated
{
    self.selectionProgress = selectionProgress;
    self.progressCount += 1;

    CALayer *bar = contentView.layer.sublayers.firstObject;
    if (bar == nil) { return; }

    CGFloat clamped = MAX(0, MIN(1, selectionProgress));
    UIColor *from = UIColor.systemGray3Color;
    UIColor *to = UIColor.systemOrangeColor;
    CGFloat fr, fg, fb, fa, tr, tg, tb, ta;
    if (![from getRed:&fr green:&fg blue:&fb alpha:&fa]) { return; }
    if (![to getRed:&tr green:&tg blue:&tb alpha:&ta]) { return; }

    UIColor *blended = [UIColor colorWithRed:fr + (tr - fr) * clamped
                                       green:fg + (tg - fg) * clamped
                                        blue:fb + (tb - fb) * clamped
                                       alpha:fa + (ta - fa) * clamped];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    bar.backgroundColor = blended.CGColor;
    // 跟著進度長出來：完全未選取時短、完全選取時滿寬。
    CGFloat width = 12 + 12 * clamped;
    bar.frame = CGRectMake((28 - width) / 2, 11, width, 6);
    bar.cornerRadius = 3;
    [CATransaction commit];
}

/// expanded = 0、minimized = 1。Tab Bar 縮起來時內容也跟著縮，否則會頂到膠囊邊緣。
- (void)updateContentView:(UIView *)contentView
     presentationProgress:(CGFloat)presentationProgress
                 animated:(BOOL)animated
{
    self.presentationProgress = presentationProgress;

    CGFloat clamped = MAX(0, MIN(1, presentationProgress));
    CGFloat scale = 1 - 0.35 * clamped;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    contentView.transform = CGAffineTransformMakeScale(scale, scale);
    [CATransaction commit];
}

@end
