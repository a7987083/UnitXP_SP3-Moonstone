#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^ZonoeAuthCompletion)(BOOL ok, NSString *message, NSDictionary * _Nullable info);

FOUNDATION_EXPORT void ZonoeAuthLogin(NSString *username,
                                      NSString *password,
                                      ZonoeAuthCompletion completion);

FOUNDATION_EXPORT void ZonoeAuthRegister(NSString *username,
                                         NSString *password,
                                         NSString * _Nullable channel,
                                         ZonoeAuthCompletion completion);

FOUNDATION_EXPORT void ZonoeAuthChangePassword(NSString *username,
                                               NSString *oldPassword,
                                               NSString *newPassword,
                                               ZonoeAuthCompletion completion);

NS_ASSUME_NONNULL_END
