#import <UIKit/UIKit.h>
#import "ObjCDemo-Swift.h"
#import "ObjCNavigationChromePage.h"

/// 完全自己畫的 chrome，不是 `TeroNavigationBar`。
///
/// 存在理由是證明容器的契約真的只有「一個 `UIView` ＋ 一條 0…1 的收合進度」：
/// 這個型別 Tero 一個字都不認得，也沒有採用任何套件協定。圖示走 SF Symbols、
/// 其餘用 Core Graphics 畫，不帶任何 bundle 資源（ADR-0007）。
@interface ObjCCustomChromeView : UIView

@property (nonatomic, readonly, strong) UIButton *backButton;

/// Primary 列的標題。這個名字不叫 `title`：`UIView` 沒有那個屬性，
/// 借用系統名字只會讓讀的人以為它來自 UIKit。
@property (nonatomic, copy) NSString *chromeTitle;

/// 由頁面在 `updateTeroNavigationChrome:collapseProgress:` 裡轉發進來。
/// 收合方式是這個 view 自己定義的：副標整段淡出，標題縮小並靠左收。
- (void)applyCollapseProgress:(CGFloat)progress;

@end

/// 被推進 stack 的詳細頁。
///
/// 除了換成自訂 chrome，它還宣告 `TeroTabVisibilityProviding`：進到這一頁時 Tab Bar
/// 收起來。政策沿轉發鏈往上走——頁面 → Navigation Container → Tab Bar 容器。
@interface ObjCCustomChromePage : ObjCNavigationChromePage <TeroTabVisibilityProviding>

- (instancetype)initWithPageTitle:(NSString *)pageTitle;

@end
