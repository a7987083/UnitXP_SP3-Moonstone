#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "ZNRuntimeActionModel.h"

static const void *kZNRuntimeDescriptionKey = &kZNRuntimeDescriptionKey;

@implementation ZNRuntimeMethodAction (ZNRuntimeDescriptionBridge)
- (NSString *)descriptionText {
    NSString *value = objc_getAssociatedObject(self, kZNRuntimeDescriptionKey);
    return [value isKindOfClass:NSString.class] ? value : @"";
}
- (void)setDescriptionText:(NSString *)descriptionText {
    NSString *trimmed = [descriptionText ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    objc_setAssociatedObject(self, kZNRuntimeDescriptionKey, trimmed, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
@end

@implementation ZNRuntimeActionStore (ZNRuntimeDescriptionBridge)
- (BOOL)updateDescriptionText:(NSString *)descriptionText atIndex:(NSUInteger)index error:(NSString **)error {
    @synchronized(self) {
        NSArray<ZNRuntimeMethodAction *> *snapshot = [self actionsSnapshot];
        if (index >= snapshot.count) {
            if (error) *error = @"Runtime Method Call 索引已失效";
            return NO;
        }
        // mutableActions is intentionally private; update the live object through KVC.
        NSMutableArray *mutable = [self valueForKey:@"mutableActions"];
        if (![mutable isKindOfClass:NSMutableArray.class] || index >= mutable.count) {
            if (error) *error = @"Runtime Method Call 存储不可用";
            return NO;
        }
        ZNRuntimeMethodAction *action = mutable[index];
        action.descriptionText = descriptionText ?: @"";
        return YES;
    }
}
@end
