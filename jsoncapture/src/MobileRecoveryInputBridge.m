#import "MobileRecoveryInputBridge.h"
#import <CommonCrypto/CommonDigest.h>
#include <limits.h>

static unsigned long long gJCG4BridgeLastManifestSize = ULLONG_MAX;
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

static NSString *JCG4BridgeSHA12(NSData *data) {
    if(!data.length)return @"000000000000";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *s=[NSMutableString stringWithCapacity:24];
    for(NSUInteger i=0;i<6;i++)[s appendFormat:@"%02x",digest[i]];
    return s;
}

static NSString *JCG4BridgeLeaf(NSString *asset) {
    if(!asset.length)return @"unnamed";
    NSString *norm=[asset stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSString *leaf=norm.lastPathComponent;
    return leaf.length?leaf:asset;
}

NSDictionary *JCG4SyncRecoveryInput(NSString *rootPath) {
    if(!rootPath.length)return @{ @"mapped":@0,@"missing":@0,@"invalid":@0,@"total":@0 };
    NSFileManager *fm=[NSFileManager defaultManager];
    NSString *decoded=[rootPath stringByAppendingPathComponent:@"decoded_lua"];
    NSString *manifest=[rootPath stringByAppendingPathComponent:@"manifest.jsonl"];
    [fm createDirectoryAtPath:decoded withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *attrs=[fm attributesOfItemAtPath:manifest error:nil];
    unsigned long long manifestSize=[attrs[NSFileSize] unsignedLongLongValue];
    if(manifestSize==gJCG4BridgeLastManifestSize){
        return @{ @"mapped":@0,@"missing":@0,@"invalid":@0,@"total":@0,@"unchanged":@YES };
    }

    NSData *md=[NSData dataWithContentsOfFile:manifest options:NSDataReadingMappedIfSafe error:nil];
    if(!md.length)return @{ @"mapped":@0,@"missing":@0,@"invalid":@0,@"total":@0 };
    NSString *text=[[[NSString alloc]initWithData:md encoding:NSUTF8StringEncoding]autorelease];
    if(!text.length)return @{ @"mapped":@0,@"missing":@0,@"invalid":@0,@"total":@0 };

    unsigned long long mapped=0,missing=0,invalid=0,total=0,normalized=0,dedupRemoved=0;
    for(NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){@autoreleasepool{
        if(line.length<2)continue;
        total++;
        NSData *ld=[line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *obj=[NSJSONSerialization JSONObjectWithData:ld options:0 error:nil];
        if(![obj isKindOfClass:[NSDictionary class]]){invalid++;continue;}
        NSString *decodedFile=obj[@"decoded_file"];
        NSString *asset=obj[@"asset"];
        if(!decodedFile.length||!asset.length)continue;
        NSString *src=[decoded stringByAppendingPathComponent:decodedFile];
        BOOL isDir=NO;
        if(![fm fileExistsAtPath:src isDirectory:&isDir]||isDir){continue;}
        NSData *bytes=[NSData dataWithContentsOfFile:src options:NSDataReadingMappedIfSafe error:nil];
        if(bytes.length<5){invalid++;continue;}
        const uint8_t *p=bytes.bytes;
        if(!(p[0]==0x1B&&p[1]=='L'&&p[2]=='u'&&p[3]=='a'&&p[4]==0x53))continue;
        NSString *leaf=JCG4BridgeLeaf(asset);
        NSString *safe=JCG4BridgeSafe(leaf);
        NSString *hash=JCG4BridgeSHA12(bytes);
        NSString *dstName=[NSString stringWithFormat:@"%@_%@.luac",safe,hash];
        NSString *dst=[decoded stringByAppendingPathComponent:dstName];
        mapped++;
        if([dst isEqualToString:src])continue;
        if([fm fileExistsAtPath:dst]){
            if([fm removeItemAtPath:src error:nil])dedupRemoved++;
            continue;
        }
        NSError *err=nil;
        if([fm moveItemAtPath:src toPath:dst error:&err]){normalized++;continue;}
        err=nil;
        if([fm copyItemAtPath:src toPath:dst error:&err]){
            [fm removeItemAtPath:src error:nil];
            normalized++;
        }else{
            invalid++;
        }
    }}

    gJCG4BridgeLastManifestSize=manifestSize;
    NSDictionary *status=@{
        @"mapped":@(mapped),@"normalized_files":@(normalized),@"dedup_removed":@(dedupRemoved),@"missing":@(missing),@"invalid":@(invalid),@"total":@(total),
        @"input_dir":decoded,@"strategy":@"manifest asset leaf -> canonical decoded_lua filename; no duplicate recovery groups",
        @"updated_at":@([[NSDate date] timeIntervalSince1970])
    };
    NSData *sd=[NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:nil];
    [sd writeToFile:[rootPath stringByAppendingPathComponent:@"MobileRecoveryInput.status.json"] atomically:YES];
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{JCG4BridgeTick();});
}
