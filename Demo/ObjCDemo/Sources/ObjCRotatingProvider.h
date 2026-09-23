#import <UIKit/UIKit.h>
#import "ObjCDemo-Swift.h"

/// 以 Objective-C 實作套件的 Content Provider。
///
/// 在 source drop 模式下，generated header 可以在 `.h` 裡引入，
/// 因此 protocol 的採用能寫在公開介面上（不必只藏在 `.m`）。
///
/// 採用的是**進階**協定 `TeroTabInteractiveContentProvider`：它繼承
/// `TeroTabContentProvider`，額外收到 0.0…1.0 的連續進度。這裡兩個 optional
/// 方法都實作，因為這個 Demo 的用途就是證明它們從 Objective-C 用得到——
/// 協定在 Swift 那側是 `@objc optional`，選擇器名稱與參數型別能不能過橋，
/// 只有真的有人從 Objective-C 實作過才算數。
@interface ObjCRotatingProvider : NSObject <TeroTabInteractiveContentProvider>
@property (nonatomic, readonly) NSInteger madeContentViewCount;
/// 最後一次收到的選取進度，供 Demo 的狀態列顯示「回呼真的有來」。
@property (nonatomic, readonly) CGFloat lastSelectionProgress;
/// 最後一次收到的呈現進度（expanded = 0、minimized = 1）。
@property (nonatomic, readonly) CGFloat lastPresentationProgress;
@property (nonatomic, readonly) NSInteger selectionProgressCallbackCount;
@end
