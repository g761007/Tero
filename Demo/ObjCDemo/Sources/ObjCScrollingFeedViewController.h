#import <UIKit/UIKit.h>
#import "ObjCDemo-Swift.h"

/// 以 Objective-C 採用套件的捲動協定。
///
/// 這個頁面的存在理由是**編譯覆蓋**：CI 的 objc-demo job 會驗證
/// `TeroScrollProviding` 與 `TeroTabBarScrollBehaviorProviding` 的成員
/// 都能從 Objective-C 實作。
/// 在此之前，source drop 這條交付路徑從未編譯過這個協定。
@interface ObjCScrollingFeedViewController : UIViewController <TeroScrollProviding, TeroTabBarScrollBehaviorProviding>
@end
