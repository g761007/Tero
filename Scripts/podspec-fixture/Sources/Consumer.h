#import <UIKit/UIKit.h>
#import <Tero/Tero-Swift.h>

/// 在 `.h` 的公開介面上宣告採用 Swift 定義的 `@objc protocol`。
/// source drop 可以做到這件事；這裡驗 pod 也可以。
@interface Consumer : NSObject <TeroTabBarControllerDelegate>
- (TeroTabBarController *)makeController;
@end
