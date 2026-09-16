#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Compile-time bridge only. ManualTaskEngineV05 stores UILabel instances in an
// NSMutableDictionary. Redeclaring keyed subscript lookup with the concrete
// UILabel return type lets Clang type-check `labels[@"key"].text` under the
// older MRC/Theos Objective-C mode. NSMutableDictionary's runtime implementation
// is unchanged.
@interface NSMutableDictionary (JCG5UILabelTypedSubscript)
- (UILabel *)objectForKeyedSubscript:(id)key;
@end
