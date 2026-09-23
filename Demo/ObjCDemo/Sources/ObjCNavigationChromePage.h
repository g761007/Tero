#import <UIKit/UIKit.h>
#import "ObjCDemo-Swift.h"

/// 由畫面自己提供 chrome 的參考頁，chrome 用現成的 `TeroNavigationBar` 排出
/// Primary（標題與按鈕）與 Secondary（分類列）。
///
/// 這一頁同時是捲動輸入的來源：Tab Bar 的追蹤路徑讀它的 table view，再把樣本轉給
/// 選取中的 Navigation Container，頂部 chrome 才有東西可以收合。單獨使用的容器則自己
/// 觀察 top 的 scroll view（2.1 起）。
@interface ObjCNavigationChromePage : UIViewController <
    TeroNavigationChromeProviding,
    TeroScrollProviding,
    TeroTabBarScrollBehaviorProviding>

- (instancetype)initWithPageTitle:(NSString *)pageTitle
                         material:(TeroNavigationButtonMaterial)material
                        showsBack:(BOOL)showsBack;

@property (nonatomic, readonly, copy) NSString *pageTitle;

/// 容器持有頁面，頁面只能反向弱引用。
@property (nonatomic, weak) TeroNavigationContainer *container;

/// trailing 的 push 鍵按下時呼叫。由 Lab 決定要推什麼進去。
@property (nonatomic, copy) void (^onPushRequested)(void);

@end
