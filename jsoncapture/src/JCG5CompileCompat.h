#import <Foundation/Foundation.h>

// Compile-time declaration only. The v0.5 UI dictionary stores UILabel objects,
// but the property is intentionally kept as an untyped NSMutableDictionary for
// MRC/Theos compatibility. Declaring -text/-setText: on NSObject lets Clang
// type-check dot syntax on values returned as id; runtime dispatch still goes
// to UILabel's real implementation.
@interface NSObject (JCG5UILabelTextCompileBridge)
@property(nonatomic, copy) NSString *text;
@end
