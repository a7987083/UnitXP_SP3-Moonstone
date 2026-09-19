#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SJDiagnostics : NSObject
+ (void)appendModule:(NSString *)module message:(NSString *)message code:(NSInteger)code;
+ (NSArray<NSDictionary<NSString *, id> *> *)snapshot;
+ (void)reset;
@end

NS_ASSUME_NONNULL_END
