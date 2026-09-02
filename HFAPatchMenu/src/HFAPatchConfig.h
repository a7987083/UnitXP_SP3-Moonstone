#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HFAPatchTarget : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *image;
@property(nonatomic, copy) NSString *uuid;
@end

@interface HFAPatchOperation : NSObject
@property(nonatomic, copy) NSString *targetIdentifier;
@property(nonatomic, assign) uint64_t offset;
@property(nonatomic, copy) NSData *originalBytes;
@property(nonatomic, copy) NSData *enabledBytes;
@end

@interface HFAPatchFeature : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *group;
@property(nonatomic, assign) BOOL defaultEnabled;
@property(nonatomic, copy) NSArray<HFAPatchOperation *> *patches;
@end

@interface HFAPatchPackageIdentity : NSObject
@property(nonatomic, copy) NSString *bundleIdentifier;
@property(nonatomic, copy) NSString *shortVersion;
@property(nonatomic, copy) NSString *buildVersion;
@property(nonatomic, copy) NSArray<NSString *> *architectures;
@end

@interface HFAPatchConfiguration : NSObject
@property(nonatomic, copy) NSString *schema;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, strong) HFAPatchPackageIdentity *packageIdentity;
@property(nonatomic, copy) NSDictionary<NSString *, HFAPatchTarget *> *targets;
@property(nonatomic, copy) NSArray<HFAPatchFeature *> *features;
@property(nonatomic, copy) NSString *sourcePath;

+ (nullable instancetype)loadPreferredConfigurationWithError:(NSError **)error;
+ (nullable instancetype)configurationWithData:(NSData *)data
                                     sourcePath:(NSString *)sourcePath
                                          error:(NSError **)error;
@end

FOUNDATION_EXPORT NSString *HFAPatchNormalizedUUID(NSString *value);
FOUNDATION_EXPORT NSString *HFAPatchHexString(NSData *data);

NS_ASSUME_NONNULL_END
