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

// Pure primitive-name classifier used by the runtime classifier and CI tests.
// Non-primitive managed types intentionally return Unknown here and are refined
// with il2cpp_class_from_type / il2cpp_class_is_valuetype at runtime.
FOUNDATION_EXPORT ZNIL2CPPABIValueKind ZNIL2CPPABIKindForManagedTypeName(NSString *typeName);

// Candidate is the existing Method Finder V3 dictionary. The returned object is
// descriptive only: M3.1 never installs a hook or mutates target memory.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *ZNIL2CPPDescribeMethodABI(NSDictionary<NSString *, id> *candidate);

// Builds and validates a future Return Override plan without applying it. This
// is the contract M3.2 hook backends will consume. Only conservative scalar
// return classes are accepted in M3.1.
FOUNDATION_EXPORT nullable NSDictionary<NSString *, id> *ZNIL2CPPBuildReturnOverridePlan(
    NSDictionary<NSString *, id> *candidate,
    NSNumber *value,
    NSString * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
