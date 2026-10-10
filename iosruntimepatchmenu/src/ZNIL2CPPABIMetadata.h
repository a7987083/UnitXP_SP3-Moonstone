#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZNIL2CPPABIValueKind) {
    ZNIL2CPPABIValueKindUnknown = 0,
    ZNIL2CPPABIValueKindVoid,
    ZNIL2CPPABIValueKindBool,
    ZNIL2CPPABIValueKindSigned32,
    ZNIL2CPPABIValueKindUnsigned32,
    ZNIL2CPPABIValueKindSigned64,
    ZNIL2CPPABIValueKindUnsigned64,
    ZNIL2CPPABIValueKindFloat32,
    ZNIL2CPPABIValueKindFloat64,
    ZNIL2CPPABIValueKindPointer,
    ZNIL2CPPABIValueKindObjectReference,
    ZNIL2CPPABIValueKindComplexValueType,
};

FOUNDATION_EXPORT NSString *ZNIL2CPPABIValueKindName(ZNIL2CPPABIValueKind kind);
FOUNDATION_EXPORT ZNIL2CPPABIValueKind ZNIL2CPPABIKindForManagedTypeName(NSString *typeName);
// Descriptive only: never use candidate slots to install hooks before verification.
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
ZNIL2CPPABIAggregateCandidate(NSDictionary<NSString *, id> *param);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *ZNIL2CPPDescribeMethodABI(NSDictionary<NSString *, id> *candidate);
// Conservative AAPCS64 location for scalar/by-ref parameters only.
// storage: gpr, fpr or stack; index is the register number or 8-byte stack slot.
// Does not claim support for aggregates, HFA, varargs or hidden sret.
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable
ZNIL2CPPABIArgumentLocation(NSDictionary<NSString *, id> *abi, NSUInteger argumentIndex);
// Only returns a location when all preceding arguments have known one-slot ABI classes.
FOUNDATION_EXPORT BOOL ZNIL2CPPABIGPRLocation(NSDictionary<NSString *, id> *abi,
                                              NSUInteger argumentIndex,
                                              uint32_t * _Nullable outRegister);
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable ZNIL2CPPBuildReturnOverridePlan(
    NSDictionary<NSString *, id> *candidate,
    NSNumber *value,
    NSString * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
