#import "Consumer.h"

@implementation Consumer

- (TeroTabBarController *)makeController {
    TeroTabBarConfiguration *configuration = [TeroTabBarConfiguration defaultConfiguration];
    configuration.style = TeroTabBarStyleClassic;
    configuration.compact.maximumVisibleItems = 4;

    TeroTabBarController *controller =
        [[TeroTabBarController alloc] initWithConfiguration:configuration];
    controller.delegate = self;

    TeroTabItem *item = [[TeroTabItem alloc] initWithTitle:@"Home" image:nil selectedImage:nil];
    TeroTab *tab = [[TeroTab alloc] initWithIdentifier:@"home"
                                        viewController:[UIViewController new]
                                                  item:item];
    [controller setTabs:@[tab] selectedIdentifier:@"home" animated:NO];
    return controller;
}

@end
