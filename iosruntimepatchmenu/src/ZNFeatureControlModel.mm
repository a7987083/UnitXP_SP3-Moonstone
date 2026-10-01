#import "ZNFeatureControlModel.h"
#import <objc/runtime.h>

NSNotificationName const ZNFeatureNumberValueDidChangeNotification = @"ZNFeatureNumberValueDidChangeNotification";
NSNotificationName const ZNFeatureSliderValueDidChangeNotification = @"ZNFeatureSliderValueDidChangeNotification";
NSNotificationName const ZNFeatureActionRequestedNotification = @"ZNFeatureActionRequestedNotification";

static const void *kZNFeatureControlTypeKey = &kZNFeatureControlTypeKey;
static const void *kZNFeatureValueTypeKey = &kZNFeatureValueTypeKey;

static NSString *ZNFCTrim(NSString *value) {
    return [value ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static BOOL ZNFCValidControlType(ZNFeatureControlType type) {
    switch (type) {
        case ZNFeatureControlTypeButton:
        case ZNFeatureControlTypeSwitch:
        case ZNFeatureControlTypeNumber:
        case ZNFeatureControlTypeSlider: return YES;
        default: return NO;
    }
}
static BOOL ZNFCValidValueType(ZNValueType type) { return type >= ZNValueTypeAuto && type <= ZNValueTypeF64; }
static BOOL ZNFCFeatureMatches(ZNBinaryPatchRow *row, NSString *featureName) {
    NSString *wanted = ZNFCTrim(featureName); if (!wanted.length) return NO;
    NSString *group = ZNFCTrim(row.group);
    if (!group.length || [group caseInsensitiveCompare:@"Imported"] == NSOrderedSame) group = ZNFCTrim(row.title);
    return [group caseInsensitiveCompare:wanted] == NSOrderedSame;
}
NSString *ZNFeatureControlTypeName(ZNFeatureControlType type) {
    switch (type) {
        case ZNFeatureControlTypeButton: return @"点击执行";
        case ZNFeatureControlTypeNumber: return @"输入";
        case ZNFeatureControlTypeSlider: return @"滑动条";
        case ZNFeatureControlTypeSwitch:
        default: return @"开关";
    }
}

@implementation ZNBinaryPatchRow (ZNFeatureControlModel)
- (ZNFeatureControlType)featureControlType { NSNumber *v=objc_getAssociatedObject(self,kZNFeatureControlTypeKey); if(!v)return ZNFeatureControlTypeSwitch; ZNFeatureControlType t=(ZNFeatureControlType)v.integerValue; return ZNFCValidControlType(t)?t:ZNFeatureControlTypeSwitch; }
- (void)setFeatureControlType:(ZNFeatureControlType)type { if(!ZNFCValidControlType(type))type=ZNFeatureControlTypeSwitch; objc_setAssociatedObject(self,kZNFeatureControlTypeKey,@(type),OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (ZNValueType)featureValueType { NSNumber *v=objc_getAssociatedObject(self,kZNFeatureValueTypeKey); if(!v)return ZNValueTypeAuto; ZNValueType t=(ZNValueType)v.integerValue; return ZNFCValidValueType(t)?t:ZNValueTypeAuto; }
- (void)setFeatureValueType:(ZNValueType)type { if(!ZNFCValidValueType(type))type=ZNValueTypeAuto; objc_setAssociatedObject(self,kZNFeatureValueTypeKey,@(type),OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

@implementation ZNBinaryPatchWorkspace (ZNFeatureControlEditingV2)
- (ZNFeatureControlType)controlTypeForFeature:(NSString *)featureName { for(ZNBinaryPatchRow *r in self.rows)if(ZNFCFeatureMatches(r,featureName))return r.featureControlType; return ZNFeatureControlTypeSwitch; }
- (BOOL)setControlType:(ZNFeatureControlType)type forFeature:(NSString *)featureName error:(NSString **)error { if(self.hasAnyApplied||self.isBuilding){if(error)*error=@"当前状态不可修改按钮类型";return NO;} if(!ZNFCValidControlType(type)){if(error)*error=@"按钮类型无效";return NO;} NSString *name=ZNFCTrim(featureName); if(!name.length){if(error)*error=@"功能名称为空";return NO;} NSUInteger changed=0; for(ZNBinaryPatchRow *r in self.rows)if(ZNFCFeatureMatches(r,name)){r.featureControlType=type;changed++;} if(!changed){if(error)*error=@"找不到要修改的功能";return NO;} self.lastStatus=[NSString stringWithFormat:@"%@：按钮类型 → %@",name,ZNFeatureControlTypeName(type)]; return YES; }
- (ZNValueType)valueTypeForFeature:(NSString *)featureName { for(ZNBinaryPatchRow *r in self.rows)if(ZNFCFeatureMatches(r,featureName))return r.featureValueType; return ZNValueTypeAuto; }
- (BOOL)setValueType:(ZNValueType)type forFeature:(NSString *)featureName error:(NSString **)error { if(self.hasAnyApplied||self.isBuilding){if(error)*error=@"当前状态不可修改数值类型";return NO;} if(!ZNFCValidValueType(type)){if(error)*error=@"数值类型无效";return NO;} NSString *name=ZNFCTrim(featureName); if(!name.length){if(error)*error=@"功能名称为空";return NO;} NSUInteger changed=0; for(ZNBinaryPatchRow *r in self.rows)if(ZNFCFeatureMatches(r,name)){r.featureValueType=type;changed++;} if(!changed){if(error)*error=@"找不到要修改的功能";return NO;} self.lastStatus=[NSString stringWithFormat:@"%@：数值类型 → %@",name,ZNValueTypeName(type)]; return YES; }
- (BOOL)removeFeatureNamed:(NSString *)featureName error:(NSString **)error { if(self.hasAnyApplied||self.isBuilding){if(error)*error=@"当前状态不可删除功能，请先恢复 Runtime Patch 或等待生成结束";return NO;} NSString *name=ZNFCTrim(featureName); if(!name.length){if(error)*error=@"功能名称为空";return NO;} NSIndexSet *indexes=[self.rows indexesOfObjectsPassingTest:^BOOL(ZNBinaryPatchRow *row,NSUInteger idx,BOOL *stop){(void)idx;(void)stop;return ZNFCFeatureMatches(row,name);}]; if(!indexes.count){if(error)*error=@"找不到要删除的功能";return NO;} NSUInteger count=indexes.count; [self.rows removeObjectsAtIndexes:indexes]; [self ensureDefaultRows]; self.lastStatus=[NSString stringWithFormat:@"已删除功能：%@（%lu Patch）",name,(unsigned long)count]; return YES; }
- (BOOL)removePatchAtGlobalIndex:(NSUInteger)index error:(NSString **)error { if(self.hasAnyApplied||self.isBuilding){if(error)*error=@"当前状态不可删除 Patch，请先恢复 Runtime Patch 或等待生成结束";return NO;} if(index>=self.rows.count){if(error)*error=@"Patch 索引越界";return NO;} ZNBinaryPatchRow *victim=self.rows[index]; NSString *featureName=ZNFCTrim(victim.group); if(!featureName.length||[featureName caseInsensitiveCompare:@"Imported"]==NSOrderedSame)featureName=ZNFCTrim(victim.title); ZNFeatureControlType preservedControl=[self controlTypeForFeature:featureName]; ZNValueType preservedValue=[self valueTypeForFeature:featureName]; NSString *title=ZNFCTrim(victim.title); if(!title.length)title=[NSString stringWithFormat:@"Patch #%lu",(unsigned long)index+1]; [self.rows removeObjectAtIndex:index]; NSUInteger serial=1; for(ZNBinaryPatchRow *r in self.rows){ if(!ZNFCFeatureMatches(r,featureName))continue; r.featureControlType=preservedControl; r.featureValueType=preservedValue; NSString *rowTitle=ZNFCTrim(r.title); if(!rowTitle.length||[rowTitle hasPrefix:@"Patch #"])r.title=[NSString stringWithFormat:@"Patch #%lu",(unsigned long)serial]; serial++; } [self ensureDefaultRows]; self.lastStatus=[NSString stringWithFormat:@"已删除 %@ · %@",featureName.length?featureName:@"功能",title]; return YES; }
@end

ZNFeatureControlType ZNFeatureControlTypeForFeatureName(NSString *featureName){return [[ZNBinaryPatchWorkspace sharedWorkspace] controlTypeForFeature:featureName?:@""];}
ZNValueType ZNFeatureValueTypeForFeatureName(NSString *featureName){return [[ZNBinaryPatchWorkspace sharedWorkspace] valueTypeForFeature:featureName?:@""];}
