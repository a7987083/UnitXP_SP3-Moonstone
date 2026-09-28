#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "ZNBinaryPatchWorkspace.h"
#import "ZNFeatureControlModel.h"
#import "ZNRuntimeActionModel.h"
#import "ZNPatchCore.h"

static NSString * const kZNM640ControlPrefix = @"zonoe.m6.4.offset-control.v1";

static NSString *ZNM640Trim(NSString *v){return [v?:@"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
static NSString *ZNM640Name(ZNBinaryPatchRow *row){NSString *g=ZNM640Trim(row.group);if(g.length&&[g caseInsensitiveCompare:@"Imported"]!=NSOrderedSame)return g;NSString *t=ZNM640Trim(row.title);return t.length?t:@"功能";}
static NSString *ZNM640ControlKey(ZNBinaryPatchRow *row){return [NSString stringWithFormat:@"%@.%@",kZNM640ControlPrefix,ZNM640Name(row).lowercaseString];}

@interface ZNBinaryPatchWorkspace (ZNM640ValidationBridge)
- (BOOL)znm640_validateAll:(NSString **)error;
@end

@implementation ZNBinaryPatchWorkspace (ZNM640ValidationBridge)
- (BOOL)znm640_validateAll:(NSString **)error {
    NSMutableArray<NSDictionary *> *restore=[NSMutableArray array];
    for(ZNBinaryPatchRow *row in self.rows){
        if(!row.offsetText.length)continue;
        NSString *key=[NSUserDefaults.standardUserDefaults stringForKey:ZNM640ControlKey(row)];
        if(!key.length)continue;
        ZNRuntimeArgumentControlType control=ZNRuntimeArgumentControlTypeFromKey(key);
        [restore addObject:@{@"row":row,@"type":@((NSInteger)row.featureControlType)}];
        row.featureControlType=(control==ZNRuntimeArgumentControlTypeSlider)?ZNFeatureControlTypeSlider:ZNFeatureControlTypeNumber;
    }
    BOOL ok=[self znm640_validateAll:error];
    for(NSDictionary *item in restore){ZNBinaryPatchRow *row=item[@"row"];row.featureControlType=(ZNFeatureControlType)[item[@"type"] integerValue];}
    return ok;
}
@end

extern "C" void ZNInstallM640AuthoringValidationBridgeDeferred(void){
    static dispatch_once_t once;dispatch_once(&once,^{
        Class cls=NSClassFromString(@"ZNBinaryPatchWorkspace");
        Method a=class_getInstanceMethod(cls,@selector(validateAll:));
        Method b=class_getInstanceMethod(cls,@selector(znm640_validateAll:));
        if(a&&b)method_exchangeImplementations(a,b);
        [[ZNRuntimeLogger sharedLogger]log:@"[m6.4-validation] unified Offset controls routed through existing preflight without adding UI layers"];
    });
}
