#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HFAPatchMenuUI : NSObject
+ (instancetype)sharedUI;
- (void)start;
- (void)reload;
@end

NS_ASSUME_NONNULL_END
