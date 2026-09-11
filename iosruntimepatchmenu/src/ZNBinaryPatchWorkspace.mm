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

static NSString *ZNW44TargetForRow(ZNBinaryPatchRow *row, NSString *defaultTarget) {
    return (row.explicitTarget && row.target.length) ? row.target : (defaultTarget.length ? defaultTarget : @"main");
}

static NSString *ZNW44SiteKeyForRow(ZNBinaryPatchRow *row, NSString *defaultTarget) {
    uint64_t rva=0; if(row.validator) rva=row.validator.rva; else if(!ZNW44RVA(row.offsetText,&rva)) return nil;
    return [NSString stringWithFormat:@"%@|%llx",ZNW44TargetForRow(row,defaultTarget).lowercaseString,rva];
}

@interface ZNBinaryPatchWorkspace ()
@property(nonatomic,strong,readwrite) NSMutableArray<ZNBinaryPatchRow *> *rows;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *jsonFiles;
@property(nonatomic,copy,readwrite) NSArray<NSString *> *lastOutputPaths;
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *temporarySharedSessions;
@end

@implementation ZNBinaryPatchWorkspace
+ (instancetype)sharedWorkspace {
    static ZNBinaryPatchWorkspace *s; static dispatch_once_t onceToken;
    dispatch_once(&onceToken,^{s=[ZNBinaryPatchWorkspace new];}); return s;
}
- (instancetype)init {
    self=[super init]; if(!self)return nil;
    _rows=[NSMutableArray array]; _jsonFiles=@[]; _lastOutputPaths=@[]; _temporarySharedSessions=[NSMutableArray array];
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
    [self.temporarySharedSessions removeAllObjects];
    NSArray<NSDictionary *> *items=[ZNPatchJSONImporter importFile:path error:error]; if(!items)return NO;
    NSMutableArray *rows=[NSMutableArray array]; NSMutableDictionary<NSString *,NSMutableArray<ZNBinaryPatchRow *> *> *sites=[NSMutableDictionary dictionary];
    NSMutableSet *targets=[NSMutableSet set]; NSUInteger low=0; __block NSUInteger shared=0;
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
        (void)key;(void)stop; if(bucket.count<=1)return; shared++;
        NSMutableSet *v=[NSMutableSet set]; for(ZNBinaryPatchRow *r in bucket)[v addObject:r.enabledText.uppercaseString?:@""];
        NSString *status=v.count>1?@"↔ Shared Site：多个 Variant（临时应用/生成均合并）":@"↔ Shared Site：重复 Variant（临时应用/生成均合并）";
        for(ZNBinaryPatchRow *r in bucket){r.conflict=NO;if(!r.lowConfidence)r.statusText=status;}
    }];
    self.rows=rows; [self ensureDefaultRows]; if(targets.count==1)self.defaultTarget=targets.anyObject; self.showJSONFiles=NO;
    NSString *rel=[path hasPrefix:NSHomeDirectory()]?[path substringFromIndex:NSHomeDirectory().length]:path.lastPathComponent;
    self.lastStatus=[NSString stringWithFormat:@"已导入 %@ · Patch %lu · Shared Site %lu · 候选 %lu · JSON original 已忽略",rel,(unsigned long)items.count,(unsigned long)shared,(unsigned long)low]; return YES;
}
- (NSUInteger)filledCount { NSUInteger n=0;for(ZNBinaryPatchRow *r in self.rows)if(r.offsetText.length||r.enabledText.length)n++;return n; }
- (NSUInteger)validatedCount { NSUInteger n=0;for(ZNBinaryPatchRow *r in self.rows)if(r.validated)n++;return n; }
- (BOOL)hasAnyApplied {
    for(ZNBinaryPatchRow *r in self.rows)if(r.validator.isApplied)return YES;
    for(NSDictionary *session in self.temporarySharedSessions){ZNPatchRuntimeValidator *v=session[@"validator"];if(v.isApplied)return YES;}
    return NO;
}

- (void)znw44RecheckConflicts {
    // Same Target + same starting RVA is no longer a conflict. Static Builder
    // V2 merges those logical rows into one physical site and creates one
    // variant per unique Enabled byte sequence. Different-start partial overlap
    // is still rejected later by the Builder after exact byte lengths are known.
    NSMutableDictionary<NSString *,NSMutableArray<ZNBinaryPatchRow *> *> *sites=[NSMutableDictionary dictionary];
    for(ZNBinaryPatchRow *r in self.rows){r.conflict=NO;if(!r.offsetText.length&&!r.enabledText.length)continue;uint64_t v=0;if(!ZNW44RVA(r.offsetText,&v))continue;
        NSString *t=ZNW44TargetForRow(r,self.defaultTarget);NSString *key=[NSString stringWithFormat:@"%@|%llx",t.lowercaseString,v];if(!sites[key])sites[key]=[NSMutableArray array];[sites[key] addObject:r];}
    [sites enumerateKeysAndObjectsUsingBlock:^(NSString *key,NSMutableArray<ZNBinaryPatchRow *> *bucket,BOOL *stop){(void)key;(void)stop;if(bucket.count<=1)return;
        NSMutableSet *variants=[NSMutableSet set];for(ZNBinaryPatchRow *r in bucket)[variants addObject:r.enabledText.uppercaseString?:@""];
        NSString *s=variants.count>1?@"↔ Shared Site：多个 Variant":@"↔ Shared Site：重复 Variant";
        for(ZNBinaryPatchRow *r in bucket)if(!r.validated)r.statusText=s;
    }];
}

- (BOOL)znw44HasSharedSite {
    NSMutableSet<NSString *> *seen=[NSMutableSet set];
    for(ZNBinaryPatchRow *r in self.rows){
        if(!r.offsetText.length&&!r.enabledText.length)continue;uint64_t v=0;if(!ZNW44RVA(r.offsetText,&v))continue;
        NSString *t=ZNW44TargetForRow(r,self.defaultTarget);
        NSString *key=[NSString stringWithFormat:@"%@|%llx",t.lowercaseString,v];
        if([seen containsObject:key])return YES;[seen addObject:key];
    }
    return NO;
}

- (BOOL)validateAll:(NSString **)error {
    if(self.hasAnyApplied){if(error)*error=@"请先恢复当前临时 Patch";return NO;} [self.temporarySharedSessions removeAllObjects]; [self znw44RecheckConflicts];
    NSUInteger filled=0,ok=0,fail=0;NSString *first=nil;
    for(NSUInteger i=0;i<self.rows.count;i++){
        ZNBinaryPatchRow *r=self.rows[i]; if(!r.offsetText.length&&!r.enabledText.length){r.validated=NO;r.validator=nil;r.originalHex=@"";r.statusText=@"";continue;} filled++;
        if(r.conflict){fail++;if(!first)first=[NSString stringWithFormat:@"#%lu %@",(unsigned long)i+1,r.statusText];continue;}
        if(!r.offsetText.length||!r.enabledText.length){r.validated=NO;r.statusText=@"❌ Offset / Enabled 未填写完整";fail++;if(!first)first=[NSString stringWithFormat:@"#%lu 输入不完整",(unsigned long)i+1];continue;}
        NSString *t=ZNW44TargetForRow(r,self.defaultTarget); ZNPatchRuntimeValidator *v=[ZNPatchRuntimeValidator new];NSString *e=nil;
        if(![v configureTarget:t offsetString:r.offsetText patchHex:r.enabledText error:&e]||![v validate:&e]){r.validated=NO;r.validator=nil;r.originalHex=@"";r.statusText=[NSString stringWithFormat:@"❌ %@",e?:@"验证失败"];fail++;if(!first)first=[NSString stringWithFormat:@"#%lu %@",(unsigned long)i+1,e?:@"验证失败"];continue;}
        r.validator=v;r.validated=YES;r.offsetText=[NSString stringWithFormat:@"0x%llX",v.rva];r.enabledText=ZNW44Hex(v.patchBytes);r.originalHex=ZNW44Hex(v.capturedOriginalBytes);r.statusText=r.lowConfidence?@"✅ 已验证（候选确认）":@"✅ 已验证";ok++;
    }
    if(!filled){self.lastStatus=@"没有填写 Patch";if(error)*error=self.lastStatus;return NO;} self.lastStatus=[NSString stringWithFormat:@"读取验证：%lu/%lu 成功%@%@",(unsigned long)ok,(unsigned long)filled,fail?[NSString stringWithFormat:@" · %lu 失败",(unsigned long)fail]:@"",[self znw44HasSharedSite]?@" · Shared Site 已识别":@""];
    if(fail){if(error)*error=first?:@"存在验证失败项";return NO;}return YES;
}

- (BOOL)applyAll:(NSString **)error {
    if(!self.filledCount){if(error)*error=@"没有填写 Patch";return NO;}
    if(self.hasAnyApplied){if(error)*error=@"当前已有临时 Patch，请先恢复";return NO;}
    [self.temporarySharedSessions removeAllObjects];

    NSMutableDictionary<NSString *,NSMutableArray<ZNBinaryPatchRow *> *> *groups=[NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *order=[NSMutableArray array];
    for(NSUInteger i=0;i<self.rows.count;i++){
        ZNBinaryPatchRow *r=self.rows[i];
        if(!r.offsetText.length&&!r.enabledText.length)continue;
        if(!r.validated||!r.validator){if(error)*error=[NSString stringWithFormat:@"#%lu 尚未通过读取验证",(unsigned long)i+1];return NO;}
        NSString *key=ZNW44SiteKeyForRow(r,self.defaultTarget);
        if(!key.length){if(error)*error=[NSString stringWithFormat:@"#%lu Shared Site key 解析失败",(unsigned long)i+1];return NO;}
        if(!groups[key]){groups[key]=[NSMutableArray array];[order addObject:key];}
        [groups[key] addObject:r];
    }

    NSMutableArray<NSDictionary *> *done=[NSMutableArray array];
    NSUInteger logicalCount=0,sharedCount=0;
    NSString *failure=nil;
    NSArray<ZNBinaryPatchRow *> *failureRows=nil;

    for(NSString *key in order){
        NSArray<ZNBinaryPatchRow *> *bucket=[groups[key] copy];
        logicalCount+=bucket.count;
        ZNPatchRuntimeValidator *applyValidator=nil;
        BOOL shared=bucket.count>1;
        NSString *e=nil;

        if(!shared){
            applyValidator=bucket.firstObject.validator;
        }else{
            sharedCount++;
            ZNBinaryPatchRow *canonical=nil;
            NSUInteger window=0;
            for(ZNBinaryPatchRow *r in bucket){
                NSUInteger len=r.validator.patchBytes.length;
                if(len>window){window=len;canonical=r;}
            }
            if(!canonical||!window||canonical.validator.capturedOriginalBytes.length!=window){
                failure=@"Shared Site 缺少完整现场 Original"; failureRows=bucket; break;
            }

            NSData *siteOriginal=canonical.validator.capturedOriginalBytes;
            NSString *target=canonical.validator.target;
            uint64_t rva=canonical.validator.rva;
            for(ZNBinaryPatchRow *r in bucket){
                if([r.validator.target caseInsensitiveCompare:target]!=NSOrderedSame || r.validator.rva!=rva){
                    failure=@"Shared Site Target/RVA 不一致"; failureRows=bucket; break;
                }
                NSData *rowOriginal=r.validator.capturedOriginalBytes;
                if(!rowOriginal.length||rowOriginal.length>siteOriginal.length){failure=@"Shared Site Original 长度异常";failureRows=bucket;break;}
                NSData *prefix=[siteOriginal subdataWithRange:NSMakeRange(0,rowOriginal.length)];
                if(![prefix isEqualToData:rowOriginal]){failure=@"Shared Site 各 Variant 的现场 Original 前缀不一致";failureRows=bucket;break;}
            }
            if(failure)break;

            // 临时应用与生成后二进制保持同一规则：逻辑 owner 按导入顺序
            // 激活，最后一个 active owner 的 Variant 作为当前物理实现。
            ZNBinaryPatchRow *winner=bucket.lastObject;
            NSMutableData *variant=[siteOriginal mutableCopy];
            NSData *winnerBytes=winner.validator.patchBytes;
            if(!winnerBytes.length||winnerBytes.length>variant.length){failure=@"Shared Site winner Variant 长度异常";failureRows=bucket;break;}
            [variant replaceBytesInRange:NSMakeRange(0,winnerBytes.length) withBytes:winnerBytes.bytes];

            ZNPatchRuntimeValidator *sharedValidator=[ZNPatchRuntimeValidator new];
            NSString *offset=[NSString stringWithFormat:@"0x%llX",rva];
            if(![sharedValidator configureTarget:target offsetString:offset patchHex:ZNW44Hex(variant) error:&e]||
               ![sharedValidator validate:&e]){
                failure=e?:@"Shared Site 临时 Validator 预检失败"; failureRows=bucket; break;
            }
            applyValidator=sharedValidator;
        }

        if(![applyValidator applyTemporary:&e]){
            failure=e?:@"临时应用失败"; failureRows=bucket; break;
        }

        NSDictionary *session=@{@"validator":applyValidator,@"rows":bucket,@"shared":@(shared)};
        [done addObject:session];
        if(shared)[self.temporarySharedSessions addObject:session];
        for(ZNBinaryPatchRow *r in bucket)r.statusText=shared?@"✅ 临时已应用（Shared Site）":@"✅ 临时已应用";
    }

    if(failure){
        NSMutableArray *rollbackErrors=[NSMutableArray array];
        for(NSDictionary *session in [done reverseObjectEnumerator]){
            ZNPatchRuntimeValidator *v=session[@"validator"]; NSString *re=nil;
            if(v.isApplied&&![v restoreOriginal:&re])[rollbackErrors addObject:re?:@"回滚失败"];
            for(ZNBinaryPatchRow *r in session[@"rows"])r.statusText=@"✅ 已验证（已回滚）";
        }
        [self.temporarySharedSessions removeAllObjects];
        for(ZNBinaryPatchRow *r in failureRows)r.statusText=[NSString stringWithFormat:@"❌ %@",failure];
        self.lastStatus=[NSString stringWithFormat:@"临时应用失败；已事务回滚%@",rollbackErrors.count?@"（部分回滚失败）":@""];
        if(error)*error=rollbackErrors.count?[NSString stringWithFormat:@"%@；%@",failure,[rollbackErrors componentsJoinedByString:@" | "]]:failure;
        return NO;
    }

    self.lastStatus=[NSString stringWithFormat:@"临时应用成功：%lu 个 Patch%@ · 请回游戏验证功能",(unsigned long)logicalCount,sharedCount?[NSString stringWithFormat:@" · Shared Site %lu",(unsigned long)sharedCount]:@""];
    return YES;
}

- (BOOL)restoreAll:(NSString **)error {
    NSMutableArray *errs=[NSMutableArray array];NSUInteger n=0;

    for(NSDictionary *session in [self.temporarySharedSessions reverseObjectEnumerator]){
        ZNPatchRuntimeValidator *v=session[@"validator"]; NSArray<ZNBinaryPatchRow *> *rows=session[@"rows"];
        if(!v.isApplied)continue; NSString *e=nil;
        if(![v restoreOriginal:&e]){
            [errs addObject:e?:@"Shared Site 恢复失败"];
            for(ZNBinaryPatchRow *r in rows)r.statusText=[NSString stringWithFormat:@"❌ %@",e?:@"Shared Site 恢复失败"];
        }else{
            for(ZNBinaryPatchRow *r in rows)r.statusText=@"✅ 已验证";
            n+=rows.count;
        }
    }

    for(ZNBinaryPatchRow *r in [self.rows reverseObjectEnumerator]){
        if(!r.validator.isApplied)continue;NSString *e=nil;
        if(![r.validator restoreOriginal:&e]){[errs addObject:e?:@"恢复失败"];r.statusText=[NSString stringWithFormat:@"❌ %@",e?:@"恢复失败"];}else{r.statusText=@"✅ 已验证";n++;}
    }

    if(!errs.count)[self.temporarySharedSessions removeAllObjects];
    self.lastStatus=errs.count?[NSString stringWithFormat:@"恢复：%lu 成功 · %lu 失败",(unsigned long)n,(unsigned long)errs.count]:[NSString stringWithFormat:@"恢复完成：%lu 个 Patch",(unsigned long)n];
    if(errs.count){if(error)*error=[errs componentsJoinedByString:@" | "];return NO;}return YES;
}
- (void)setBuildOutputs:(NSArray<NSString *> *)paths status:(NSString *)status { self.lastOutputPaths=paths?:@[];self.lastStatus=status?:@""; }
@end
