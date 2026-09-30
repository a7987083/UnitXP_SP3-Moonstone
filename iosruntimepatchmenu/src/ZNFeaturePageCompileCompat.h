#import <Foundation/Foundation.h>

// Compile-time only declaration for Objective-C dot-syntax on values pulled from
// NSArray without lightweight generics. No implementation is provided here;
// actual ZNFeaturePageItem instances implement -backingRecord.
@interface NSObject (ZNFeaturePageCompileCompat)
@property(nonatomic,strong,nullable) id backingRecord;
@end
