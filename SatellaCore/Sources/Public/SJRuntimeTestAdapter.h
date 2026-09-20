#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJRuntimeTestAdapter : NSObject
// Safe test equivalent of the upstream DyldHook decision. This returns the
// name a detector should be shown, but it never hooks dyld or hides a loaded image.
+ (NSString *)simulatedVisibleImageNameForOriginalImageName:(NSString *)originalImageName;
@end

NS_ASSUME_NONNULL_END
