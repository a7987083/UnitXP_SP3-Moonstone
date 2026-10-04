#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^ZNBuildCapabilityProbe)(void);

typedef NS_ENUM(NSUInteger, ZNBuildCapabilityKind) {
    ZNBuildCapabilityKindStaticPatch = 0,
    ZNBuildCapabilityKindRuntimeOwnedData = 1,
};

/// Registry is backend-facing. Any future buildable feature registers one probe.
/// UI must never inspect concrete hook/action stores.
@interface ZNBuildCapabilityRegistry : NSObject
+ (instancetype)sharedRegistry;
- (void)registerProviderIdentifier:(NSString *)identifier
                              kind:(ZNBuildCapabilityKind)kind
               hasBuildableContent:(ZNBuildCapabilityProbe)probe;
- (void)registerProviderIdentifier:(NSString *)identifier
               hasBuildableContent:(ZNBuildCapabilityProbe)probe;
- (void)unregisterProviderIdentifier:(NSString *)identifier;
- (BOOL)hasBuildableContent;
- (BOOL)hasBuildableContentOfKind:(ZNBuildCapabilityKind)kind;
- (NSArray<NSString *> *)activeProviderIdentifiers;
- (NSArray<NSString *> *)activeProviderIdentifiersOfKind:(ZNBuildCapabilityKind)kind;
@end

/// Single policy owner for whether the Build button is actionable.
@interface ZNBinaryBuildCoordinator : NSObject
+ (instancetype)sharedCoordinator;
@property(nonatomic,readonly) BOOL canBuild;
@property(nonatomic,copy,readonly) NSString *blockedReason;
@property(nonatomic,copy,readonly) NSArray<NSString *> *activeProviderIdentifiers;
@end

/// Convenience C ABI for future modules that should not depend on UI code.
FOUNDATION_EXPORT void ZNRegisterBuildCapabilityProvider(NSString *identifier,
                                                         ZNBuildCapabilityProbe probe);
FOUNDATION_EXPORT void ZNRegisterBuildCapabilityProviderWithKind(NSString *identifier,
                                                                 ZNBuildCapabilityKind kind,
                                                                 ZNBuildCapabilityProbe probe);
FOUNDATION_EXPORT void ZNUnregisterBuildCapabilityProvider(NSString *identifier);

NS_ASSUME_NONNULL_END
