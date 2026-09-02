#import "HFAPatchMenuUI.h"
#import "HFAPatchLogger.h"

#import <UIKit/UIKit.h>

static void HFAPatchStartOnce(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (![NSBundle.mainBundle.bundlePath.pathExtension.lowercaseString isEqualToString:@"app"]) return;
            HFAPatchLog(@"[BOOT] version=0.1.0 bundle=%@", NSBundle.mainBundle.bundleIdentifier ?: @"<none>");
            [HFAPatchMenuUI.sharedUI start];
        });
    });
}

__attribute__((constructor)) static void HFAPatchEntry(void)
{
    @autoreleasepool {
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateInactive ||
            UIApplication.sharedApplication.delegate) {
            HFAPatchStartOnce();
        } else {
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                            object:nil
                                                             queue:NSOperationQueue.mainQueue
                                                        usingBlock:^(__unused NSNotification *notification) {
                HFAPatchStartOnce();
            }];
        }
    }
}

extern "C" __attribute__((visibility("default"))) void HFAPatchMenuReloadConfig(void)
{
    [HFAPatchMenuUI.sharedUI reload];
}
