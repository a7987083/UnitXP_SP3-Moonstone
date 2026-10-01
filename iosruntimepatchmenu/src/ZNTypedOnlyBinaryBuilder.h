#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// M5.11 generic Typed-only generation path. Creates an owned
// __ZNDATA/__zndata container for every validated Typed Value target without
// requiring a Static Patch or Runtime Method record.
BOOL ZNTypedOnlyBinaryBuilderBuild(NSArray<NSString *> *targets,
                                   NSArray<NSString *> * _Nullable * _Nullable outputs,
                                   NSString * _Nullable * _Nullable report,
                                   NSString * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
