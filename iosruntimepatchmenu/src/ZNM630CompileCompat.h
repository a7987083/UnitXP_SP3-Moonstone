#pragma once
#import <Foundation/Foundation.h>

// Compile-time declaration only. The canonical authoring renderer stores
// concrete ZNBinaryPatchRow objects in Foundation collections; Objective-C++
// loses lightweight-generic information after an untyped local NSArray. This
// declaration lets dot syntax resolve the existing `title` accessor without
// adding a runtime category or another UI layer.
@interface NSObject (ZNM630TitleCompileSurface)
@property(nonatomic,copy) NSString *title;
@end
