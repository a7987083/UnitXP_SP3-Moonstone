#import <Foundation/Foundation.h>

// Reuse the device-validated g2 Full Sweep core in the same translation unit.
// The g3 layer below persists only disk Bundle versions that reached a terminal
// processing event. This keeps runtime-only discovery intact while preventing
// unchanged on-disk Bundles from being LoadFromFile-scanned again after relaunch.
#include "GenericFullSweep.m"

#define JCG3_VERSION @"JSONCapture Persistent Incremental v0.4.2-g3"
#define JCG3_SCHEMA_VERSION 1
#define JCG3_LOG_POLL_SECONDS 0.50

static dispatch_queue_t gJCG3PersistQueue;
static NSString *gJCG3IndexPath;
static NSString *gJCG3StatusPath;
static NSMutableDictionary *gJCG3Bundles;
static NSMutableString *gJCG3LogCarry;
static unsigned long long gJCG3LogOffset = 0;
static unsigned long long gJCG3IndexLoadedEntries = 0;
static unsigned long long gJCG3UnchangedSeeded = 0;
static unsigned long long gJCG3PersistedOK = 0;
static unsigned long long gJCG3PersistedFailed = 0;
static unsigned long long gJCG3IndexWrites = 0;
static NSString *gJCG3LastEvent;
static BOOL gJCG3Initialized = NO;

static NSString *JCG3StringBetween(NSString *line, NSString *startToken, NSString *endToken) {
    if (!line.length || !startToken.length) return nil;
    NSRange start = [line rangeOfString:startToken];
    if (start.location == NSNotFound) return nil;
    NSUInteger pos = NSMaxRange(start);
    if (pos >= line.length) return @"";
    NSRange search = NSMakeRange(pos, line.length - pos);
    NSRange end = endToken.length ? [line rangeOfString:endToken options:0 range:search] : NSMakeRange(NSNotFound, 0);
    NSUInteger len = (end.location == NSNotFound ? line.length : end.location) - pos;
    return [line substringWithRange:NSMakeRange(pos, len)];
}

static NSString *JCG3CurrentDiskVersion(NSString *path) {
    if (!path.length) return nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attrs) return nil;
    return JCG2FileVersion(path, attrs);
}

static void JCG3WriteStatus(void) {
    if (!gJCG3StatusPath.length) return;
    NSDictionary *status = @{
        @"version": JCG3_VERSION,
        @"schema_version": @(JCG3_SCHEMA_VERSION),
        @"persistent_incremental": @YES,
        @"disk_policy": @"same path+size+mtime version => skip across launches; new/changed => process",
        @"runtime_loaded_policy": @"still observed every process to catch memory-only/newly loaded bundles",
        @"bundle_index": gJCG3IndexPath ?: @"",
        @"index_entries": @(gJCG3Bundles.count),
        @"index_loaded_entries": @(gJCG3IndexLoadedEntries),
        @"unchanged_seeded": @(gJCG3UnchangedSeeded),
        @"persisted_ok": @(gJCG3PersistedOK),
        @"persisted_failed": @(gJCG3PersistedFailed),
        @"index_writes": @(gJCG3IndexWrites),
        @"last_event": gJCG3LastEvent ?: @"none",
        @"updated_at": JCG2Now()
    };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:&err];
    if (data && !err) [data writeToFile:gJCG3StatusPath options:NSDataWritingAtomic error:nil];
}

static void JCG3SaveIndex(void) {
    if (!gJCG3IndexPath.length || !gJCG3Bundles) return;
    NSDictionary *root = @{
        @"schema_version": @(JCG3_SCHEMA_VERSION),
        @"version": JCG3_VERSION,
        @"target": @"Unity2019.4.33f1 / IL2CPP / ToLua / Lua5.3",
        @"identity": @"path + file size + modification time",
        @"note": @"Delete bundle_index.json to force a complete disk rescan.",
        @"bundles": gJCG3Bundles,
        @"updated_at": JCG2Now()
    };
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:&err];
    if (!data || err) {
        JCG2Log([NSString stringWithFormat:@"PERSIST-INDEX serialize-fail %@", err]);
        return;
    }
    if ([data writeToFile:gJCG3IndexPath options:NSDataWritingAtomic error:&err]) {
        gJCG3IndexWrites++;
    } else {
        JCG2Log([NSString stringWithFormat:@"PERSIST-INDEX write-fail %@", err]);
    }
    JCG3WriteStatus();
}

static void JCG3RecordTerminal(NSString *path, NSString *version, NSString *status, NSNumber *textassets) {
    if (!path.length || !version.length || !status.length) return;
    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:gJCG3Bundles[path] ?: @{}];
    entry[@"version"] = version;
    entry[@"status"] = status;
    entry[@"handled"] = @YES;
    entry[@"updated_at"] = JCG2Now();
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (attrs[NSFileSize]) entry[@"size"] = attrs[NSFileSize];
    if (attrs[NSFileModificationDate]) entry[@"mtime"] = @([(NSDate *)attrs[NSFileModificationDate] timeIntervalSince1970]);
    if (textassets) entry[@"textassets"] = textassets;
    gJCG3Bundles[path] = entry;
    [gJCG3LastEvent release];
    gJCG3LastEvent = [[NSString stringWithFormat:@"%@ %@", status, path] copy];
    if ([status isEqualToString:@"ok"]) gJCG3PersistedOK++;
    else gJCG3PersistedFailed++;
}

static BOOL JCG3ProcessLogLine(NSString *line) {
    if (!line.length) return NO;

    // Success is persisted only after BUNDLE-SWEEP completes. A crash between
    // LoadFromFile and the sweep therefore causes a safe retry on next launch.
    if ([line containsString:@"BUNDLE-SWEEP origin=disk:"]) {
        NSString *path = JCG3StringBetween(line, @"BUNDLE-SWEEP origin=disk:", @" bundle=");
        if (path.length) {
            NSString *version = nil;
            pthread_mutex_lock(&gDiskLock);
            version = [[gDiskSeenVersions[path] copy] autorelease];
            pthread_mutex_unlock(&gDiskLock);
            if (!version.length) version = JCG3CurrentDiskVersion(path);
            NSString *textString = JCG3StringBetween(line, @" textassets=", @"");
            NSNumber *textassets = textString.length ? @([textString longLongValue]) : nil;
            if (version.length) {
                JCG3RecordTerminal(path, version, @"ok", textassets);
                return YES;
            }
        }
    }

    // A stable Unity-magic file that LoadFromFile rejects is terminal for that
    // exact version. If the downloader later changes size/mtime it is retried.
    if ([line containsString:@"DISK-BUNDLE-LOAD-FAIL path="]) {
        NSString *path = JCG3StringBetween(line, @"DISK-BUNDLE-LOAD-FAIL path=", @" version=");
        NSString *version = JCG3StringBetween(line, @" version=", @"");
        if (path.length && version.length) {
            JCG3RecordTerminal(path, version, @"load_failed", nil);
            return YES;
        }
    }
    return NO;
}

static void JCG3ConsumeNewLogBytes(void) {
    if (!gLogPath.length || !gJCG3Bundles) return;
    NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:gLogPath];
    if (!h) return;
    unsigned long long length = 0;
    @try { length = [h seekToEndOfFile]; } @catch (__unused NSException *e) { [h closeFile]; return; }
    if (length < gJCG3LogOffset) gJCG3LogOffset = 0;
    if (length == gJCG3LogOffset) { [h closeFile]; return; }
    @try {
        [h seekToFileOffset:gJCG3LogOffset];
        NSData *data = [h readDataToEndOfFile];
        gJCG3LogOffset = length;
        [h closeFile];
        if (!data.length) return;
        NSString *piece = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
        if (!piece) return;
        [gJCG3LogCarry appendString:piece];
        NSArray *parts = [gJCG3LogCarry componentsSeparatedByString:@"\n"];
        if (!parts.count) return;
        [gJCG3LogCarry setString:parts.lastObject ?: @""];
        BOOL dirty = NO;
        for (NSUInteger i = 0; i + 1 < parts.count; i++) {
            if (JCG3ProcessLogLine(parts[i])) dirty = YES;
        }
        if (dirty) JCG3SaveIndex();
    } @catch (__unused NSException *e) {
        @try { [h closeFile]; } @catch (__unused NSException *x) {}
    }
}

static void JCG3ScheduleLogPoll(void);
static void JCG3LogPoll(void) {
    if (!gRunning) return;
    dispatch_async(gJCG3PersistQueue, ^{ @autoreleasepool { JCG3ConsumeNewLogBytes(); } });
    JCG3ScheduleLogPoll();
}

static void JCG3ScheduleLogPoll(void) {
    if (!gRunning) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(JCG3_LOG_POLL_SECONDS * NSEC_PER_SEC)),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ JCG3LogPoll(); });
}

static void JCG3LoadPersistentIndex(void) {
    if (gJCG3Initialized) return;
    // The included g2 constructor initializes these before its first disk pass
    // (which starts after one second). If constructor ordering differs, retry.
    if (!gRootPath.length || !gDiskSeenVersions) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ JCG3LoadPersistentIndex(); });
        return;
    }

    gJCG3IndexPath = [[gRootPath stringByAppendingPathComponent:@"bundle_index.json"] retain];
    gJCG3StatusPath = [[gRootPath stringByAppendingPathComponent:@"PersistentIncremental.status.json"] retain];
    gJCG3Bundles = [[NSMutableDictionary alloc] init];
    gJCG3LogCarry = [[NSMutableString alloc] init];
    gJCG3PersistQueue = dispatch_queue_create("com.openai.jsoncapture.persistindex", DISPATCH_QUEUE_SERIAL);

    NSData *data = [NSData dataWithContentsOfFile:gJCG3IndexPath];
    if (data.length) {
        NSError *err = nil;
        id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
        NSDictionary *bundles = [root isKindOfClass:[NSDictionary class]] ? [root objectForKey:@"bundles"] : nil;
        if ([bundles isKindOfClass:[NSDictionary class]]) [gJCG3Bundles addEntriesFromDictionary:bundles];
        else if (err) JCG2Log([NSString stringWithFormat:@"PERSIST-INDEX parse-fail %@", err]);
    }

    gJCG3IndexLoadedEntries = gJCG3Bundles.count;
    NSFileManager *fm = [NSFileManager defaultManager];
    pthread_mutex_lock(&gDiskLock);
    for (NSString *path in gJCG3Bundles) {
        NSDictionary *entry = gJCG3Bundles[path];
        if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"handled"] boolValue]) continue;
        NSString *version = entry[@"version"];
        if (!version.length) continue;
        gDiskSeenVersions[path] = version;
        NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
        if (attrs && [[JCG2FileVersion(path, attrs) description] isEqualToString:version]) gJCG3UnchangedSeeded++;
    }
    pthread_mutex_unlock(&gDiskLock);

    // Ignore historical log bytes; only terminal events from this process are
    // allowed to advance the persistent index.
    NSDictionary *logAttrs = [fm attributesOfItemAtPath:gLogPath error:nil];
    gJCG3LogOffset = [logAttrs[NSFileSize] unsignedLongLongValue];
    gJCG3Initialized = YES;
    JCG2Log([NSString stringWithFormat:@"PERSIST-INDEX ready entries=%llu unchanged_seeded=%llu path=%@",
             gJCG3IndexLoadedEntries, gJCG3UnchangedSeeded, gJCG3IndexPath]);
    JCG3WriteStatus();
    JCG3ScheduleLogPoll();
}

__attribute__((constructor)) static void JCG3Entry(void) {
    @autoreleasepool {
        // Run after image construction but before the g2 disk watcher performs
        // its first pass. This avoids relying on constructor lexical ordering.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ JCG3LoadPersistentIndex(); });
    }
}
