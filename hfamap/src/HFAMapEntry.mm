#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

static void HFAMapInitialize(void)
{
    NSLog(@"[HFAMap] Theos build entry loaded");
}

__attribute__((constructor))
static void HFAMapConstructor(void)
{
    @autoreleasepool {
        HFAMapInitialize();
    }
}
