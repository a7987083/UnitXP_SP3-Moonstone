#import "MobileRecoveryInputBridge.h"
#import <CommonCrypto/CommonDigest.h>
#include <limits.h>

#define JCG4_BRIDGE_SCHEMA 3

static NSString *gJCG4BridgeLastManifestSHA256;
static dispatch_queue_t gJCG4BridgeQueue;

static NSString *JCG4BridgeSafe(NSString *text) {
    if (!text.length) return @"unnamed";
    NSMutableString *out=[NSMutableString stringWithCapacity:MIN(text.length,140)];
    NSCharacterSet *ok=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@+"];
    for(NSUInteger i=0;i<text.length&&out.length<140;i++){
        unichar c=[text characterAtIndex:i];
        if([ok characterIsMember:c])[out appendFormat:@"%C",c]; else [out appendString:@"_"];
    }
    return out.length?out:@"unnamed";
}

static NSString *JCG4BridgeSHA256(NSData *data) {
    if(!data.length)return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *s=[NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for(NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[s appendFormat:@"%02x",digest[i]];
    return s;
}

static BOOL JCG4BridgeIsHexHash(NSString *s) {
    if(!(s.length==12||s.length==64))return NO;
    NSCharacterSet *hex=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    return [[s stringByTrimmingCharactersInSet:hex] length]==0;
}

static NSString *JCG4BridgeHashFromFileName(NSString *name) {
    if(!name.length)return nil;
    NSString *base=[name stringByDeletingPathExtension];
    NSRange r=[base rangeOfString:@"_" options:NSBackwardsSearch];
    if(r.location==NSNotFound||r.location+1>=base.length)return nil;
    NSString *tail=[base substringFromIndex:r.location+1];
    return JCG4BridgeIsHexHash(tail)?[tail lowercaseString]:nil;
}

static NSString *JCG4BridgeResolveFullHash(NSDictionary *filesByHash, NSString *hint) {
    if(!hint.length)return nil;
    NSString *lower=hint.lowercaseString;
    if(lower.length==64 && filesByHash[lower])return lower;
    if(lower.length==12){
        NSString *match=nil;
        for(NSString *full in filesByHash){
            if([full hasPrefix:lower]){
                if(match)return nil;
                match=full;
            }
        }
        return match;
    }
    return nil;
}

static NSString *JCG4BridgeLeaf(NSString *asset) {
    if(!asset.length)return @"unnamed";
    NSString *norm=[asset stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSString *leaf=norm.lastPathComponent;
    return leaf.length?leaf:asset;
}

/*
 * Unity TextAsset names in this title commonly end in ".lua.bytes".
 * The old bridge removed only the outer generated .luac suffix later in the
 * recovery parser, leaving names such as TAB_Drop_5.lua.bytes.  That prevents
 * TAB_xxx_N fragments from grouping and makes fragment 2+ look dynamic because
 * their shared table is missing.  Strip all known transport/source suffixes
 * here so recovery sees canonical names such as TAB_Drop_5.
 */
static NSString *JCG4BridgeCanonicalStem(NSString *asset) {
    NSString *stem=JCG4BridgeLeaf(asset);
    NSArray *exts=@[@".luac",@".lua",@".bytes",@".txt",@".bin"];
    for(NSUInteger guard=0;guard<8&&stem.length;guard++){
        NSString *lower=stem.lowercaseString;
        BOOL changed=NO;
        for(NSString *ext in exts){
            if([lower hasSuffix:ext]&&stem.length>ext.length){
                stem=[stem substringToIndex:stem.length-ext.length];
                changed=YES;
                break;
            }
        }
        if(!changed)break;
    }
    return JCG4BridgeSafe(stem.length?stem:@"unnamed");
}

static NSDictionary *JCG4BridgeReadDictionary(NSString *path) {
    NSData *d=[NSData dataWithContentsOfFile:path];
    if(!d.length)return nil;
    id obj=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]]?obj:nil;
}

static void JCG4BridgeWriteDictionary(NSDictionary *obj, NSString *path) {
    if(!obj||!path.length)return;
    NSData *d=[NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil];
    if(d.length)[d writeToFile:path atomically:YES];
}

static void JCG4BridgeResetStaleRecoveryIfNeeded(NSString *rootPath, BOOL *didReset) {
    if(didReset)*didReset=NO;
    NSString *schemaPath=[rootPath stringByAppendingPathComponent:@"MobileRecoveryInput.schema.json"];
    NSDictionary *old=JCG4BridgeReadDictionary(schemaPath);
    NSInteger oldVersion=[old[@"schema_version"] integerValue];
    if(oldVersion>=JCG4_BRIDGE_SCHEMA)return;

    NSFileManager *fm=[NSFileManager defaultManager];
    for(NSString *name in @[@"MobileRecovery.index.json",@"MobileRecovery.report.json",@"MobileRecovery.status.json"])
        [fm removeItemAtPath:[rootPath stringByAppendingPathComponent:name] error:nil];
    for(NSString *name in @[@"recovered_json",@"recovered_partial"]){
        NSString *dir=[rootPath stringByAppendingPathComponent:name];
        [fm removeItemAtPath:dir error:nil];
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    JCG4BridgeWriteDictionary(@{ @"schema_version":@(JCG4_BRIDGE_SCHEMA),@"updated_at":@([[NSDate date] timeIntervalSince1970]) },schemaPath);
    if(didReset)*didReset=YES;
}

NSDictionary *JCG4SyncRecoveryInput(NSString *rootPath) {
    if(!rootPath.length)return @{ @"mapped":@0,@"missing":@0,@"invalid":@0,@"total":@0 };
    NSFileManager *fm=[NSFileManager defaultManager];
    NSString *decoded=[rootPath stringByAppendingPathComponent:@"decoded_lua"];
    NSString *manifest=[rootPath stringByAppendingPathComponent:@"manifest.jsonl"];
    [fm createDirectoryAtPath:decoded withIntermediateDirectories:YES attributes:nil error:nil];

    NSData *md=[NSData dataWithContentsOfFile:manifest options:NSDataReadingMappedIfSafe error:nil];
    if(!md.length)return @{ @"mapped":@0,@"missing":@0,@"invalid":@0,@"total":@0,@"schema_version":@(JCG4_BRIDGE_SCHEMA) };
    NSString *manifestSHA256=JCG4BridgeSHA256(md);
    if(manifestSHA256.length && [manifestSHA256 isEqualToString:gJCG4BridgeLastManifestSHA256]){
        return @{ @"mapped":@0,@"missing":@0,@"invalid":@0,@"total":@0,@"unchanged":@YES,@"manifest_sha256":manifestSHA256,@"schema_version":@(JCG4_BRIDGE_SCHEMA) };
    }
    NSString *text=[[[NSString alloc]initWithData:md encoding:NSUTF8StringEncoding]autorelease];
    if(!text.length)return @{ @"mapped":@0,@"missing":@0,@"invalid":@0,@"total":@0,@"schema_version":@(JCG4_BRIDGE_SCHEMA) };

    /* Build a FULL SHA-256 -> existing files map. Filename suffixes are not
       trusted as identity; legacy 12-hex names are migrated by their bytes. */
    NSMutableDictionary *filesByHash=[NSMutableDictionary dictionary];
    for(NSString *name in [fm contentsOfDirectoryAtPath:decoded error:nil]){
        NSString *path=[decoded stringByAppendingPathComponent:name];
        NSData *bytes=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
        NSString *h=JCG4BridgeSHA256(bytes);
        if(h.length!=64)continue;
        NSMutableArray *a=filesByHash[h];
        if(!a){a=[NSMutableArray array];filesByHash[h]=a;}
        [a addObject:name];
    }

    unsigned long long mapped=0,missing=0,invalid=0,total=0,normalized=0,dedupRemoved=0;
    NSMutableSet *seenDest=[NSMutableSet set];
    for(NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){@autoreleasepool{
        if(line.length<2)continue;
        total++;
        NSData *ld=[line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *obj=[NSJSONSerialization JSONObjectWithData:ld options:0 error:nil];
        if(![obj isKindOfClass:[NSDictionary class]]){invalid++;continue;}
        NSString *decodedFile=obj[@"decoded_file"];
        NSString *asset=obj[@"asset"];
        if(!decodedFile.length||!asset.length)continue;

        NSString *hash=JCG4BridgeHashFromFileName(decodedFile);
        NSString *src=[decoded stringByAppendingPathComponent:decodedFile];
        BOOL isDir=NO;
        BOOL srcExists=[fm fileExistsAtPath:src isDirectory:&isDir]&&!isDir;
        NSData *bytes=srcExists?[NSData dataWithContentsOfFile:src options:NSDataReadingMappedIfSafe error:nil]:nil;
        if(bytes.length>=5){
            const uint8_t *p=bytes.bytes;
            if(!(p[0]==0x1B&&p[1]=='L'&&p[2]=='u'&&p[3]=='a'&&p[4]==0x53)){invalid++;continue;}
            hash=JCG4BridgeSHA256(bytes);
        }
        if(hash.length!=64) hash=JCG4BridgeResolveFullHash(filesByHash,hash);
        if(hash.length!=64){missing++;continue;}

        NSString *stem=JCG4BridgeCanonicalStem(asset);
        NSString *dstName=[NSString stringWithFormat:@"%@_%@.luac",stem,hash];
        if([seenDest containsObject:dstName])continue;
        [seenDest addObject:dstName];
        NSString *dst=[decoded stringByAppendingPathComponent:dstName];
        mapped++;

        if([fm fileExistsAtPath:dst]){
            for(NSString *other in [NSArray arrayWithArray:(filesByHash[hash]?:@[])]){
                if([other isEqualToString:dstName])continue;
                if([fm removeItemAtPath:[decoded stringByAppendingPathComponent:other] error:nil])dedupRemoved++;
            }
            continue;
        }

        NSString *candidate=nil;
        if(srcExists)candidate=decodedFile;
        if(!candidate){
            for(NSString *other in filesByHash[hash]){
                NSString *p=[decoded stringByAppendingPathComponent:other];
                BOOL d=NO;if([fm fileExistsAtPath:p isDirectory:&d]&&!d){candidate=other;break;}
            }
        }
        if(!candidate){missing++;continue;}

        NSString *candidatePath=[decoded stringByAppendingPathComponent:candidate];
        NSError *err=nil;
        if([fm moveItemAtPath:candidatePath toPath:dst error:&err]){
            normalized++;
        }else{
            err=nil;
            if([fm copyItemAtPath:candidatePath toPath:dst error:&err]){
                [fm removeItemAtPath:candidatePath error:nil];
                normalized++;
            }else{invalid++;continue;}
        }

        /* Remove stale r2 aliases/original flattened names with identical hash. */
        for(NSString *other in [NSArray arrayWithArray:(filesByHash[hash]?:@[])]){
            if([other isEqualToString:dstName]||[other isEqualToString:candidate])continue;
            if([fm removeItemAtPath:[decoded stringByAppendingPathComponent:other] error:nil])dedupRemoved++;
        }
        filesByHash[hash]=[NSMutableArray arrayWithObject:dstName];
    }}

    BOOL resetRecovery=NO;
    JCG4BridgeResetStaleRecoveryIfNeeded(rootPath,&resetRecovery);
    [gJCG4BridgeLastManifestSHA256 release];\n    gJCG4BridgeLastManifestSHA256=[manifestSHA256 copy];
    NSDictionary *status=@{
        @"schema_version":@(JCG4_BRIDGE_SCHEMA),
        @"mapped":@(mapped),@"normalized_files":@(normalized),@"dedup_removed":@(dedupRemoved),@"missing":@(missing),@"invalid":@(invalid),@"total":@(total),
        @"canonical_groups_expected":@"TAB_xxx_N fragments now strip compound .lua.bytes suffixes before grouping",
        @"recovery_state_reset":@(resetRecovery),
        @"input_dir":decoded,@"strategy":@"manifest SHA-256 change detection; canonical decoded_lua filename; dedup by full decoded SHA-256",\n        @"manifest_sha256":manifestSHA256?:@"",
        @"updated_at":@([[NSDate date] timeIntervalSince1970])
    };
    JCG4BridgeWriteDictionary(status,[rootPath stringByAppendingPathComponent:@"MobileRecoveryInput.status.json"]);
    return status;
}

static NSString *JCG4BridgeRoot(void){
    NSArray *docs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);
    NSString *d=docs.count?docs[0]:NSTemporaryDirectory();
    return [[d stringByAppendingPathComponent:@"JSONCapture"] stringByAppendingPathComponent:@"FullSweep"];
}

static void JCG4BridgeSchedule(void);
static void JCG4BridgeTick(void){
    dispatch_async(gJCG4BridgeQueue, ^{@autoreleasepool{JCG4SyncRecoveryInput(JCG4BridgeRoot());}});
    JCG4BridgeSchedule();
}
static void JCG4BridgeSchedule(void){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(3.0*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{JCG4BridgeTick();});
}

__attribute__((constructor)) static void JCG4BridgeEntry(void){
    gJCG4BridgeQueue=dispatch_queue_create("com.openai.jsoncapture.g4r2.recoveryinput",DISPATCH_QUEUE_SERIAL);
    /* Start earlier than the UI worker's first recovery tick so one-time name
       migration normally completes before static recovery begins. */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.20*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{JCG4BridgeTick();});
}
