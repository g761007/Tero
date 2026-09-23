#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[]) {
    NSString *delegateClassName = NSStringFromClass([AppDelegate class]);
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, delegateClassName);
    }
}
