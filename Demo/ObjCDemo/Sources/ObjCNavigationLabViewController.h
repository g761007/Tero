#import <UIKit/UIKit.h>

/// 2.0 導覽介面的 Objective-C 參考畫面。
///
/// 每個 Tab 各自一個 `TeroNavigationContainer`：push／pop、由畫面提供的 chrome、
/// 自訂 chrome view、Tab Bar 的 delegate 事件，以及捲動驅動的收合，全部從
/// Objective-C 呼叫。容器**刻意巢狀在 `TeroTabBarController` 裡**——捲動樣本由
/// Tab Bar 的追蹤路徑轉給選取中的容器，單獨使用的容器沒有樣本來源。
@interface ObjCNavigationLabViewController : UIViewController
@end
