// **順序有意義**：產生的介面用 `@import UIKit` 取得 UIView 等型別，而 ObjC++ 預設
// 沒有開 modules，所以要先用標頭的形式把 UIKit 帶進來。顛倒過來會得到一整排
// `unknown type name 'UIView'`。
#import <UIKit/UIKit.h>
#import <Tero/Tero-Swift.h>
#include <vector>

/// ObjC++ 是 pod 相對 SPM 的關鍵差異：SPM module 在 `.mm` 匯入不可用（spike 0001）。
@interface ConsumerCpp : NSObject
- (NSUInteger)badgeCount;
@end

@implementation ConsumerCpp

- (NSUInteger)badgeCount {
    std::vector<int> pending{1, 2, 3};
    TeroTabBadge *badge = [TeroTabBadge new];
    badge.style = TeroTabBadgeStyleValue;
    badge.value = @"3";
    return pending.size() + badge.value.length;
}

@end
