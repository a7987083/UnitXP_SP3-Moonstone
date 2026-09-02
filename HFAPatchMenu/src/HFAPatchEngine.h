#import <Foundation/Foundation.h>
#import "HFAPatchConfig.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, HFAPatchFeatureState) {
    HFAPatchFeatureStateUnavailable = 0,
    HFAPatchFeatureStateDisabled,
    HFAPatchFeatureStateEnabled,
    HFAPatchFeatureStateMixed,
};

@interface HFAPatchEngine : NSObject
@property(nonatomic, strong, readonly, nullable) HFAPatchConfiguration *configuration;
@property(nonatomic, copy, readonly, nullable) NSString *configurationError;
@property(nonatomic, assign, readonly, getter=isReady) BOOL ready;

+ (instancetype)sharedEngine;
- (BOOL)reloadConfiguration;
- (HFAPatchFeatureState)stateForFeature:(HFAPatchFeature *)feature
                                  error:(NSString * _Nullable * _Nullable)error;
- (BOOL)setFeature:(HFAPatchFeature *)feature
           enabled:(BOOL)enabled
             error:(NSString * _Nullable * _Nullable)error;
- (void)disableAll;
@end

NS_ASSUME_NONNULL_END
