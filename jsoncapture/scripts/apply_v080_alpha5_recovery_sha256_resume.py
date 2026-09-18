#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
recp = root / "src" / "OnDeviceLuaRecovery.m"
mainp = root / "src" / "ManualTaskEngineV05.m"
r = recp.read_text(encoding="utf-8")
m = mainp.read_text(encoding="utf-8")
MARKER = "ODLR_V080_ALPHA5_SHA256_RESUME"
if MARKER in r and "JCG5_V080_ALPHA5_RECOVERY_SHA256_RESUME" in m:
    print("alpha5 recovery SHA256 resume already applied")
    raise SystemExit(0)
if "ODLR_V080_MEMSAFE_G5" not in r:
    raise SystemExit("memsafe recovery baseline marker missing")
if "JCG5_V080_ALPHA4_STABILITY" not in m:
    raise SystemExit("alpha4 stability marker missing")

# Replace the recovery directory driver. ODLRRecoverGroup itself stays the
# memsafe-g5 implementation, so recovery semantics/beam scoring are unchanged.
start = r.find('NSDictionary *ODLRRecoverDecodedDirectory(NSString *decodedDirectory, NSString *outputRoot, BOOL forceAll, ODLRShouldYieldBlock shouldYield, ODLRProgressBlock progress) {')
end = r.find('\nNSDictionary *ODLRQueueSnapshot(', start)
if start < 0 or end < 0:
    raise SystemExit('ODLRRecoverDecodedDirectory boundaries missing')

new_driver = r'''// ODLR_V080_ALPHA5_SHA256_RESUME
// Recovery.SHA256.txt is both a user-readable file hash list and a lightweight
// crash-resume journal. FILE records are followed by one GROUP commit marker;
// a group is skipped only when its source signature matches AND every recorded
// output still exists with the exact full SHA-256.
static NSString * const kODLRRecoverySHA256ManifestName = @"Recovery.SHA256.txt";

static NSString *ODLRFileSHA256(NSString *path) {
    if (!path.length) return @"";
    NSInputStream *stream=[NSInputStream inputStreamWithFileAtPath:path];
    if (!stream) return @"";
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx); [stream open];
    uint8_t buf[64*1024]; BOOL ok=YES;
    for (;;) {
        NSInteger n=[stream read:buf maxLength:sizeof(buf)];
        if (n>0) { CC_SHA256_Update(&ctx,buf,(CC_LONG)n); continue; }
        if (n==0) break;
        ok=NO; break;
    }
    [stream close];
    if (!ok) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest,&ctx);
    NSMutableString *s=[NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for (NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [s appendFormat:@"%02x",digest[i]];
    return s;
}

static NSString *ODLRManifestSafeField(NSString *s) {
    NSString *v=s?:@"";
    v=[v stringByReplacingOccurrencesOfString:@"\t" withString:@"_"];
    v=[v stringByReplacingOccurrencesOfString:@"\r" withString:@"_"];
    v=[v stringByReplacingOccurrencesOfString:@"\n" withString:@"_"];
    return v;
}

static NSString *ODLRRelativeOutputPath(NSString *path, NSString *outputRoot) {
    if (!path.length) return @"";
    NSString *prefix=[outputRoot stringByAppendingString:@"/"];
    return [path hasPrefix:prefix] ? [path substringFromIndex:prefix.length] : path.lastPathComponent;
}

static NSString *ODLRStoredOutputPath(NSString *stored, NSString *outputRoot) {
    if (!stored.length) return @"";
    if ([stored hasPrefix:@"/"]) return stored;
    return [outputRoot stringByAppendingPathComponent:stored];
}

static NSString *ODLRManifestKey(NSString *group, NSString *signature) {
    return [NSString stringWithFormat:@"%@\n%@",group?:@"",signature?:@""];
}

static NSMutableDictionary *ODLRLoadRecoveryManifest(NSString *path) {
    NSMutableDictionary *map=[NSMutableDictionary dictionary];
    NSString *text=[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return map;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if (!line.length || [line hasPrefix:@"#"]) continue;
        NSArray *p=[line componentsSeparatedByString:@"\t"];
        if (p.count<4) continue;
        NSString *kind=p[0],*group=p[1],*sig=p[2],*key=ODLRManifestKey(group,sig);
        NSMutableDictionary *e=map[key];
        if (!e) { e=[NSMutableDictionary dictionaryWithObject:[NSMutableDictionary dictionary] forKey:@"files"]; map[key]=e; }
        if ([kind isEqualToString:@"FILE"] && p.count>=5) {
            NSString *sha=p[3],*rel=p[4];
            if (sha.length==64 && rel.length) e[@"files"][rel]=sha;
        } else if ([kind isEqualToString:@"GROUP"] && p.count>=5) {
            e[@"expected"]=@([p[3] integerValue]); e[@"status"]=p[4]?:@"unknown"; e[@"committed"]=@YES;
        }
    }
    return map;
}

static NSArray *ODLRManifestRecords(NSDictionary *entry) {
    NSDictionary *files=[entry[@"files"] isKindOfClass:[NSDictionary class]]?entry[@"files"]:@{};
    NSMutableArray *out=[NSMutableArray array];
    for (NSString *rel in [[files allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
        [out addObject:@{ @"path":rel, @"sha256":files[rel]?:@"" }];
    return out;
}

static BOOL ODLRValidateManifestEntry(NSDictionary *entry, NSString *outputRoot) {
    if (![entry[@"committed"] boolValue]) return NO;
    NSArray *records=ODLRManifestRecords(entry); NSInteger expected=[entry[@"expected"] integerValue];
    if ((NSInteger)records.count!=expected) return NO;
    for (NSDictionary *rec in records) {
        NSString *expectedSHA=rec[@"sha256"],*path=ODLRStoredOutputPath(rec[@"path"],outputRoot);
        NSString *actual=ODLRFileSHA256(path);
        if (!actual.length || ![actual isEqualToString:expectedSHA]) return NO;
    }
    return YES;
}

static NSArray *ODLROutputRecordsForResult(NSDictionary *result, NSString *outputRoot) {
    NSMutableDictionary *byPath=[NSMutableDictionary dictionary];
    for (NSDictionary *t in ([result[@"tables"] isKindOfClass:[NSArray class]]?result[@"tables"]:@[])) {
        NSString *path=[t[@"file"] isKindOfClass:[NSString class]]?t[@"file"]:@"";
        NSString *sha=ODLRFileSHA256(path);
        NSString *rel=ODLRRelativeOutputPath(path,outputRoot);
        if (sha.length==64 && rel.length) byPath[rel]=sha;
    }
    NSMutableArray *out=[NSMutableArray array];
    for (NSString *rel in [[byPath allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])
        [out addObject:@{ @"path":rel, @"sha256":byPath[rel] }];
    return out;
}

static void ODLREnsureManifestHeader(NSString *path) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return;
    NSString *h=@"# JSONCapture Recovery SHA256 v1\n# FILE\\tgroup\\tsource_signature_sha256\\toutput_sha256\\trelative_path\n# GROUP\\tgroup\\tsource_signature_sha256\\toutput_count\\tstatus\n";
    [h writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void ODLRAppendManifestCommit(NSString *path, NSString *group, NSString *signature, NSArray *records, NSString *status) {
    ODLREnsureManifestHeader(path);
    NSMutableString *chunk=[NSMutableString string]; NSString *g=ODLRManifestSafeField(group),*sig=ODLRManifestSafeField(signature);
    for (NSDictionary *rec in records)
        [chunk appendFormat:@"FILE\t%@\t%@\t%@\t%@\n",g,sig,ODLRManifestSafeField(rec[@"sha256"]),ODLRManifestSafeField(rec[@"path"])];
    [chunk appendFormat:@"GROUP\t%@\t%@\t%lu\t%@\n",g,sig,(unsigned long)records.count,ODLRManifestSafeField(status?:@"unknown")];
    NSFileHandle *fh=[NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) return;
    @try { [fh seekToEndOfFile]; [fh writeData:[chunk dataUsingEncoding:NSUTF8StringEncoding]]; }
    @catch (__unused NSException *e) {}
    [fh closeFile];
}

static void ODLRCompactRecoveryManifest(NSString *path, NSDictionary *processed) {
    NSMutableString *text=[NSMutableString stringWithString:@"# JSONCapture Recovery SHA256 v1\n# FILE\\tgroup\\tsource_signature_sha256\\toutput_sha256\\trelative_path\n# GROUP\\tgroup\\tsource_signature_sha256\\toutput_count\\tstatus\n"];
    NSArray *groups=[[processed allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *group in groups) {
        NSDictionary *e=processed[group]; NSString *sig=e[@"signature"]?:@"",*status=e[@"status"]?:@"unknown";
        NSArray *records=[e[@"outputs"] isKindOfClass:[NSArray class]]?e[@"outputs"]:@[];
        for (NSDictionary *rec in records)
            [text appendFormat:@"FILE\t%@\t%@\t%@\t%@\n",ODLRManifestSafeField(group),ODLRManifestSafeField(sig),ODLRManifestSafeField(rec[@"sha256"]),ODLRManifestSafeField(rec[@"path"])];
        [text appendFormat:@"GROUP\t%@\t%@\t%lu\t%@\n",ODLRManifestSafeField(group),ODLRManifestSafeField(sig),(unsigned long)records.count,ODLRManifestSafeField(status)];
    }
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void ODLRRemoveRecordedOutputs(NSDictionary *processedEntry, NSDictionary *reportEntry, NSString *outputRoot) {
    NSFileManager *fm=[NSFileManager defaultManager]; NSString *prefix=[outputRoot stringByAppendingString:@"/"];
    for (NSDictionary *rec in ([processedEntry[@"outputs"] isKindOfClass:[NSArray class]]?processedEntry[@"outputs"]:@[])) {
        NSString *p=ODLRStoredOutputPath(rec[@"path"],outputRoot); if ([p hasPrefix:prefix]) [fm removeItemAtPath:p error:nil];
    }
    for (NSDictionary *t in ([reportEntry[@"tables"] isKindOfClass:[NSArray class]]?reportEntry[@"tables"]:@[])) {
        NSString *p=t[@"file"]; if ([p isKindOfClass:[NSString class]] && [p hasPrefix:prefix]) [fm removeItemAtPath:p error:nil];
    }
}

NSDictionary *ODLRRecoverDecodedDirectory(NSString *decodedDirectory, NSString *outputRoot, BOOL forceAll, ODLRShouldYieldBlock shouldYield, ODLRProgressBlock progress) {
    NSFileManager *fm=[NSFileManager defaultManager];
    NSString *completeDir=[outputRoot stringByAppendingPathComponent:@"recovered_json"],*partialDir=[outputRoot stringByAppendingPathComponent:@"recovered_partial"],*dynamicDir=[outputRoot stringByAppendingPathComponent:@"dynamic_lua"];
    for (NSString*d in @[completeDir,partialDir,dynamicDir]) [fm createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];

    NSMutableDictionary *groups=[NSMutableDictionary dictionary],*groupSHAs=[NSMutableDictionary dictionary];
    for (NSString *path in ODLRFilesInDirectory(decodedDirectory)) {
        NSDictionary*e=ODLRFileEntry(path); if(!e)continue; NSString*g=e[@"group"];
        NSMutableArray*a=groups[g]; if(!a){a=[NSMutableArray array];groups[g]=a;} [a addObject:e];
        NSMutableArray*hs=groupSHAs[g]; if(!hs){hs=[NSMutableArray array];groupSHAs[g]=hs;} [hs addObject:e[@"sha"]];
    }

    NSString *indexPath=[outputRoot stringByAppendingPathComponent:kODLRRecoveryIndexName];
    NSDictionary *oldIndex=ODLRReadJSONDictionary(indexPath);
    NSMutableDictionary *processed=[NSMutableDictionary dictionaryWithDictionary:[oldIndex[@"groups"] isKindOfClass:[NSDictionary class]]?oldIndex[@"groups"]:@{}];
    NSString *reportPath=[outputRoot stringByAppendingPathComponent:kODLRRecoveryReportName];
    NSDictionary *oldReport=ODLRReadJSONDictionary(reportPath);
    NSMutableDictionary *reportGroups=[NSMutableDictionary dictionaryWithDictionary:[oldReport[@"groups"] isKindOfClass:[NSDictionary class]]?oldReport[@"groups"]:@{}];
    NSString *manifestPath=[outputRoot stringByAppendingPathComponent:kODLRRecoverySHA256ManifestName];
    NSMutableDictionary *manifest=ODLRLoadRecoveryManifest(manifestPath);

    NSArray *sorted=[[groups allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    unsigned long long attempted=0,changed=0,written=0,skipped=0; BOOL yielded=NO;
    for (NSString *group in sorted) {@autoreleasepool {
        if(shouldYield&&shouldYield()){yielded=YES;break;}
        NSArray *shas=[groupSHAs[group] sortedArrayUsingSelector:@selector(compare:)];
        NSString *signature=ODLRSHA256([[shas componentsJoinedByString:@"|"] dataUsingEncoding:NSUTF8StringEncoding]);
        NSString *mkey=ODLRManifestKey(group,signature); NSDictionary *me=manifest[mkey]; NSDictionary *pe=processed[group]; NSDictionary *oldResult=reportGroups[group];

        if (!forceAll) {
            BOOL verified=ODLRValidateManifestEntry(me,outputRoot);
            NSArray *records=verified?ODLRManifestRecords(me):nil;
            NSString *status=verified?(me[@"status"]?:pe[@"status"]?:@"unknown"):@"";
            if (!verified && [pe[@"signature"] isEqualToString:signature]) {
                NSArray *migrated=ODLROutputRecordsForResult(oldResult,outputRoot);
                NSString *oldStatus=pe[@"status"]?:oldResult[@"status"]?:@"unknown";
                BOOL zeroOK=migrated.count==0 && ([oldStatus isEqualToString:@"dynamic"] || [oldStatus isEqualToString:@"static-no-table"]);
                BOOL filesOK=migrated.count>0;
                for (NSDictionary *rec in migrated) if (!ODLRFileSHA256(ODLRStoredOutputPath(rec[@"path"],outputRoot)).length) { filesOK=NO; break; }
                if (filesOK || zeroOK) {
                    ODLRAppendManifestCommit(manifestPath,group,signature,migrated,oldStatus);
                    NSMutableDictionary *ne=[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSMutableDictionary dictionary],@"files",@(migrated.count),@"expected",oldStatus,@"status",@YES,@"committed",nil];
                    for(NSDictionary *rec in migrated) ne[@"files"][rec[@"path"]]=rec[@"sha256"];
                    manifest[mkey]=ne; verified=YES; records=migrated; status=oldStatus;
                }
            }
            if (verified) {
                skipped++;
                processed[group]=@{ @"signature":signature,@"status":status?:@"unknown",@"outputs":records?:@[],@"verified_at":@([[NSDate date] timeIntervalSince1970]) };
                if(progress)progress(@{ @"stage":@"recover_skip",@"group":group,@"groups_total":@(sorted.count),@"skipped_verified":@(skipped),@"status":status?:@"unknown",@"outputs":@((records?:@[]).count) });
                continue;
            }
        }

        attempted++;
        if(progress)progress(@{ @"stage":@"recover_begin",@"group":group,@"attempted":@(attempted),@"groups_total":@(sorted.count),@"variants":@([groups[group] count]) });
        ODLRRemoveRecordedOutputs(pe,oldResult,outputRoot);
        BOOL didWrite=NO; NSDictionary *result=ODLRRecoverGroup(group,groups[group],completeDir,partialDir,&didWrite);
        NSArray *outputs=ODLROutputRecordsForResult(result,outputRoot); NSString *status=result[@"status"]?:@"unknown";
        ODLRAppendManifestCommit(manifestPath,group,signature,outputs,status);
        NSMutableDictionary *ne=[NSMutableDictionary dictionaryWithObjectsAndKeys:[NSMutableDictionary dictionary],@"files",@(outputs.count),@"expected",status,@"status",@YES,@"committed",nil];
        for(NSDictionary *rec in outputs) ne[@"files"][rec[@"path"]]=rec[@"sha256"];
        manifest[mkey]=ne;
        reportGroups[group]=result;
        processed[group]=@{ @"signature":signature,@"status":status,@"outputs":outputs,@"updated_at":@([[NSDate date] timeIntervalSince1970]) };
        changed++; if(didWrite)written++;
        if(progress)progress(@{ @"stage":@"recover_end",@"group":group,@"attempted":@(attempted),@"groups_total":@(sorted.count),@"status":status,@"written":@(didWrite),@"records":result[@"records"]?:@0,@"outputs":@(outputs.count) });
    }}

    NSDictionary *summary=ODLRBuildSummary(reportGroups);
    ODLRWriteJSON(@{ @"version":ODLR_VERSION,@"groups":processed,@"updated_at":@([[NSDate date] timeIntervalSince1970]) },indexPath);
    ODLRWriteJSON(@{ @"version":ODLR_VERSION,@"summary":summary,@"groups":reportGroups,@"updated_at":@([[NSDate date] timeIntervalSince1970]) },reportPath);
    ODLRCompactRecoveryManifest(manifestPath,processed);
    NSMutableDictionary *status=[NSMutableDictionary dictionaryWithDictionary:summary];
    status[@"version"]=ODLR_VERSION; status[@"attempted_this_run"]=@(attempted); status[@"groups_changed_this_run"]=@(changed); status[@"groups_written_this_run"]=@(written); status[@"skipped_verified_this_run"]=@(skipped); status[@"yielded_for_capture"]=@(yielded); status[@"sha256_manifest"]=manifestPath.lastPathComponent; status[@"updated_at"]=@([[NSDate date] timeIntervalSince1970]);
    ODLRWriteJSON(status,[outputRoot stringByAppendingPathComponent:kODLRRecoveryStatusName]);
    return status;
}
'''
r = r[:start] + new_driver + r[end:]

# Normal recovery must be incremental.  Retry-failed remains forced for the
# selected failed groups.  Crucially, normal start no longer deletes outputs,
# report/index, or the SHA256 journal.
start = m.find('static void JCG5RunRecover(BOOL retryOnly) {')
end = m.find('\nstatic void JCG5RequestTask(', start)
if start < 0 or end < 0:
    raise SystemExit('JCG5RunRecover boundaries missing')
new_main = r'''static void JCG5RunRecover(BOOL retryOnly) {
    @autoreleasepool{
        NSString*input=gJCG5DecodedDir;
        if(retryOnly){
            NSArray*groups=JCG5ReadFailureItems(@"Recovery.failures.json"); NSMutableArray*names=[NSMutableArray array];
            for(id x in groups){if([x isKindOfClass:[NSDictionary class]]&&[x[@"group"] length])[names addObject:x[@"group"]];else if([x isKindOfClass:[NSString class]])[names addObject:x];}
            if(!names.count){JCG5FinishTask(@"JSON恢复：没有失败组可重试");return;}
            input=JCG5BuildRetryRecoveryDir(names);
        } else {
            // Alpha5 incremental mode: preserve recovered_json / recovered_partial,
            // MobileRecovery.index.json and Recovery.SHA256.txt across runs.
            for(NSString *dir in @[gJCG5RecoveredDir,gJCG5PartialDir]) JCG5EnsureDir(dir);
        }
        pthread_mutex_lock(&gJCG5StateLock); [gJCG5RecoverState release]; gJCG5RecoverState=[(retryOnly?@"重试失败中":@"增量恢复中") copy];
        gJCG5RecoverComplete=gJCG5RecoverPartial=gJCG5RecoverFailed=gJCG5RecoverRecords=0; pthread_mutex_unlock(&gJCG5StateLock);
        NSUInteger inputFiles=[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:input error:nil] count];
        NSString *manifest=[gJCG5Root stringByAppendingPathComponent:@"Recovery.SHA256.txt"];
        JCG5Log([NSString stringWithFormat:@"RECOVERY start input=%@ decoded_files=%lu engine=OnDeviceLuaRecovery-alpha5-sha256-resume retry=%d forceAll=%d manifest=%@",input?:@"",(unsigned long)inputFiles,retryOnly,retryOnly,manifest]);
        NSDictionary*stats=ODLRRecoverDecodedDirectory(input,gJCG5Root,retryOnly?YES:NO,^BOOL{return JCG5ShouldStop();},^(NSDictionary*event){
            NSString*stage=event[@"stage"]?:@"recover",*g=event[@"group"]?:@"";
            unsigned long long n=[event[@"attempted"] unsignedLongLongValue],total=[event[@"groups_total"] unsignedLongLongValue];
            if([stage isEqualToString:@"recover_begin"]){
                JCG5SetEvent([NSString stringWithFormat:@"恢复 %llu/%llu：%@",n,total,g]);
                JCG5Log([NSString stringWithFormat:@"RECOVERY begin group=%@ index=%llu/%llu variants=%@",g,n,total,event[@"variants"]?:@0]);
            }else if([stage isEqualToString:@"recover_end"]){
                NSString*st=event[@"status"]?:@"unknown"; unsigned long long records=[event[@"records"] unsignedLongLongValue];
                pthread_mutex_lock(&gJCG5StateLock); if([st isEqualToString:@"complete"])gJCG5RecoverComplete++;else if([st isEqualToString:@"partial"])gJCG5RecoverPartial++;else gJCG5RecoverFailed++;gJCG5RecoverRecords+=records; pthread_mutex_unlock(&gJCG5StateLock);
                JCG5SetEvent([NSString stringWithFormat:@"恢复 %llu/%llu：%@ → %@（%llu条）",n,total,g,st,records]);
                JCG5Log([NSString stringWithFormat:@"RECOVERY end group=%@ index=%llu/%llu status=%@ records=%llu outputs=%@ written=%@",g,n,total,st,records,event[@"outputs"]?:@0,event[@"written"]?:@0]);
            }else if([stage isEqualToString:@"recover_skip"]){
                unsigned long long skipped=[event[@"skipped_verified"] unsignedLongLongValue];
                JCG5SetEvent([NSString stringWithFormat:@"SHA256 已验证，跳过 %llu｜%@",skipped,g]);
                if(skipped<=5 || skipped%100==0) JCG5Log([NSString stringWithFormat:@"RECOVERY skip verified group=%@ skipped=%llu outputs=%@ status=%@",g,skipped,event[@"outputs"]?:@0,event[@"status"]?:@"unknown"]);
            }
        });
        JCG5Log([NSString stringWithFormat:@"RECOVERY finish stats=%@ manifest=%@",stats?:@{},manifest]);
        NSArray*failedGroups=JCG5FailureGroupsFromReport(); NSMutableArray*failItems=[NSMutableArray array]; for(NSString*g in failedGroups)[failItems addObject:@{ @"group":g }]; JCG5WriteFailureItems(@"Recovery.failures.json",failItems,@"recovery");
        pthread_mutex_lock(&gJCG5StateLock); gJCG5RecoverComplete=[stats[@"tables_complete"] unsignedLongLongValue]; gJCG5RecoverPartial=[stats[@"tables_partial"] unsignedLongLongValue]; gJCG5RecoverFailed=failedGroups.count; gJCG5RecoverRecords=[stats[@"records_recovered"] unsignedLongLongValue]; BOOL stopped=JCG5ShouldStop()||[stats[@"yielded_for_capture"] boolValue]; [gJCG5RecoverState release]; gJCG5RecoverState=[(stopped?(gJCG5PreemptedByCapture?@"被抓取停止":@"已停止"):@"已完成") copy]; pthread_mutex_unlock(&gJCG5StateLock);
        unsigned long long skipped=[stats[@"skipped_verified_this_run"] unsignedLongLongValue],attempted=[stats[@"attempted_this_run"] unsignedLongLongValue];
        JCG5FinishTask(stopped?@"JSON恢复已停止":[NSString stringWithFormat:@"JSON恢复完成｜本次恢复%llu组｜SHA256跳过%llu组",attempted,skipped]);
    }
}
'''
m = m[:start] + new_main + m[end:]

# Runtime binary marker for CI/strings inspection.
needle='MODE2ROUTER=alpha5-metatable-index'
if needle not in m:
    raise SystemExit('alpha5 router marker missing before recovery marker')
m=m.replace(needle,needle+'; RECOVERYSHA=journal-v1-resume',1)
m += '\n// JCG5_V080_ALPHA5_RECOVERY_SHA256_RESUME manifest=Recovery.SHA256.txt force-normal=0 verify-output-sha256=1\n'
recp.write_text(r,encoding='utf-8')
mainp.write_text(m,encoding='utf-8')
print('applied alpha5 recovery SHA256 journal + incremental resume')
