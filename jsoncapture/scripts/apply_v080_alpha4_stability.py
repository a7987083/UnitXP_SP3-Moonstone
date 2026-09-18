#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_V080_ALPHA4_STABILITY"
if MARKER in s:
    print("v0.8.0-alpha4 stability already applied")
    raise SystemExit(0)

for required in (
    "JCG5_PAGE_SNAPSHOT_V070",
    "JCG5_SNAPSHOT_COMPLETENESS_V071",
    "JCG5_V080_ALPHA4_MODE1_MODE2_FIX",
):
    if required not in s:
        raise SystemExit(f"required marker missing: {required}")


def rep(old: str, new: str, label: str, count: int = 1) -> None:
    global s
    if old not in s:
        raise SystemExit(f"alpha4 stability anchor missing: {label}")
    s = s.replace(old, new, count)

# 1) Real game path is Documents/Bundles. Keep singular Bundle only as a
# compatibility fallback for older packages; never prefer it over Bundles.
rep(
    '    gJCG5BundleDir = [[docs stringByAppendingPathComponent:@"Bundle"] retain];',
    '''    NSString *bundles = [docs stringByAppendingPathComponent:@"Bundles"];
    NSString *legacyBundle = [docs stringByAppendingPathComponent:@"Bundle"];
    BOOL bundlesIsDir = NO, legacyIsDir = NO;
    BOOL hasBundles = [[NSFileManager defaultManager] fileExistsAtPath:bundles isDirectory:&bundlesIsDir] && bundlesIsDir;
    BOOL hasLegacy = [[NSFileManager defaultManager] fileExistsAtPath:legacyBundle isDirectory:&legacyIsDir] && legacyIsDir;
    gJCG5BundleDir = [[hasBundles ? bundles : (hasLegacy ? legacyBundle : bundles)] retain];''',
    "Documents/Bundles primary path",
)

# Log the exact path/count before local scanning so a future path issue is
# visible in ManualV05.log without screenshots.
rep(
    '''        if(retryOnly){NSMutableArray*p=[NSMutableArray array];for(id item in JCG5ReadFailureItems(@"LocalScan.failures.json")){if([item isKindOfClass:[NSDictionary class]]&&[item[@"path"] length])[p addObject:item[@"path"]];}paths=p;}else paths=JCG5FilesRecursively(gJCG5BundleDir);
        pthread_mutex_lock(&gJCG5StateLock);''',
    '''        if(retryOnly){NSMutableArray*p=[NSMutableArray array];for(id item in JCG5ReadFailureItems(@"LocalScan.failures.json")){if([item isKindOfClass:[NSDictionary class]]&&[item[@"path"] length])[p addObject:item[@"path"]];}paths=p;}else paths=JCG5FilesRecursively(gJCG5BundleDir);
        JCG5Log([NSString stringWithFormat:@"LOCAL-SCAN source=%@ retry=%d files=%lu", gJCG5BundleDir ?: @"", retryOnly, (unsigned long)paths.count]);
        pthread_mutex_lock(&gJCG5StateLock);''',
    "local scan source logging",
)

# 2) Recovery progress must become observable before an expensive group starts.
# The recovery engine now emits recover_begin/recover_end; update UI counters
# incrementally and write both phases into ManualV05.log.
old_stats = '''        NSDictionary*stats=ODLRRecoverDecodedDirectory(input,gJCG5Root,YES,^BOOL{return JCG5ShouldStop();},^(NSDictionary*event){NSString*g=event[@"group"];if(g.length)JCG5SetEvent([NSString stringWithFormat:@"恢复：%@",g]);});
'''
new_stats = '''        NSUInteger inputFiles=[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:input error:nil] count];
        JCG5Log([NSString stringWithFormat:@"RECOVERY start input=%@ decoded_files=%lu engine=OnDeviceLuaRecovery-0.4.3-g5-memsafe retry=%d", input ?: @"", (unsigned long)inputFiles, retryOnly]);
        NSDictionary*stats=ODLRRecoverDecodedDirectory(input,gJCG5Root,YES,^BOOL{return JCG5ShouldStop();},^(NSDictionary*event){
            NSString*stage=event[@"stage"]?:@"recover";
            NSString*g=event[@"group"]?:@"";
            unsigned long long n=[event[@"attempted"] unsignedLongLongValue], total=[event[@"groups_total"] unsignedLongLongValue];
            if([stage isEqualToString:@"recover_begin"]){
                JCG5SetEvent([NSString stringWithFormat:@"恢复 %llu/%llu：%@",n,total,g]);
                JCG5Log([NSString stringWithFormat:@"RECOVERY begin group=%@ index=%llu/%llu variants=%@",g,n,total,event[@"variants"]?:@0]);
            }else if([stage isEqualToString:@"recover_end"]){
                NSString*status=event[@"status"]?:@"unknown";
                unsigned long long records=[event[@"records"] unsignedLongLongValue];
                pthread_mutex_lock(&gJCG5StateLock);
                if([status isEqualToString:@"complete"])gJCG5RecoverComplete++;
                else if([status isEqualToString:@"partial"])gJCG5RecoverPartial++;
                else gJCG5RecoverFailed++;
                gJCG5RecoverRecords+=records;
                pthread_mutex_unlock(&gJCG5StateLock);
                JCG5SetEvent([NSString stringWithFormat:@"恢复 %llu/%llu：%@ → %@（%llu条）",n,total,g,status,records]);
                JCG5Log([NSString stringWithFormat:@"RECOVERY end group=%@ index=%llu/%llu status=%@ records=%llu written=%@",g,n,total,status,records,event[@"written"]?:@0]);
            }
        });
        JCG5Log([NSString stringWithFormat:@"RECOVERY finish stats=%@",stats?:@{}]);
'''
rep(old_stats, new_stats, "recovery progress/log callback")

# When no scan files are found, expose the exact path in the UI too.
rep(
    'JCG5FinishTask(@"本地扫描：没有可处理文件");return;',
    'JCG5FinishTask([NSString stringWithFormat:@"本地扫描：没有可处理文件｜%@",gJCG5BundleDir?:@""]);return;',
    "scan empty path UI",
)

# Visible binary marker for CI.
rep(
    'MODE1 canonical-directory-follower skip-policy=none; MODE2 active-navigation resourcesui=live-rawgeti router=DlgManager/UIBase snapshot=canonical',
    'MODE1 canonical-directory-follower skip-policy=none; MODE2 active-navigation resourcesui=live-rawgeti router=DlgManager/UIBase snapshot=canonical; LOCALSCAN=Documents/Bundles; RECOVERY=memsafe-g5',
    "stability runtime marker",
)

s += "\n// JCG5_V080_ALPHA4_STABILITY bundles=Documents/Bundles recovery=memsafe-g5-progress\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.0-alpha4 Bundles path + recovery progress/log stability layer")
