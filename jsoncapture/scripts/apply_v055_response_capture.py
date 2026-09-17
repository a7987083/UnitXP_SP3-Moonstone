#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_RESPONSE_CAPTURE_V055"
if MARKER in s:
    print("v0.5.5 response capture patch already applied")
    raise SystemExit(0)

if "JCG5_RESPONSE_OBSERVER_V054" not in s:
    raise SystemExit("v0.5.4 response observer patch must be applied first")
if "JCG5_RUNTIME_CACHE_V052" not in s:
    raise SystemExit("v0.5.2 runtime cache patch must be applied first")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"patch anchor missing: {label}")
    s = s.replace(old, new, 1)

rep(
    "static NSString *gJCG54ObserverLastState;\n",
    "static NSString *gJCG54ObserverLastState;\n"
    "// JCG5_RESPONSE_CAPTURE_V055: validated response JSON persistence.\n"
    "static NSMutableSet *gJCG55ResponseMD5s;\n"
    "static NSMutableSet *gJCG55ResponseSHA256s;\n"
    "static NSString *gJCG55ResponseDir;\n"
    "static NSString *gJCG55ResponseCachePath;\n"
    "static NSString *gJCG55ResponseManifestPath;\n"
    "static BOOL gJCG55ResponseCacheReady = NO;\n"
    "static unsigned long long gJCG55ResponseSaved = 0;\n"
    "static unsigned long long gJCG55ResponseSkipped = 0;\n"
    "static unsigned long long gJCG55ResponseInvalid = 0;\n"
    "static unsigned long long gJCG55ResponseCacheLoaded = 0;\n",
    "response capture globals",
)

helpers = r'''
static void JCG55AppendJSONLine(NSString *path, NSDictionary *obj) {
    if (!path.length || !obj) return;
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!d.length) return;
    NSString *line = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
    if (!line.length) return;
    pthread_mutex_lock(&gJCG5LogLock);
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (f) {
        NSData *ld = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(ld.bytes, 1, ld.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gJCG5LogLock);
}

static void JCG55LoadResponseCacheIfNeeded(void) {
    if (gJCG55ResponseCacheReady) return;
    if (!gJCG55ResponseMD5s) gJCG55ResponseMD5s = [[NSMutableSet alloc] init];
    if (!gJCG55ResponseSHA256s) gJCG55ResponseSHA256s = [[NSMutableSet alloc] init];

    if (!gJCG55ResponseDir) gJCG55ResponseDir = [[gJCG5Root stringByAppendingPathComponent:@"runtime_response_json"] retain];
    if (!gJCG55ResponseCachePath) gJCG55ResponseCachePath = [[gJCG5StateDir stringByAppendingPathComponent:@"ResponseCapture.cache.jsonl"] retain];
    if (!gJCG55ResponseManifestPath) gJCG55ResponseManifestPath = [[gJCG5Root stringByAppendingPathComponent:@"runtime_response_manifest.jsonl"] retain];
    JCG5EnsureDir(gJCG55ResponseDir);

    NSData *raw = [NSData dataWithContentsOfFile:gJCG55ResponseCachePath options:NSDataReadingMappedIfSafe error:nil];
    if (raw.length) {
        NSString *text = [[[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding] autorelease];
        for (NSString *line in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
            @autoreleasepool {
                if (line.length < 2) continue;
                NSData *ld = [line dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *o = [NSJSONSerialization JSONObjectWithData:ld options:0 error:nil];
                if (![o isKindOfClass:[NSDictionary class]]) continue;
                NSString *md5 = [o[@"md5"] lowercaseString];
                NSString *sha = [o[@"sha256"] lowercaseString];
                if (md5.length) [gJCG55ResponseMD5s addObject:md5];
                if (sha.length) [gJCG55ResponseSHA256s addObject:sha];
            }
        }
    }
    gJCG55ResponseCacheReady = YES;
    pthread_mutex_lock(&gJCG5StateLock);
    gJCG55ResponseCacheLoaded = gJCG55ResponseMD5s.count;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG5Log([NSString stringWithFormat:@"RESPONSE-CAPTURE cache ready md5=%lu sha256=%lu path=%@",
             (unsigned long)gJCG55ResponseMD5s.count,
             (unsigned long)gJCG55ResponseSHA256s.count,
             gJCG55ResponseCachePath]);
}

static void JCG55QueueValidatedResponse(NSData *body, unsigned long long hit) {
    if (!body.length || !gJCG5CaptureQueue) return;
    NSData *snapshot = [body retain];
    dispatch_async(gJCG5CaptureQueue, ^{@autoreleasepool {
        JCG55LoadResponseCacheIfNeeded();

        NSError *jsonError = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:snapshot options:0 error:&jsonError];
        BOOL complete = [obj isKindOfClass:[NSDictionary class]] || [obj isKindOfClass:[NSArray class]];
        if (!complete) {
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG55ResponseInvalid++;
            [gJCG54ObserverLastState release];
            gJCG54ObserverLastState = [@"JSON前缀但完整解析失败" copy];
            pthread_mutex_unlock(&gJCG5StateLock);
            JCG5Log([NSString stringWithFormat:@"RESPONSE-CAPTURE invalid hit=%llu bytes=%lu error=%@",
                     hit, (unsigned long)snapshot.length, jsonError.localizedDescription ?: @"unknown"]);
            [snapshot release];
            return;
        }

        NSString *md5 = [JCG5MD5(snapshot).lowercaseString copy];
        NSString *sha = [JCG5SHA256(snapshot).lowercaseString copy];
        if (!md5.length || !sha.length) {
            [md5 release]; [sha release]; [snapshot release];
            return;
        }

        NSString *file = [NSString stringWithFormat:@"%@.json", md5];
        NSString *path = [gJCG55ResponseDir stringByAppendingPathComponent:file];
        BOOL duplicate = [gJCG55ResponseMD5s containsObject:md5] ||
                         [gJCG55ResponseSHA256s containsObject:sha] ||
                         [[NSFileManager defaultManager] fileExistsAtPath:path];
        if (duplicate) {
            if (![gJCG55ResponseMD5s containsObject:md5]) [gJCG55ResponseMD5s addObject:md5];
            if (![gJCG55ResponseSHA256s containsObject:sha]) [gJCG55ResponseSHA256s addObject:sha];
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG55ResponseSkipped++;
            gJCG55ResponseCacheLoaded = gJCG55ResponseMD5s.count;
            [gJCG54ObserverLastState release];
            gJCG54ObserverLastState = [@"完整JSON｜重复跳过" copy];
            pthread_mutex_unlock(&gJCG5StateLock);
            [md5 release]; [sha release]; [snapshot release];
            return;
        }

        BOOL wrote = [snapshot writeToFile:path atomically:YES];
        if (wrote) {
            [gJCG55ResponseMD5s addObject:md5];
            [gJCG55ResponseSHA256s addObject:sha];
            NSDictionary *record = @{
                @"schema": @1,
                @"source": @"UnityWebRequest.DownloadHandlerBuffer.GetData",
                @"rva": @"0x0ECFC0C0",
                @"hit": @(hit),
                @"file": file,
                @"md5": md5,
                @"sha256": sha,
                @"bytes": @(snapshot.length),
                @"time": @([[NSDate date] timeIntervalSince1970])
            };
            JCG55AppendJSONLine(gJCG55ResponseManifestPath, record);
            JCG55AppendJSONLine(gJCG55ResponseCachePath, record);
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG55ResponseSaved++;
            gJCG55ResponseCacheLoaded = gJCG55ResponseMD5s.count;
            [gJCG54ObserverLastState release];
            gJCG54ObserverLastState = [@"完整JSON｜已保存" copy];
            pthread_mutex_unlock(&gJCG5StateLock);
            JCG5Log([NSString stringWithFormat:@"RESPONSE-CAPTURE saved hit=%llu bytes=%lu file=%@ md5=%@ sha256=%@",
                     hit, (unsigned long)snapshot.length, file, md5, sha]);
        } else {
            pthread_mutex_lock(&gJCG5StateLock);
            gJCG55ResponseInvalid++;
            [gJCG54ObserverLastState release];
            gJCG54ObserverLastState = [@"完整JSON｜写入失败" copy];
            pthread_mutex_unlock(&gJCG5StateLock);
            JCG5Log([NSString stringWithFormat:@"RESPONSE-CAPTURE write failed hit=%llu bytes=%lu path=%@",
                     hit, (unsigned long)snapshot.length, path]);
        }

        [md5 release]; [sha release]; [snapshot release];
    }});
}

'''

rep(
    "static void *JCG54HookDownloadHandlerBufferGetData(void *self, const void *method) {\n",
    helpers + "static void *JCG54HookDownloadHandlerBufferGetData(void *self, const void *method) {\n",
    "response capture helpers",
)

old_log_tail = '''    if (hit <= 8 || jsonLike) {
        JCG5Log([NSString stringWithFormat:@"RESPONSE-OBSERVER hit=%llu bytes=%lu json_like=%d rva=0x%llX",
                 hit, (unsigned long)len, jsonLike,
                 (unsigned long long)JCG54_DOWNLOAD_HANDLER_BUFFER_GETDATA_RVA]);
    }
    return ret;
}
'''
new_log_tail = '''    if (hit <= 8 || jsonLike) {
        JCG5Log([NSString stringWithFormat:@"RESPONSE-OBSERVER hit=%llu bytes=%lu json_like=%d rva=0x%llX",
                 hit, (unsigned long)len, jsonLike,
                 (unsigned long long)JCG54_DOWNLOAD_HANDLER_BUFFER_GETDATA_RVA]);
    }
    if (jsonLike) {
        // The Il2Cpp byte[] belongs to the returned managed object. Copy only
        // JSON-looking bodies before leaving this call, then validate and save
        // asynchronously on the existing v0.5.2 serial capture queue.
        NSData *body = [NSData dataWithBytes:a->vector length:len];
        JCG55QueueValidatedResponse(body, hit);
    }
    return ret;
}
'''
rep(old_log_tail, new_log_tail, "queue JSON-looking response")

old_status = '''    unsigned long long hits = gJCG54ObserverHits;
    unsigned long long json = gJCG54ObserverJSONLike;
    unsigned long long bytes = gJCG54ObserverLastBytes;
    NSString *state = [[(gJCG54ObserverLastState ?: @"暂无") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    return [NSString stringWithFormat:@"目标：%@  Hook：%@  命中%llu JSON%llu\\n最新：%lluB｜%@",
            matched ? @"匹配 ✅" : @"未匹配",
            ready ? @"就绪" : @"等待",
            hits, json, bytes, state];
'''
new_status = '''    unsigned long long hits = gJCG54ObserverHits;
    unsigned long long json = gJCG54ObserverJSONLike;
    unsigned long long bytes = gJCG54ObserverLastBytes;
    unsigned long long saved = gJCG55ResponseSaved;
    unsigned long long skipped = gJCG55ResponseSkipped;
    unsigned long long invalid = gJCG55ResponseInvalid;
    unsigned long long cache = gJCG55ResponseCacheLoaded;
    NSString *state = [[(gJCG54ObserverLastState ?: @"暂无") copy] autorelease];
    pthread_mutex_unlock(&gJCG5StateLock);
    return [NSString stringWithFormat:@"目标：%@ Hook：%@ 命中%llu JSON%llu\\n保存%llu 跳过%llu 失败%llu 缓存%llu｜%lluB %@",
            matched ? @"匹配 ✅" : @"未匹配",
            ready ? @"就绪" : @"等待",
            hits, json, saved, skipped, invalid, cache, bytes, state];
'''
rep(old_status, new_status, "response capture status")

rep(
    '@[@"capture2",@"响应观察"]',
    '@[@"capture2",@"响应抓取"]',
    "response capture UI title",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.5 validated response JSON capture")
