#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ZonoeAuthCompletion)(BOOL ok, NSString *message, NSDictionary * _Nullable accountInfo);

FOUNDATION_EXPORT void ZonoeAuthLogin(NSString *username,
                                      NSString *password,
                                      ZonoeAuthCompletion completion);

NS_ASSUME_NONNULL_END
