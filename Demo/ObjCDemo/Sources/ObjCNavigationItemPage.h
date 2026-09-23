#import <UIKit/UIKit.h>
#import "ObjCDemo-Swift.h"

/// 既有頁面不改寫法：這一頁只碰 `navigationItem`，chrome 由
/// `-[TeroNavigationBar bindToNavigationItem:backAction:]` 鏡射（issue #89）。
@interface ObjCNavigationItemPage : UIViewController <TeroNavigationChromeProviding>

- (instancetype)initWithPageTitle:(NSString *)pageTitle;

@property (nonatomic, readonly, copy) NSString *pageTitle;

/// 容器持有頁面，頁面只能反向弱引用。
@property (nonatomic, weak) TeroNavigationContainer *container;

@end
