#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchJSONImporter.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"
#import <errno.h>
#import <stdlib.h>

@implementation ZNBinaryPatchRow
- (instancetype)init {
    self=[super init]; if(!self) return nil;
    _target=@""; _offsetText=@""; _enabledText=@""; _originalHex=@"";
    _title=@""; _group=@"Imported"; _sourcePath=@""; _statusText=@"";
    return self;
}
@end

static NSString *ZNW44Hex(NSData *data) {
    if(!data.length) return @""; const uint8_t *p=(const uint8_t *)data.bytes;
    NSMutableString *s=[NSMutableString stringWithCapacity:data.length*2];
    for(NSUInteger i=0;i<data.length;i++) [s appendFormat:@"%02X",p[i]];
    return s;
}

static BOOL ZNW44RVA(NSString *text,uint64_t *out) {
    NSString *s=[[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if(!s.length) return NO; const char *c=s.UTF8String; char *end=NULL; errno=0;
    unsigned long long v=strtoull(c,&end,0);
    if(errno||end==c||(end&&*end)){errno=0;end=NULL;v=strtoull(c,&end,16);} if(errno||end==c||(end&&*end)) return NO;
    if(out)*out=v; return YES;
}

@interface ZNBinaryPatchWorkspace ()
@property(nonatomic,strong,readwrite) NSMutableArray<ZNBinaryPatchRow *> *rows;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *jsonFiles;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *lastOutputPaths;
@end

@implementation ZNBinaryPatchWorkspace
+ (instancetype)sharedWorkspace {
    static ZNBinaryPatchWorkspace *s; static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{s=[ZNBinaryPatchWorkspace new];}); return s;
}
- (instancetype)init {
    self=[super init]; if(!self)return nil;
    _rows=[NSMutableArray array]; _jsonFiles=@[]; _lastOutputPaths=@[];
    NSString *name=[ZNModuleManager sharedManager].mainExecutable[@"name"];
    if(!name.length) name=[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
    _defaultTarget=name.length?name:@"main"; _lastStatus=@"等待输入或导入 JSON";
    [self ensureDefaultRows]; return self;
}
- (void)ensureDefaultRows { while(self.rows.count<10)[self.rows addObject:[ZNBinaryPatchRow new]]; }
- (void)addEmptyRow {
    if(self.hasAnyApplied){self.lastStatus=@"请先恢复当前临时 Patch";return;}
    [self.rows addObject:[ZNBinaryPatchRow new]]; self.lastStatus=[NSString stringWithFormat:@"已增加 Offset #%lu",(unsigned long)self.rows.count];
}
- (void)updateOffset:(NSString *)text row:(NSUInteger)i {
    if(self.hasAnyApplied||i>=self.rows.count)return; ZNBinaryPatchRow *r=self.rows[i];
    r.offsetText=text?:@""; r.validated=NO; r.validator=nil; r.originalHex=@""; r.statusText=@"";
}
- (void)updateEnabled:(NSString *)text row:(NSUInteger)i {
    if(self.hasAnyApplied||i>=self.rows.count)return; ZNBinaryPatchRow *r=self.rows[i];
    r.enabledText=text?:@""; r.validated=NO; r.validator=nil; r.originalHex=@""; r.statusText=@"";
}
- (void)updateDefaultTarget:(NSString *)text {
    if(self.hasAnyApplied)return; NSString *t=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.defaultTarget=t.length?t:@"main";
    for(ZNBinaryPatchRow *r in self.rows) if(!r.explicitTarget){r.validated=NO;r.validator=nil;r.originalHex=@"";r.statusText=@"";}
}
- (void)refreshJSONFiles {
    self.jsonFiles=[ZNPatchJSONImporter discoverJSONFiles];
    self.lastStatus=self.jsonFiles.count?[NSString stringWithFormat:@"发现 %lu 个 JSON",(unsigned long)self.jsonFiles.count]:@"游戏数据目录未发现 JSON";
}
- (BOOL)importJSONAtPath:(NSString *)path error:(NSString **)error {
    if(self.hasAnyApplied){if(error)*error=@"请先恢复当前临时 Patch";return NO;}
    NSArray<NSDictionary *> *items=[ZNPatchJSONImporter importFile:path error:error]; if(!items)return NO;
    NSMutableArray *rows=[NSMutableArray array]; NSMutableDictionary<NSString *,NSMutableArray<ZNBinaryPatchRow *> *> *sites=[NSMutableDictionary dictionary];
    NSMutableSet *targets=[NSMutableSet set]; NSUInteger low=0;
    for(NSDictionary *item in items){
        ZNBinaryPatchRow *r=[ZNBinaryPatchRow new]; r.target=item[@"target"]?:@""; r.explicitTarget=r.target.length>0;
        r.offsetText=item[@"offset"]?:@""; r.enabledText=item[@"enabled"]?:@""; r.title=[item[@"title"] length]?item[@"title"]:[NSString stringWithFormat:@"Patch #%lu",(unsigned long)rows.count+1];
        r.group=[item[@"group"] length]?item[@"group"]:@"Imported"; r.sourcePath=item[@"path"]?:@"$";
        r.lowConfidence=[item[@"confidence"] doubleValue]<0.8; if(r.lowConfidence)low++;
        r.statusText=r.lowConfidence?@"⚠ 候选，需读取验证":@"待验证"; [rows addObject:r]; if(r.target.length)[targets addObject:r.target];
        NSString *site=[NSString stringWithFormat:@"%@|%@",(r.target.length?r.target:self.defaultTarget).lowercaseString,r.offsetText.lowercaseString];
        if(!sites[site])sites[site]=[NSMutableArray array]; [sites[site] addObject:r];
    }
    [sites enumerateKeysAndObjectsUsingBlock:^(NSString *key,NSMutableArray<ZNBinaryPatchRow *> *bucket,BOOL *stop){
        (void)key;(void)stop; if(bucket.count<=1)return; NSMutableSet *v=[NSMutableSet set]; for(ZNBinaryPatchRow *r in bucket)[v addObject:r.enabledText.uppercaseString?:@""];
        if(v.count>1)for(ZNBinaryPatchRow *r in bucket){r.conflict=YES;r.statusText=@"⚠ 同一 Offset 存在多个 Enabled";}
    }];
    self.rows=rows; [self ensureDefaultRows]; if(targets.count==1)self.defaultTarget=targets.anyObject; self.showJSONFiles=NO;
    NSString *rel=[path hasPrefix:NSHomeDirectory()]?[path substringFromIndex:NSHomeDirectory().length]:path.lastPathComponent;
    self.lastStatus=[NSString stringWithFormat:@"已导入 %@ · Patch %lu · 候选 %lu · JSON original 已忽略",rel,(unsigned long)items.count,(unsigned long)low]; return YES;
}
- (NSUInteger)filledCount { NSUInteger n=0;for(ZNBinaryPatchRow *r in self.rows)if(r.offsetText.length||r.enabledText.length)n++;return n; }
- (NSUInteger)validatedCount { NSUInteger n=0;for(ZNBinaryPatchRow *r in self.rows)if(r.validated)n++;return n; }
- (BOOL)hasAnyApplied { for(ZNBinaryPatchRow *r in self.rows)if(r.validator.isApplied)return YES;return NO; }

- (void)znw44RecheckConflicts {
    NSMutableDictionary<NSString *,NSMutableArray<ZNBinaryPatchRow *> *> *sites=[NSMutableDictionary dictionary];
    for(ZNBinaryPatchRow *r in self.rows){r.conflict=NO;if(!r.offsetText.length&&!r.enabledText.length)continue;uint64_t v=0;if(!ZNW44RVA(r.offsetText,&v))continue;
        NSString *t=(r.explicitTarget&&r.target.length)?r.target:self.defaultTarget;NSString *key=[NSString stringWithFormat:@"%@|%llx",t.lowercaseString,v];if(!sites[key])sites[key]=[NSMutableArray array];[sites[key] addObject:r];}
    [sites enumerateKeysAndObjectsUsingBlock:^(NSString *key,NSMutableArray<ZNBinaryPatchRow *> *bucket,BOOL *stop){(void)key;(void)stop;if(bucket.count<=1)return;for(ZNBinaryPatchRow *r in bucket){r.conflict=YES;r.validated=NO;r.statusText=@"❌ 同一 Target + Offset 重复/冲突";}}];
}

- (BOOL)validateAll:(NSString **)error {
    if(self.hasAnyApplied){if(error)*error=@"请先恢复当前临时 Patch";return NO;} [self znw44RecheckConflicts];
    NSUInteger filled=0,ok=0,fail=0;NSString *first=nil;
    for(NSUInteger i=0;i<self.rows.count;i++){
        ZNBinaryPatchRow *r=self.rows[i]; if(!r.offsetText.length&&!r.enabledText.length){r.validated=NO;r.validator=nil;r.originalHex=@"";r.statusText=@"";continue;} filled++;
        if(r.conflict){fail++;if(!first)first=[NSString stringWithFormat:@"#%lu %@",(unsigned long)i+1,r.statusText];continue;}
        if(!r.offsetText.length||!r.enabledText.length){r.validated=NO;r.statusText=@"❌ Offset / Enabled 未填写完整";fail++;if(!first)first=[NSString stringWithFormat:@"#%lu 输入不完整",(unsigned long)i+1];continue;}
        NSString *t=(r.explicitTarget&&r.target.length)?r.target:self.defaultTarget; ZNPatchRuntimeValidator *v=[ZNPatchRuntimeValidator new];NSString *e=nil;
        if(![v configureTarget:t offsetString:r.offsetText patchHex:r.enabledText error:&e]||![v validate:&e]){r.validated=NO;r.validator=nil;r.originalHex=@"";r.statusText=[NSString stringWithFormat:@"❌ %@",e?:@"验证失败"];fail++;if(!first)first=[NSString stringWithFormat:@"#%lu %@",(unsigned long)i+1,e?:@"验证失败"];continue;}
        r.validator=v;r.validated=YES;r.offsetText=[NSString stringWithFormat:@"0x%llX",v.rva];r.enabledText=ZNW44Hex(v.patchBytes);r.originalHex=ZNW44Hex(v.capturedOriginalBytes);r.statusText=r.lowConfidence?@"✅ 已验证（候选确认）":@"✅ 已验证";ok++;
    }
    if(!filled){self.lastStatus=@"没有填写 Patch";if(error)*error=self.lastStatus;return NO;} self.lastStatus=[NSString stringWithFormat:@"读取验证：%lu/%lu 成功%@",(unsigned long)ok,(unsigned long)filled,fail?[NSString stringWithFormat:@" · %lu 失败",(unsigned long)fail]:@""];
    if(fail){if(error)*error=first?:@"存在验证失败项";return NO;}return YES;
}

- (BOOL)applyAll:(NSString **)error {
    if(!self.filledCount){if(error)*error=@"没有填写 Patch";return NO;} if(self.hasAnyApplied){if(error)*error=@"当前已有临时 Patch，请先恢复";return NO;}
    NSMutableArray<ZNBinaryPatchRow *> *done=[NSMutableArray array];
    for(NSUInteger i=0;i<self.rows.count;i++){
        ZNBinaryPatchRow *r=self.rows[i];if(!r.offsetText.length&&!r.enabledText.length)continue;if(!r.validated||!r.validator){if(error)*error=[NSString stringWithFormat:@"#%lu 尚未通过读取验证",(unsigned long)i+1];return NO;}
        NSString *e=nil;if(![r.validator applyTemporary:&e]){NSMutableArray *re=[NSMutableArray array];for(ZNBinaryPatchRow *x in [done reverseObjectEnumerator]){NSString *xerr=nil;if(![x.validator restoreOriginal:&xerr])[re addObject:xerr?:@"回滚失败"];else x.statusText=@"✅ 已验证（已回滚）";}
            r.statusText=[NSString stringWithFormat:@"❌ %@",e?:@"临时应用失败"];self.lastStatus=[NSString stringWithFormat:@"批量应用失败于 #%lu；已事务回滚%@",(unsigned long)i+1,re.count?@"（部分失败）":@""];if(error)*error=re.count?[NSString stringWithFormat:@"%@；%@",e?:@"应用失败",[re componentsJoinedByString:@" | "]]:(e?:@"应用失败");return NO;}
        r.statusText=@"✅ 临时已应用";[done addObject:r];
    }
    self.lastStatus=[NSString stringWithFormat:@"临时应用成功：%lu 项 · 请回游戏验证功能",(unsigned long)done.count];return YES;
}
- (BOOL)restoreAll:(NSString **)error {
    NSMutableArray *errs=[NSMutableArray array];NSUInteger n=0;
    for(ZNBinaryPatchRow *r in [self.rows reverseObjectEnumerator]){if(!r.validator.isApplied)continue;NSString *e=nil;if(![r.validator restoreOriginal:&e]){[errs addObject:e?:@"恢复失败"];r.statusText=[NSString stringWithFormat:@"❌ %@",e?:@"恢复失败"];}else{r.statusText=@"✅ 已验证";n++;}}
    self.lastStatus=errs.count?[NSString stringWithFormat:@"恢复：%lu 成功 · %lu 失败",(unsigned long)n,(unsigned long)errs.count]:[NSString stringWithFormat:@"恢复完成：%lu 项",(unsigned long)n];if(errs.count){if(error)*error=[errs componentsJoinedByString:@" | "];return NO;}return YES;
}
- (void)setBuildOutputs:(NSArray<NSString *> *)paths status:(NSString *)status { self.lastOutputPaths=paths?:@[];self.lastStatus=status?:@""; }
@end
