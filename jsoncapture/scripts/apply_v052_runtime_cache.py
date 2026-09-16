#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_RUNTIME_CACHE_V052"
if MARKER in s:
    print("v0.5.2 runtime cache patch already applied")
    raise SystemExit(0)


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"patch anchor missing: {label}")
    s = s.replace(old, new, 1)

rep(
    "static NSMutableSet *gJCG5CaptureHashes;\nstatic pthread_mutex_t gJCG5StateLock = PTHREAD_MUTEX_INITIALIZER;",
    "static NSMutableSet *gJCG5CaptureHashes;\n"
    "static NSMutableSet *gJCG5CaptureMD5s;\n"
    "static NSString *gJCG5CaptureCachePath;\n"
    "static NSString *gJCG5LastCaptureStatus;\n"
    "static unsigned long long gJCG5CaptureSkipped = 0;\n"
    "static unsigned long long gJCG5CaptureCacheLoaded = 0;\n"
    "static pthread_mutex_t gJCG5StateLock = PTHREAD_MUTEX_INITIALIZER;",
    "capture cache globals",
)

rep(
    "static NSString *JCG5SHA256(NSData *data) {\n"
    "    if (!data.length) return @\"\";\n"
    "    unsigned char digest[CC_SHA256_DIGEST_LENGTH];\n"
    "    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);\n"
    "    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];\n"
    "    for (NSUInteger i=0; i<CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@\"%02x\", digest[i]];\n"
    "    return s;\n"
    "}\n",
    "static NSString *JCG5SHA256(NSData *data) {\n"
    "    if (!data.length) return @\"\";\n"
    "    unsigned char digest[CC_SHA256_DIGEST_LENGTH];\n"
    "    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);\n"
    "    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];\n"
    "    for (NSUInteger i=0; i<CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@\"%02x\", digest[i]];\n"
    "    return s;\n"
    "}\n\n"
    "// JCG5_RUNTIME_CACHE_V052: persistent cross-launch runtime Lua dedupe.\n"
    "static NSString *JCG5MD5(NSData *data) {\n"
    "    if (!data.length) return @\"\";\n"
    "    unsigned char digest[CC_MD5_DIGEST_LENGTH];\n"
    "    CC_MD5(data.bytes, (CC_LONG)data.length, digest);\n"
    "    NSMutableString *s = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];\n"
    "    for (NSUInteger i=0; i<CC_MD5_DIGEST_LENGTH; i++) [s appendFormat:@\"%02x\", digest[i]];\n"
    "    return s;\n"
    "}\n",
    "MD5 helper",
)

cache_helpers = r'''
static void JCG5AppendRuntimeCaptureCache(NSString *md5, NSString *sha, NSString *source, NSString *chunk, NSUInteger bytes, NSString *status) {
    if (!gJCG5CaptureCachePath.length || !md5.length) return;
    NSDictionary *obj = @{
        @"schema": @1,
        @"algorithm": @"md5",
        @"md5": md5,
        @"sha256": sha ?: @"",
        @"source": source ?: @"",
        @"chunk": chunk ?: @"",
        @"bytes": @(bytes),
        @"status": status ?: @"captured",
        @"time": @([[NSDate date] timeIntervalSince1970])
    };
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d.length) return;
    NSString *line = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
    pthread_mutex_lock(&gJCG5LogLock);
    FILE *f = fopen(gJCG5CaptureCachePath.fileSystemRepresentation, "a");
    if (f) {
        NSData *ld = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(ld.bytes, 1, ld.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJCG5LogLock);
}

static void JCG5LoadHashManifestIntoSets(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data.length) return;
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!text.length) return;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        @autoreleasepool {
            if (line.length < 2) continue;
            NSData *ld = [line dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *o = [NSJSONSerialization JSONObjectWithData:ld options:0 error:nil];
            if (![o isKindOfClass:[NSDictionary class]]) continue;
            NSString *md5 = o[@"md5"];
            NSString *sha = o[@"sha256"];
            if (md5.length) [gJCG5CaptureMD5s addObject:md5.lowercaseString];
            if (sha.length) [gJCG5CaptureHashes addObject:sha.lowercaseString];
        }
    }
}

static void JCG5LoadRuntimeCaptureCache(void) {
    if (!gJCG5CaptureMD5s) gJCG5CaptureMD5s = [[NSMutableSet alloc] init];
    if (!gJCG5CaptureHashes) gJCG5CaptureHashes = [[NSMutableSet alloc] init];
    [gJCG5CaptureCachePath release];
    gJCG5CaptureCachePath = [[gJCG5StateDir stringByAppendingPathComponent:@"RuntimeCapture.cache.jsonl"] retain];

    // Load the new MD5 cache first, then import SHA256 values from the old
    // loader manifest so files captured by v0.5/v0.5.1 are skipped immediately.
    JCG5LoadHashManifestIntoSets(gJCG5CaptureCachePath);
    JCG5LoadHashManifestIntoSets([gJCG5Root stringByAppendingPathComponent:@"loader_manifest.jsonl"]);

    pthread_mutex_lock(&gJCG5StateLock);
    gJCG5CaptureCacheLoaded = gJCG5CaptureMD5s.count;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG5Log([NSString stringWithFormat:@"RUNTIME-CACHE ready md5=%lu sha256_legacy=%lu path=%@",
             (unsigned long)gJCG5CaptureMD5s.count,
             (unsigned long)gJCG5CaptureHashes.count,
             gJCG5CaptureCachePath]);
}

'''
rep("#pragma mark - Dynamic symbols / loader hooks\n", cache_helpers + "#pragma mark - Dynamic symbols / loader hooks\n", "cache helpers")

old_manifest = '''static void JCG5AppendLoaderManifest(NSString *file, NSString *source, NSString *chunk, NSString *sha, NSUInteger bytes) {
    NSDictionary *obj=@{ @"file":file?:@"",@"source":source?:@"",@"chunk":chunk?:@"",@"sha256":sha?:@"",@"bytes":@(bytes),@"time":@([[NSDate date] timeIntervalSince1970]) };
'''
new_manifest = '''static void JCG5AppendLoaderManifest(NSString *file, NSString *source, NSString *chunk, NSString *md5, NSString *sha, NSUInteger bytes) {
    NSDictionary *obj=@{ @"file":file?:@"",@"source":source?:@"",@"chunk":chunk?:@"",@"md5":md5?:@"",@"sha256":sha?:@"",@"bytes":@(bytes),@"time":@([[NSDate date] timeIntervalSince1970]) };
'''
rep(old_manifest, new_manifest, "loader manifest md5")

old_queue = '''static void JCG5QueueLoaderCapture(NSData *data, NSString *source, NSString *chunkName) {
    if(!data.length||data.length>JCG5_MAX_BUFFER||!gJCG5CaptureQueue)return;
    NSData *snapshot=[NSData dataWithData:data]; NSString *src=[(source?:@"loader") copy]; NSString *chunk=[(chunkName?:@"unnamed") copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool{
        NSString *hash=JCG5SHA256(snapshot);
        if(!hash.length||[gJCG5CaptureHashes containsObject:hash]){[src release];[chunk release];return;}
        [gJCG5CaptureHashes addObject:hash];
        pthread_mutex_lock(&gJCG5StateLock);gJCG5CaptureCount++;unsigned long long seq=gJCG5CaptureCount;[gJCG5LastCaptureChunk release];gJCG5LastCaptureChunk=[chunk copy];pthread_mutex_unlock(&gJCG5StateLock);
        NSString *shortHash=hash.length>12?[hash substringToIndex:12]:hash;
        NSString *ext=JCG5HasLua53(snapshot)?@"luac":@"bin";
        NSString *file=[NSString stringWithFormat:@"%06llu_%@_%@_%@.%@",seq,JCG5Safe(src,24),JCG5Safe(chunk,96),shortHash,ext];
        NSString *path=[gJCG5LoaderDir stringByAppendingPathComponent:file];
        [snapshot writeToFile:path atomically:YES];
        JCG5AppendLoaderManifest(file,src,chunk,hash,snapshot.length);
        [src release];[chunk release];
    }});
}
'''
new_queue = '''static void JCG5QueueLoaderCapture(NSData *data, NSString *source, NSString *chunkName) {
    if(!data.length||data.length>JCG5_MAX_BUFFER||!gJCG5CaptureQueue)return;
    NSData *snapshot=[NSData dataWithData:data]; NSString *src=[(source?:@"loader") copy]; NSString *chunk=[(chunkName?:@"unnamed") copy];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool{
        NSString *md5=JCG5MD5(snapshot).lowercaseString;
        NSString *hash=JCG5SHA256(snapshot).lowercaseString;
        BOOL duplicate=(md5.length&&[gJCG5CaptureMD5s containsObject:md5])||(hash.length&&[gJCG5CaptureHashes containsObject:hash]);
        if(duplicate){
            BOOL migrated=md5.length&&![gJCG5CaptureMD5s containsObject:md5];
            if(migrated){[gJCG5CaptureMD5s addObject:md5];JCG5AppendRuntimeCaptureCache(md5,hash,src,chunk,snapshot.length,@"migrated-duplicate");}
            pthread_mutex_lock(&gJCG5StateLock);gJCG5CaptureSkipped++;gJCG5CaptureCacheLoaded=gJCG5CaptureMD5s.count;[gJCG5LastCaptureChunk release];gJCG5LastCaptureChunk=[chunk copy];[gJCG5LastCaptureStatus release];gJCG5LastCaptureStatus=[@"已抓过" copy];pthread_mutex_unlock(&gJCG5StateLock);
            dispatch_async(dispatch_get_main_queue(), ^{JCG5SetEvent([NSString stringWithFormat:@"最新 %@ 已抓过，已跳过",chunk.lastPathComponent?:chunk]);});
            [src release];[chunk release];return;
        }
        if(!md5.length||!hash.length){[src release];[chunk release];return;}

        // Only a genuinely new runtime Lua capture may preempt manual work.
        JCG5NotifyRuntimeCapture();
        pthread_mutex_lock(&gJCG5StateLock);gJCG5CaptureCount++;unsigned long long seq=gJCG5CaptureCount;[gJCG5LastCaptureChunk release];gJCG5LastCaptureChunk=[chunk copy];[gJCG5LastCaptureStatus release];gJCG5LastCaptureStatus=[@"新抓取" copy];pthread_mutex_unlock(&gJCG5StateLock);
        NSString *shortHash=hash.length>12?[hash substringToIndex:12]:hash;
        NSString *ext=JCG5HasLua53(snapshot)?@"luac":@"bin";
        NSString *file=[NSString stringWithFormat:@"%06llu_%@_%@_%@.%@",seq,JCG5Safe(src,24),JCG5Safe(chunk,96),shortHash,ext];
        NSString *path=[gJCG5LoaderDir stringByAppendingPathComponent:file];
        BOOL wrote=[snapshot writeToFile:path atomically:YES];
        if(wrote){
            [gJCG5CaptureMD5s addObject:md5];[gJCG5CaptureHashes addObject:hash];
            pthread_mutex_lock(&gJCG5StateLock);gJCG5CaptureCacheLoaded=gJCG5CaptureMD5s.count;pthread_mutex_unlock(&gJCG5StateLock);
            JCG5AppendLoaderManifest(file,src,chunk,md5,hash,snapshot.length);
            JCG5AppendRuntimeCaptureCache(md5,hash,src,chunk,snapshot.length,@"captured");
            dispatch_async(dispatch_get_main_queue(), ^{JCG5SetEvent([NSString stringWithFormat:@"新抓取：%@",chunk.lastPathComponent?:chunk]);});
        } else {
            pthread_mutex_lock(&gJCG5StateLock);[gJCG5LastCaptureStatus release];gJCG5LastCaptureStatus=[@"写入失败" copy];pthread_mutex_unlock(&gJCG5StateLock);
            dispatch_async(dispatch_get_main_queue(), ^{JCG5SetEvent([NSString stringWithFormat:@"抓取写入失败：%@",chunk.lastPathComponent?:chunk]);});
        }
        [src release];[chunk release];
    }});
}
'''
rep(old_queue, new_queue, "runtime capture queue")

rep(
    'if(enabled&&buffer&&size>0&&(uint64_t)size<=JCG5_MAX_BUFFER){JCG5NotifyRuntimeCapture();NSData*d=[NSData dataWithBytes:buffer length:(NSUInteger)size];NSString*chunk=name?[NSString stringWithUTF8String:name]:@"unnamed";JCG5QueueLoaderCapture(d,@"tolua_loadbuffer",chunk);}',
    'if(enabled&&buffer&&size>0&&(uint64_t)size<=JCG5_MAX_BUFFER){NSData*d=[NSData dataWithBytes:buffer length:(NSUInteger)size];NSString*chunk=name?[NSString stringWithUTF8String:name]:@"unnamed";JCG5QueueLoaderCapture(d,@"tolua_loadbuffer",chunk);}',
    "tolua notify order",
)
rep(
    'if(enabled&&buffer&&size>0&&size<=JCG5_MAX_BUFFER){JCG5NotifyRuntimeCapture();NSData*d=[NSData dataWithBytes:buffer length:size];NSString*chunk=name?[NSString stringWithUTF8String:name]:@"unnamed";JCG5QueueLoaderCapture(d,@"luaL_loadbufferx",chunk);}',
    'if(enabled&&buffer&&size>0&&size<=JCG5_MAX_BUFFER){NSData*d=[NSData dataWithBytes:buffer length:size];NSString*chunk=name?[NSString stringWithUTF8String:name]:@"unnamed";JCG5QueueLoaderCapture(d,@"luaL_loadbufferx",chunk);}',
    "luaL notify order",
)

rep(
    'unsigned long long cc=gJCG5CaptureCount,st=gJCG5ScanTotal,',
    'unsigned long long cc=gJCG5CaptureCount,cs=gJCG5CaptureSkipped,cache=gJCG5CaptureCacheLoaded,st=gJCG5ScanTotal,',
    "UI capture counters",
)
rep(
    'NSString*chunk=[[(gJCG5LastCaptureChunk?:@"暂无") copy] autorelease],*scan=',
    'NSString*chunk=[[(gJCG5LastCaptureChunk?:@"暂无") copy] autorelease],*capStatus=[[(gJCG5LastCaptureStatus?:@"暂无") copy] autorelease],*scan=',
    "UI capture status",
)
rep(
    'self.labels[@"capture"].text=[NSString stringWithFormat:@"状态：%@  Hook：%@  捕获：%llu\\n最新：%@",cap?@"开启 ✅":@"关闭",hooks?@"就绪":@"等待",cc,chunk.lastPathComponent?:chunk];',
    'self.labels[@"capture"].text=[NSString stringWithFormat:@"状态：%@  Hook：%@  新抓%llu 跳过%llu\\n缓存MD5：%llu  最新：%@｜%@",cap?@"开启 ✅":@"关闭",hooks?@"就绪":@"等待",cc,cs,cache,chunk.lastPathComponent?:chunk,capStatus];',
    "UI capture label",
)

rep(
    'gJCG5CaptureHashes=[[NSMutableSet alloc]init];gJCG5ScanState=',
    'gJCG5CaptureHashes=[[NSMutableSet alloc]init];gJCG5CaptureMD5s=[[NSMutableSet alloc]init];gJCG5LastCaptureStatus=[@"暂无" copy];JCG5LoadRuntimeCaptureCache();gJCG5ScanState=',
    "constructor cache load",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.2 persistent runtime cache patch")
