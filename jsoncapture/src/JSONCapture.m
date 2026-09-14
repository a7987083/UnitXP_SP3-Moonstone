#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#define JC_VERSION @"JSONCapture v0.1"
#define MAX_DELEGATE_HOOKS 48
#define MAX_JSON_BYTES (256ULL * 1024ULL * 1024ULL)
#define MAX_NETWORK_BUFFER (128ULL * 1024ULL * 1024ULL)
#define RVA_CUSTOM_DECRYPT_STRING 0x186A4B8ULL
#define RVA_CUSTOM_DECRYPT_BYTES  0x186FA64ULL

typedef struct {
    Class cls;
    IMP responseIMP;
    IMP dataIMP;
    IMP completeIMP;
    IMP downloadIMP;
    BOOL responseHooked;
    BOOL dataHooked;
    BOOL completeHooked;
    BOOL downloadHooked;
} JCDelegateHook;

typedef struct {
    void *klass;
    void *monitor;
    int32_t length;
    uint16_t chars[0];
} JCIl2CppString;

typedef void *(*JCCustomDecryptFn)(void *data, const void *method);
typedef void (*JCMSHookFunctionFn)(void *symbol, void *replace, void **result);
typedef int (*JCDobbyHookFn)(void *address, void *replace, void **origin);

static UIWindow *gWindow;
static UIButton *gFloatButton;
static UIView *gPanel;
static UILabel *gStatusLabel;
static UITextView *gTextView;
static UIButton *gToggleButton;
static NSMutableArray *gEvents;
static NSMutableDictionary *gTaskStates;
static NSMutableSet *gSeenHashes;
static NSString *gRootPath;
static NSString *gLogPath;
static dispatch_queue_t gCaptureQueue;
static BOOL gCaptureEnabled = YES;
static BOOL gHooksInstalled = NO;
static BOOL gDecryptHookInstalled = NO;
static BOOL gUIReady = NO;
static unsigned long long gSeq = 0;
static unsigned long long gCaptured = 0;
static unsigned long long gDuplicates = 0;
static unsigned long long gRejected = 0;
static unsigned long long gNetworkCaptured = 0;
static unsigned long long gParserCaptured = 0;
static unsigned long long gFileCaptured = 0;
static unsigned long long gDecryptCaptured = 0;
static __thread int gInsideInternal = 0;
static pthread_mutex_t gLogLock = PTHREAD_MUTEX_INITIALIZER;

static JCDelegateHook gDelegateHooks[MAX_DELEGATE_HOOKS];
static NSUInteger gDelegateHookCount = 0;

static IMP gJSONObjDataIMP;
static IMP gJSONDataObjIMP;
static IMP gNSDataFileIMP;
static IMP gNSDataFileOptionsIMP;
static IMP gNSDataURLIMP;
static IMP gNSDataURLOptionsIMP;
static IMP gNSStringFileEncIMP;
static IMP gNSStringFileUsedEncIMP;
static IMP gNSStringURLEncIMP;
static IMP gNSStringURLUsedEncIMP;

static IMP gDataTaskReqIMP;
static IMP gDataTaskReqCompletionIMP;
static IMP gDataTaskURLIMP;
static IMP gDataTaskURLCompletionIMP;
static IMP gUploadReqDataIMP;
static IMP gUploadReqDataCompletionIMP;
static IMP gDownloadReqIMP;
static IMP gDownloadReqCompletionIMP;
static IMP gDownloadURLIMP;
static IMP gDownloadURLCompletionIMP;
static IMP gSyncRequestIMP;
static IMP gAsyncRequestIMP;

static JCCustomDecryptFn gOrigDecryptString;
static JCCustomDecryptFn gOrigDecryptBytes;
static NSString *gDecryptHookAPI;

#pragma mark - Utility

static NSString *JCNowText(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *JCDocumentsPath(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? [paths objectAtIndex:0] : NSTemporaryDirectory();
}

static void JCEnsureDirectory(NSString *path) {
    if (!path.length) return;
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
}

static void JCSetupPaths(void) {
    if (gRootPath.length) return;
    gRootPath = [[[JCDocumentsPath() stringByAppendingPathComponent:@"JSONCapture"] stringByStandardizingPath] retain];
    gLogPath = [[gRootPath stringByAppendingPathComponent:@"JSONCapture.log"] retain];
    JCEnsureDirectory(gRootPath);
    for (NSString *dir in @[@"network", @"parser", @"file", @"decrypt", @"outgoing"]) {
        JCEnsureDirectory([gRootPath stringByAppendingPathComponent:dir]);
    }
}

static void JCAppendLog(NSString *line) {
    if (!line.length || !gLogPath.length) return;
    pthread_mutex_lock(&gLogLock);
    FILE *f = fopen(gLogPath.fileSystemRepresentation, "a");
    if (f) {
        NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fflush(f);
        fclose(f);
    }
    pthread_mutex_unlock(&gLogLock);
}

static void JCRefreshUI(void);

static void JCPushEvent(NSString *text) {
    if (!text.length) return;
    unsigned long long seq = __sync_add_and_fetch(&gSeq, 1);
    NSString *line = [NSString stringWithFormat:@"[%@] #%llu %@", JCNowText(), seq, text];
    JCAppendLog(line);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gEvents) gEvents = [[NSMutableArray alloc] init];
        [gEvents addObject:line];
        while (gEvents.count > 40) [gEvents removeObjectAtIndex:0];
        JCRefreshUI();
    });
}

static NSString *JCSHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static NSString *JCSafeName(NSString *text) {
    if (!text.length) return @"unknown";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN(text.length, 80)];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."];
    for (NSUInteger i = 0; i < text.length && out.length < 80; i++) {
        unichar c = [text characterAtIndex:i];
        [out appendFormat:@"%@", [ok characterIsMember:c] ? [NSString stringWithCharacters:&c length:1] : @"_"];
    }
    return out.length ? out : @"unknown";
}

static BOOL JCPrefixLooksJSON(NSData *data) {
    if (!data.length) return NO;
    const unsigned char *p = data.bytes;
    NSUInteger i = 0;
    if (data.length >= 3 && p[0] == 0xEF && p[1] == 0xBB && p[2] == 0xBF) i = 3;
    while (i < data.length) {
        unsigned char c = p[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') { i++; continue; }
        return c == '{' || c == '[';
    }
    return NO;
}

typedef id (*JCJSONObjectWithDataFn)(id, SEL, NSData *, NSJSONReadingOptions, NSError **);
typedef NSData *(*JCDataWithJSONObjectFn)(id, SEL, id, NSJSONWritingOptions, NSError **);

static BOOL JCIsValidJSONData(NSData *data) {
    if (!data.length || data.length > MAX_JSON_BYTES || !JCPrefixLooksJSON(data)) return NO;
    NSError *err = nil;
    id obj = nil;
    gInsideInternal++;
    if (gJSONObjDataIMP) {
        obj = ((JCJSONObjectWithDataFn)gJSONObjDataIMP)([NSJSONSerialization class], @selector(JSONObjectWithData:options:error:), data, NSJSONReadingAllowFragments, &err);
    } else {
        obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&err];
    }
    gInsideInternal--;
    return obj != nil && err == nil;
}

static NSString *JCSourceDirectory(NSString *source) {
    if ([source hasPrefix:@"network"]) return @"network";
    if ([source hasPrefix:@"parser"]) return @"parser";
    if ([source hasPrefix:@"file"]) return @"file";
    if ([source hasPrefix:@"decrypt"]) return @"decrypt";
    if ([source hasPrefix:@"outgoing"]) return @"outgoing";
    return @"parser";
}

static void JCIncrementSourceCounter(NSString *dir) {
    if ([dir isEqualToString:@"network"]) __sync_add_and_fetch(&gNetworkCaptured, 1);
    else if ([dir isEqualToString:@"parser"]) __sync_add_and_fetch(&gParserCaptured, 1);
    else if ([dir isEqualToString:@"file"]) __sync_add_and_fetch(&gFileCaptured, 1);
    else if ([dir isEqualToString:@"decrypt"]) __sync_add_and_fetch(&gDecryptCaptured, 1);
}

static void JCCaptureData(NSData *data, NSString *source, NSString *context, BOOL trustedJSON) {
    if (!gCaptureEnabled || gInsideInternal || !data.length) return;
    if (data.length > MAX_JSON_BYTES) {
        __sync_add_and_fetch(&gRejected, 1);
        JCPushEvent([NSString stringWithFormat:@"SKIP too-large source=%@ bytes=%lu", source ?: @"?", (unsigned long)data.length]);
        return;
    }

    NSData *snapshot = [NSData dataWithData:data];
    NSString *src = source.length ? [NSString stringWithString:source] : @"unknown";
    NSString *ctx = context.length ? [NSString stringWithString:context] : @"";
    if (!gCaptureQueue) return;

    dispatch_async(gCaptureQueue, ^{
        @autoreleasepool {
            if (!gCaptureEnabled) return;
            if (!trustedJSON && !JCIsValidJSONData(snapshot)) {
                __sync_add_and_fetch(&gRejected, 1);
                return;
            }

            NSString *hash = JCSHA256(snapshot);
            if (!hash.length) return;
            if ([gSeenHashes containsObject:hash]) {
                __sync_add_and_fetch(&gDuplicates, 1);
                dispatch_async(dispatch_get_main_queue(), ^{ JCRefreshUI(); });
                return;
            }
            [gSeenHashes addObject:hash];

            unsigned long long idx = __sync_add_and_fetch(&gCaptured, 1);
            NSString *dirName = JCSourceDirectory(src);
            JCIncrementSourceCounter(dirName);
            NSString *dir = [gRootPath stringByAppendingPathComponent:dirName];
            JCEnsureDirectory(dir);
            NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
            NSString *base = [NSString stringWithFormat:@"%06llu_%@_%@", idx, JCSafeName(src), shortHash];
            NSString *jsonPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".json"]];
            NSString *metaPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".meta.json"]];

            NSError *writeErr = nil;
            gInsideInternal++;
            BOOL ok = [snapshot writeToFile:jsonPath options:NSDataWritingAtomic error:&writeErr];
            gInsideInternal--;
            if (!ok) {
                JCAppendLog([NSString stringWithFormat:@"[%@] WRITE-FAIL %@ err=%@", JCNowText(), jsonPath, writeErr]);
                return;
            }

            NSDictionary *meta = @{
                @"version": JC_VERSION,
                @"index": @(idx),
                @"source": src,
                @"context": ctx,
                @"bytes": @(snapshot.length),
                @"sha256": hash,
                @"captured_at": JCNowText(),
                @"json_file": jsonPath.lastPathComponent ?: @""
            };
            NSError *metaErr = nil;
            NSData *metaData = nil;
            gInsideInternal++;
            if (gJSONDataObjIMP) {
                metaData = ((JCDataWithJSONObjectFn)gJSONDataObjIMP)([NSJSONSerialization class], @selector(dataWithJSONObject:options:error:), meta, NSJSONWritingPrettyPrinted, &metaErr);
            } else {
                metaData = [NSJSONSerialization dataWithJSONObject:meta options:NSJSONWritingPrettyPrinted error:&metaErr];
            }
            if (metaData.length) [metaData writeToFile:metaPath options:NSDataWritingAtomic error:nil];
            gInsideInternal--;

            JCAppendLog([NSString stringWithFormat:@"[%@] CAPTURE #%llu source=%@ bytes=%lu sha256=%@ context=%@ file=%@",
                         JCNowText(), idx, src, (unsigned long)snapshot.length, hash, ctx, jsonPath]);
            dispatch_async(dispatch_get_main_queue(), ^{
                JCPushEvent([NSString stringWithFormat:@"CAPTURE #%llu %@ %luB %@", idx, src, (unsigned long)snapshot.length, shortHash]);
                JCRefreshUI();
            });
        }
    });
}

static void JCCaptureString(NSString *text, NSString *source, NSString *context, BOOL trustedJSON) {
    if (!text.length || gInsideInternal) return;
    NSData *d = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (d.length) JCCaptureData(d, source, context, trustedJSON);
}

#pragma mark - NSJSONSerialization hooks

static id JCHookJSONObjectWithData(id self, SEL _cmd, NSData *data, NSJSONReadingOptions options, NSError **error) {
    id obj = ((JCJSONObjectWithDataFn)gJSONObjDataIMP)(self, _cmd, data, options, error);
    if (!gInsideInternal && obj && data.length) JCCaptureData(data, @"parser-foundation", @"NSJSONSerialization JSONObjectWithData", YES);
    return obj;
}

static NSData *JCHookDataWithJSONObject(id self, SEL _cmd, id obj, NSJSONWritingOptions options, NSError **error) {
    NSData *data = ((JCDataWithJSONObjectFn)gJSONDataObjIMP)(self, _cmd, obj, options, error);
    if (!gInsideInternal && data.length) JCCaptureData(data, @"outgoing-foundation", @"NSJSONSerialization dataWithJSONObject", YES);
    return data;
}

#pragma mark - File / URL hooks

typedef NSData *(*JCDataFileFn)(id, SEL, NSString *);
typedef NSData *(*JCDataFileOptionsFn)(id, SEL, NSString *, NSDataReadingOptions, NSError **);
typedef NSData *(*JCDataURLFn)(id, SEL, NSURL *);
typedef NSData *(*JCDataURLOptionsFn)(id, SEL, NSURL *, NSDataReadingOptions, NSError **);
typedef NSString *(*JCStringFileEncFn)(id, SEL, NSString *, NSStringEncoding, NSError **);
typedef NSString *(*JCStringFileUsedEncFn)(id, SEL, NSString *, NSStringEncoding *, NSError **);
typedef NSString *(*JCStringURLEncFn)(id, SEL, NSURL *, NSStringEncoding, NSError **);
typedef NSString *(*JCStringURLUsedEncFn)(id, SEL, NSURL *, NSStringEncoding *, NSError **);

static BOOL JCPathIsJSON(NSString *path) {
    return [[path.pathExtension lowercaseString] isEqualToString:@"json"];
}

static NSData *JCHookNSDataFile(id self, SEL _cmd, NSString *path) {
    NSData *data = ((JCDataFileFn)gNSDataFileIMP)(self, _cmd, path);
    if (!gInsideInternal && data.length) JCCaptureData(data, @"file-nsdata", path ?: @"", JCPathIsJSON(path));
    return data;
}

static NSData *JCHookNSDataFileOptions(id self, SEL _cmd, NSString *path, NSDataReadingOptions options, NSError **error) {
    NSData *data = ((JCDataFileOptionsFn)gNSDataFileOptionsIMP)(self, _cmd, path, options, error);
    if (!gInsideInternal && data.length) JCCaptureData(data, @"file-nsdata-options", path ?: @"", JCPathIsJSON(path));
    return data;
}

static NSData *JCHookNSDataURL(id self, SEL _cmd, NSURL *url) {
    NSData *data = ((JCDataURLFn)gNSDataURLIMP)(self, _cmd, url);
    if (!gInsideInternal && data.length) JCCaptureData(data, @"file-nsdata-url", url.absoluteString ?: @"", JCPathIsJSON(url.path));
    return data;
}

static NSData *JCHookNSDataURLOptions(id self, SEL _cmd, NSURL *url, NSDataReadingOptions options, NSError **error) {
    NSData *data = ((JCDataURLOptionsFn)gNSDataURLOptionsIMP)(self, _cmd, url, options, error);
    if (!gInsideInternal && data.length) JCCaptureData(data, @"file-nsdata-url-options", url.absoluteString ?: @"", JCPathIsJSON(url.path));
    return data;
}

static NSString *JCHookNSStringFileEnc(id self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error) {
    NSString *text = ((JCStringFileEncFn)gNSStringFileEncIMP)(self, _cmd, path, enc, error);
    if (!gInsideInternal && text.length) JCCaptureString(text, @"file-nsstring", path ?: @"", JCPathIsJSON(path));
    return text;
}

static NSString *JCHookNSStringFileUsedEnc(id self, SEL _cmd, NSString *path, NSStringEncoding *enc, NSError **error) {
    NSString *text = ((JCStringFileUsedEncFn)gNSStringFileUsedEncIMP)(self, _cmd, path, enc, error);
    if (!gInsideInternal && text.length) JCCaptureString(text, @"file-nsstring-usedenc", path ?: @"", JCPathIsJSON(path));
    return text;
}

static NSString *JCHookNSStringURLEnc(id self, SEL _cmd, NSURL *url, NSStringEncoding enc, NSError **error) {
    NSString *text = ((JCStringURLEncFn)gNSStringURLEncIMP)(self, _cmd, url, enc, error);
    if (!gInsideInternal && text.length) JCCaptureString(text, @"file-nsstring-url", url.absoluteString ?: @"", JCPathIsJSON(url.path));
    return text;
}

static NSString *JCHookNSStringURLUsedEnc(id self, SEL _cmd, NSURL *url, NSStringEncoding *enc, NSError **error) {
    NSString *text = ((JCStringURLUsedEncFn)gNSStringURLUsedEncIMP)(self, _cmd, url, enc, error);
    if (!gInsideInternal && text.length) JCCaptureString(text, @"file-nsstring-url-usedenc", url.absoluteString ?: @"", JCPathIsJSON(url.path));
    return text;
}

#pragma mark - NSURLSession / NSURLConnection hooks

static NSString *JCTaskKey(NSURLSession *session, NSURLSessionTask *task) {
    if (!session || !task) return nil;
    return [NSString stringWithFormat:@"%p:%lu", session, (unsigned long)task.taskIdentifier];
}

static BOOL JCMIMEHintsJSON(NSURLResponse *response) {
    NSString *mime = [response.MIMEType lowercaseString];
    NSString *ext = [response.URL.pathExtension lowercaseString];
    return [mime containsString:@"json"] || [ext isEqualToString:@"json"];
}

static NSMutableDictionary *JCMakeTaskState(NSURLRequest *req) {
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    NSString *url = req.URL.absoluteString ?: @"";
    NSString *method = req.HTTPMethod.length ? req.HTTPMethod : @"GET";
    [state setObject:url forKey:@"url"];
    [state setObject:method forKey:@"method"];
    [state setObject:[NSMutableData data] forKey:@"data"];
    [state setObject:@(-1) forKey:@"candidate"];
    [state setObject:@0 forKey:@"truncated"];
    return state;
}

static NSMutableDictionary *JCEnsureTaskState(NSURLSession *session, NSURLSessionTask *task) {
    if (!session || !task || !gTaskStates) return nil;
    NSString *key = JCTaskKey(session, task);
    if (!key) return nil;
    @synchronized(gTaskStates) {
        NSMutableDictionary *state = [gTaskStates objectForKey:key];
        if (!state) {
            NSURLRequest *req = task.currentRequest ?: task.originalRequest;
            state = JCMakeTaskState(req ?: [NSURLRequest requestWithURL:(task.response.URL ?: [NSURL URLWithString:@"about:blank"])]);
            [gTaskStates setObject:state forKey:key];
        }
        return state;
    }
}

static void JCRegisterTask(NSURLSession *session, NSURLSessionTask *task, NSURLRequest *req) {
    if (!session || !task || !req || !gTaskStates) return;
    NSString *key = JCTaskKey(session, task);
    if (!key) return;
    @synchronized(gTaskStates) {
        if (![gTaskStates objectForKey:key]) [gTaskStates setObject:JCMakeTaskState(req) forKey:key];
    }
    if (req.HTTPBody.length) JCCaptureData(req.HTTPBody, @"outgoing-http-body", req.URL.absoluteString ?: @"", NO);
}

static JCDelegateHook *JCFindDelegateHook(Class cls) {
    if (!cls) return NULL;
    for (NSUInteger i = 0; i < gDelegateHookCount; i++) if (gDelegateHooks[i].cls == cls) return &gDelegateHooks[i];
    return NULL;
}

static IMP JCInstallDelegateMethod(Class cls, SEL sel, IMP hook) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    IMP old = method_getImplementation(m);
    const char *types = method_getTypeEncoding(m);
    if (class_addMethod(cls, sel, hook, types)) return old;
    Method own = class_getInstanceMethod(cls, sel);
    if (!own) return NULL;
    return method_setImplementation(own, hook);
}

typedef void (*JCDidReceiveResponseFn)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSURLResponse *, void (^)(NSURLSessionResponseDisposition));
typedef void (*JCDidReceiveDataFn)(id, SEL, NSURLSession *, NSURLSessionDataTask *, NSData *);
typedef void (*JCDidCompleteFn)(id, SEL, NSURLSession *, NSURLSessionTask *, NSError *);
typedef void (*JCDidFinishDownloadFn)(id, SEL, NSURLSession *, NSURLSessionDownloadTask *, NSURL *);

static void JCHookDelegateDidReceiveResponse(id self, SEL _cmd, NSURLSession *session, NSURLSessionDataTask *task,
                                             NSURLResponse *response, void (^completionHandler)(NSURLSessionResponseDisposition)) {
    NSMutableDictionary *state = JCEnsureTaskState(session, task);
    if (state && JCMIMEHintsJSON(response)) [state setObject:@1 forKey:@"candidate"];
    JCDelegateHook *h = JCFindDelegateHook(object_getClass(self));
    if (h && h->responseIMP) ((JCDidReceiveResponseFn)h->responseIMP)(self, _cmd, session, task, response, completionHandler);
}

static void JCHookDelegateDidReceiveData(id self, SEL _cmd, NSURLSession *session, NSURLSessionDataTask *task, NSData *data) {
    NSMutableDictionary *state = JCEnsureTaskState(session, task);
    if (state && data.length) {
        @synchronized(gTaskStates) {
            NSInteger candidate = [[state objectForKey:@"candidate"] integerValue];
            if (candidate < 0) {
                candidate = JCPrefixLooksJSON(data) ? 1 : 0;
                [state setObject:@(candidate) forKey:@"candidate"];
            }
            if (candidate == 1) {
                NSMutableData *buffer = [state objectForKey:@"data"];
                NSUInteger room = buffer.length < MAX_NETWORK_BUFFER ? (NSUInteger)(MAX_NETWORK_BUFFER - buffer.length) : 0;
                NSUInteger take = MIN(room, data.length);
                if (take) [buffer appendData:[data subdataWithRange:NSMakeRange(0, take)]];
                if (take < data.length) [state setObject:@1 forKey:@"truncated"];
            }
        }
    }
    JCDelegateHook *h = JCFindDelegateHook(object_getClass(self));
    if (h && h->dataIMP) ((JCDidReceiveDataFn)h->dataIMP)(self, _cmd, session, task, data);
}

static void JCHookDelegateDidComplete(id self, SEL _cmd, NSURLSession *session, NSURLSessionTask *task, NSError *error) {
    NSMutableDictionary *state = JCEnsureTaskState(session, task);
    if (state) {
        NSString *key = JCTaskKey(session, task);
        NSData *body = nil;
        NSString *url = nil;
        BOOL truncated = NO;
        @synchronized(gTaskStates) {
            body = [[[state objectForKey:@"data"] copy] autorelease];
            url = [[[state objectForKey:@"url"] copy] autorelease];
            truncated = [[state objectForKey:@"truncated"] boolValue];
            if (key) [gTaskStates removeObjectForKey:key];
        }
        if (body.length && !truncated) JCCaptureData(body, @"network-delegate", url ?: @"", NO);
        else if (truncated) JCPushEvent([NSString stringWithFormat:@"NETWORK truncated task=%lu %@", (unsigned long)task.taskIdentifier, url ?: @""]);
    }
    JCDelegateHook *h = JCFindDelegateHook(object_getClass(self));
    if (h && h->completeIMP) ((JCDidCompleteFn)h->completeIMP)(self, _cmd, session, task, error);
}

static void JCHookDelegateDidFinishDownload(id self, SEL _cmd, NSURLSession *session, NSURLSessionDownloadTask *task, NSURL *location) {
    if (location) {
        gInsideInternal++;
        NSData *data = [NSData dataWithContentsOfURL:location];
        gInsideInternal--;
        if (data.length) JCCaptureData(data, @"network-download-delegate", task.response.URL.absoluteString ?: @"", JCPathIsJSON(task.response.URL.path));
    }
    JCDelegateHook *h = JCFindDelegateHook(object_getClass(self));
    if (h && h->downloadIMP) ((JCDidFinishDownloadFn)h->downloadIMP)(self, _cmd, session, task, location);
}

static void JCInstallDelegateHooksForSession(NSURLSession *session) {
    id delegate = session.delegate;
    if (!delegate) return;
    Class cls = object_getClass(delegate);
    if (!cls || JCFindDelegateHook(cls) || gDelegateHookCount >= MAX_DELEGATE_HOOKS) return;

    JCDelegateHook *h = &gDelegateHooks[gDelegateHookCount++];
    memset(h, 0, sizeof(*h));
    h->cls = cls;
    h->responseIMP = JCInstallDelegateMethod(cls, @selector(URLSession:dataTask:didReceiveResponse:completionHandler:), (IMP)JCHookDelegateDidReceiveResponse);
    h->dataIMP = JCInstallDelegateMethod(cls, @selector(URLSession:dataTask:didReceiveData:), (IMP)JCHookDelegateDidReceiveData);
    h->completeIMP = JCInstallDelegateMethod(cls, @selector(URLSession:task:didCompleteWithError:), (IMP)JCHookDelegateDidComplete);
    h->downloadIMP = JCInstallDelegateMethod(cls, @selector(URLSession:downloadTask:didFinishDownloadingToURL:), (IMP)JCHookDelegateDidFinishDownload);
    h->responseHooked = h->responseIMP != NULL;
    h->dataHooked = h->dataIMP != NULL;
    h->completeHooked = h->completeIMP != NULL;
    h->downloadHooked = h->downloadIMP != NULL;
    JCPushEvent([NSString stringWithFormat:@"DELEGATE-HOOK %@ response=%d data=%d complete=%d download=%d",
                 NSStringFromClass(cls), h->responseHooked, h->dataHooked, h->completeHooked, h->downloadHooked]);
}

typedef NSURLSessionDataTask *(*JCDataTaskReqFn)(id, SEL, NSURLRequest *);
typedef NSURLSessionDataTask *(*JCDataTaskReqCompletionFn)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
typedef NSURLSessionDataTask *(*JCDataTaskURLFn)(id, SEL, NSURL *);
typedef NSURLSessionDataTask *(*JCDataTaskURLCompletionFn)(id, SEL, NSURL *, void (^)(NSData *, NSURLResponse *, NSError *));
typedef NSURLSessionUploadTask *(*JCUploadReqDataFn)(id, SEL, NSURLRequest *, NSData *);
typedef NSURLSessionUploadTask *(*JCUploadReqDataCompletionFn)(id, SEL, NSURLRequest *, NSData *, void (^)(NSData *, NSURLResponse *, NSError *));
typedef NSURLSessionDownloadTask *(*JCDownloadReqFn)(id, SEL, NSURLRequest *);
typedef NSURLSessionDownloadTask *(*JCDownloadReqCompletionFn)(id, SEL, NSURLRequest *, void (^)(NSURL *, NSURLResponse *, NSError *));
typedef NSURLSessionDownloadTask *(*JCDownloadURLFn)(id, SEL, NSURL *);
typedef NSURLSessionDownloadTask *(*JCDownloadURLCompletionFn)(id, SEL, NSURL *, void (^)(NSURL *, NSURLResponse *, NSError *));
typedef NSData *(*JCSyncRequestFn)(id, SEL, NSURLRequest *, NSURLResponse **, NSError **);
typedef void (*JCAsyncRequestFn)(id, SEL, NSURLRequest *, NSOperationQueue *, void (^)(NSURLResponse *, NSData *, NSError *));

static NSURLSessionDataTask *JCHookDataTaskReq(id self, SEL _cmd, NSURLRequest *req) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    NSURLSessionDataTask *task = ((JCDataTaskReqFn)gDataTaskReqIMP)(self, _cmd, req);
    JCRegisterTask((NSURLSession *)self, task, req);
    return task;
}

static NSURLSessionDataTask *JCHookDataTaskReqCompletion(id self, SEL _cmd, NSURLRequest *req, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    if (req.HTTPBody.length) JCCaptureData(req.HTTPBody, @"outgoing-http-body", req.URL.absoluteString ?: @"", NO);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (data.length) JCCaptureData(data, @"network-completion", resp.URL.absoluteString ?: req.URL.absoluteString ?: @"", NO);
        if (completion) completion(data, resp, err);
    };
    return ((JCDataTaskReqCompletionFn)gDataTaskReqCompletionIMP)(self, _cmd, req, wrapped);
}

static NSURLSessionDataTask *JCHookDataTaskURL(id self, SEL _cmd, NSURL *url) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    NSURLSessionDataTask *task = ((JCDataTaskURLFn)gDataTaskURLIMP)(self, _cmd, url);
    if (url) JCRegisterTask((NSURLSession *)self, task, [NSURLRequest requestWithURL:url]);
    return task;
}

static NSURLSessionDataTask *JCHookDataTaskURLCompletion(id self, SEL _cmd, NSURL *url, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (data.length) JCCaptureData(data, @"network-url-completion", resp.URL.absoluteString ?: url.absoluteString ?: @"", NO);
        if (completion) completion(data, resp, err);
    };
    return ((JCDataTaskURLCompletionFn)gDataTaskURLCompletionIMP)(self, _cmd, url, wrapped);
}

static NSURLSessionUploadTask *JCHookUploadReqData(id self, SEL _cmd, NSURLRequest *req, NSData *body) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    if (body.length) JCCaptureData(body, @"outgoing-upload", req.URL.absoluteString ?: @"", NO);
    return ((JCUploadReqDataFn)gUploadReqDataIMP)(self, _cmd, req, body);
}

static NSURLSessionUploadTask *JCHookUploadReqDataCompletion(id self, SEL _cmd, NSURLRequest *req, NSData *body, void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    if (body.length) JCCaptureData(body, @"outgoing-upload", req.URL.absoluteString ?: @"", NO);
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (data.length) JCCaptureData(data, @"network-upload-completion", resp.URL.absoluteString ?: req.URL.absoluteString ?: @"", NO);
        if (completion) completion(data, resp, err);
    };
    return ((JCUploadReqDataCompletionFn)gUploadReqDataCompletionIMP)(self, _cmd, req, body, wrapped);
}

static NSURLSessionDownloadTask *JCHookDownloadReq(id self, SEL _cmd, NSURLRequest *req) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    return ((JCDownloadReqFn)gDownloadReqIMP)(self, _cmd, req);
}

static NSURLSessionDownloadTask *JCHookDownloadReqCompletion(id self, SEL _cmd, NSURLRequest *req, void (^completion)(NSURL *, NSURLResponse *, NSError *)) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    void (^wrapped)(NSURL *, NSURLResponse *, NSError *) = ^(NSURL *location, NSURLResponse *resp, NSError *err) {
        if (location) {
            gInsideInternal++;
            NSData *data = [NSData dataWithContentsOfURL:location];
            gInsideInternal--;
            if (data.length) JCCaptureData(data, @"network-download-completion", resp.URL.absoluteString ?: req.URL.absoluteString ?: @"", JCPathIsJSON(resp.URL.path));
        }
        if (completion) completion(location, resp, err);
    };
    return ((JCDownloadReqCompletionFn)gDownloadReqCompletionIMP)(self, _cmd, req, wrapped);
}

static NSURLSessionDownloadTask *JCHookDownloadURL(id self, SEL _cmd, NSURL *url) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    return ((JCDownloadURLFn)gDownloadURLIMP)(self, _cmd, url);
}

static NSURLSessionDownloadTask *JCHookDownloadURLCompletion(id self, SEL _cmd, NSURL *url, void (^completion)(NSURL *, NSURLResponse *, NSError *)) {
    JCInstallDelegateHooksForSession((NSURLSession *)self);
    void (^wrapped)(NSURL *, NSURLResponse *, NSError *) = ^(NSURL *location, NSURLResponse *resp, NSError *err) {
        if (location) {
            gInsideInternal++;
            NSData *data = [NSData dataWithContentsOfURL:location];
            gInsideInternal--;
            if (data.length) JCCaptureData(data, @"network-download-url-completion", resp.URL.absoluteString ?: url.absoluteString ?: @"", JCPathIsJSON(resp.URL.path));
        }
        if (completion) completion(location, resp, err);
    };
    return ((JCDownloadURLCompletionFn)gDownloadURLCompletionIMP)(self, _cmd, url, wrapped);
}

static NSData *JCHookSyncRequest(id self, SEL _cmd, NSURLRequest *req, NSURLResponse **resp, NSError **err) {
    if (req.HTTPBody.length) JCCaptureData(req.HTTPBody, @"outgoing-nsurlconnection", req.URL.absoluteString ?: @"", NO);
    NSData *data = ((JCSyncRequestFn)gSyncRequestIMP)(self, _cmd, req, resp, err);
    if (data.length) JCCaptureData(data, @"network-nsurlconnection-sync", (resp && *resp) ? (*resp).URL.absoluteString : req.URL.absoluteString, NO);
    return data;
}

static void JCHookAsyncRequest(id self, SEL _cmd, NSURLRequest *req, NSOperationQueue *queue, void (^completion)(NSURLResponse *, NSData *, NSError *)) {
    if (req.HTTPBody.length) JCCaptureData(req.HTTPBody, @"outgoing-nsurlconnection", req.URL.absoluteString ?: @"", NO);
    void (^wrapped)(NSURLResponse *, NSData *, NSError *) = ^(NSURLResponse *resp, NSData *data, NSError *err) {
        if (data.length) JCCaptureData(data, @"network-nsurlconnection-async", resp.URL.absoluteString ?: req.URL.absoluteString ?: @"", NO);
        if (completion) completion(resp, data, err);
    };
    ((JCAsyncRequestFn)gAsyncRequestIMP)(self, _cmd, req, queue, wrapped);
}

#pragma mark - Optional IL2CPP decrypt hooks

static NSString *JCNSStringFromIl2Cpp(void *ptr) {
    if (!ptr) return nil;
    JCIl2CppString *s = (JCIl2CppString *)ptr;
    int32_t len = s->length;
    if (len <= 0 || len > (256 * 1024 * 1024)) return nil;
    @try {
        return [[[NSString alloc] initWithCharacters:(const unichar *)s->chars length:(NSUInteger)len] autorelease];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void *JCHookDecryptString(void *data, const void *method) {
    void *ret = gOrigDecryptString ? gOrigDecryptString(data, method) : NULL;
    if (ret && !gInsideInternal) {
        NSString *text = JCNSStringFromIl2Cpp(ret);
        if (text.length) JCCaptureString(text, @"decrypt-custom-string", @"AesHelper.CustomDecryptString", NO);
    }
    return ret;
}

static void *JCHookDecryptBytes(void *data, const void *method) {
    void *ret = gOrigDecryptBytes ? gOrigDecryptBytes(data, method) : NULL;
    if (ret && !gInsideInternal) {
        NSString *text = JCNSStringFromIl2Cpp(ret);
        if (text.length) JCCaptureString(text, @"decrypt-custom-bytes", @"AesHelper.CustomDecryptBytes", NO);
    }
    return ret;
}

static void *JCResolveHookSymbol(const char *symbol) {
    void *p = dlsym(RTLD_DEFAULT, symbol);
    if (p) return p;
    const char *libs[] = {
        "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/var/jb/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
        "/usr/lib/libsubstrate.dylib",
        "/var/jb/usr/lib/libsubstrate.dylib",
        "/usr/lib/libhooker.dylib",
        "/var/jb/usr/lib/libhooker.dylib",
        "/usr/lib/libellekit.dylib",
        "/var/jb/usr/lib/libellekit.dylib"
    };
    for (size_t i = 0; i < sizeof(libs) / sizeof(libs[0]); i++) {
        void *h = dlopen(libs[i], RTLD_LAZY | RTLD_GLOBAL);
        if (!h) continue;
        p = dlsym(h, symbol);
        if (p) return p;
    }
    return NULL;
}

static BOOL JCHookAddress(void *address, void *replacement, void **original) {
    JCMSHookFunctionFn ms = (JCMSHookFunctionFn)JCResolveHookSymbol("MSHookFunction");
    if (ms) {
        ms(address, replacement, original);
        if (original && *original) {
            if (!gDecryptHookAPI) gDecryptHookAPI = [@"MSHookFunction" retain];
            return YES;
        }
    }
    JCDobbyHookFn dobby = (JCDobbyHookFn)JCResolveHookSymbol("DobbyHook");
    if (dobby) {
        int rc = dobby(address, replacement, original);
        if (rc == 0 && original && *original) {
            if (!gDecryptHookAPI) gDecryptHookAPI = [@"DobbyHook" retain];
            return YES;
        }
    }
    return NO;
}

static uintptr_t JCUnityFrameworkBase(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework.framework/UnityFramework")) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

static void JCInstallDecryptHooks(uintptr_t base) {
    if (!base || gDecryptHookInstalled) return;
    BOOL ok1 = JCHookAddress((void *)(base + RVA_CUSTOM_DECRYPT_STRING), (void *)JCHookDecryptString, (void **)&gOrigDecryptString);
    BOOL ok2 = JCHookAddress((void *)(base + RVA_CUSTOM_DECRYPT_BYTES), (void *)JCHookDecryptBytes, (void **)&gOrigDecryptBytes);
    gDecryptHookInstalled = ok1 || ok2;
    JCPushEvent([NSString stringWithFormat:@"DECRYPT-HOOK base=0x%llx string=%d bytes=%d api=%@",
                 (unsigned long long)base, ok1, ok2, gDecryptHookAPI ?: @"none"]);
}

static void JCPollDecryptHook(NSUInteger attempt) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (gDecryptHookInstalled) return;
        uintptr_t base = JCUnityFrameworkBase();
        if (base) JCInstallDecryptHooks(base);
        if (!gDecryptHookInstalled && attempt < 120) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ JCPollDecryptHook(attempt + 1); });
        } else if (!gDecryptHookInstalled) {
            JCPushEvent(@"DECRYPT-HOOK unavailable/timeout; Foundation capture remains active");
        }
    });
}

#pragma mark - Hook install

static BOOL JCInstallOneInstance(Class cls, SEL sel, IMP hook, IMP *originalOut) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    IMP old = method_setImplementation(m, hook);
    if (originalOut) *originalOut = old;
    return old != NULL;
}

static BOOL JCInstallOneClass(Class cls, SEL sel, IMP hook, IMP *originalOut) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) return NO;
    IMP old = method_setImplementation(m, hook);
    if (originalOut) *originalOut = old;
    return old != NULL;
}

static void JCInstallHooks(void) {
    if (gHooksInstalled) return;
    NSUInteger installed = 0;
    installed += JCInstallOneClass([NSJSONSerialization class], @selector(JSONObjectWithData:options:error:), (IMP)JCHookJSONObjectWithData, &gJSONObjDataIMP);
    installed += JCInstallOneClass([NSJSONSerialization class], @selector(dataWithJSONObject:options:error:), (IMP)JCHookDataWithJSONObject, &gJSONDataObjIMP);

    installed += JCInstallOneClass([NSData class], @selector(dataWithContentsOfFile:), (IMP)JCHookNSDataFile, &gNSDataFileIMP);
    installed += JCInstallOneClass([NSData class], @selector(dataWithContentsOfFile:options:error:), (IMP)JCHookNSDataFileOptions, &gNSDataFileOptionsIMP);
    installed += JCInstallOneClass([NSData class], @selector(dataWithContentsOfURL:), (IMP)JCHookNSDataURL, &gNSDataURLIMP);
    installed += JCInstallOneClass([NSData class], @selector(dataWithContentsOfURL:options:error:), (IMP)JCHookNSDataURLOptions, &gNSDataURLOptionsIMP);

    installed += JCInstallOneClass([NSString class], @selector(stringWithContentsOfFile:encoding:error:), (IMP)JCHookNSStringFileEnc, &gNSStringFileEncIMP);
    installed += JCInstallOneClass([NSString class], @selector(stringWithContentsOfFile:usedEncoding:error:), (IMP)JCHookNSStringFileUsedEnc, &gNSStringFileUsedEncIMP);
    installed += JCInstallOneClass([NSString class], @selector(stringWithContentsOfURL:encoding:error:), (IMP)JCHookNSStringURLEnc, &gNSStringURLEncIMP);
    installed += JCInstallOneClass([NSString class], @selector(stringWithContentsOfURL:usedEncoding:error:), (IMP)JCHookNSStringURLUsedEnc, &gNSStringURLUsedEncIMP);

    installed += JCInstallOneInstance([NSURLSession class], @selector(dataTaskWithRequest:), (IMP)JCHookDataTaskReq, &gDataTaskReqIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(dataTaskWithRequest:completionHandler:), (IMP)JCHookDataTaskReqCompletion, &gDataTaskReqCompletionIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(dataTaskWithURL:), (IMP)JCHookDataTaskURL, &gDataTaskURLIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(dataTaskWithURL:completionHandler:), (IMP)JCHookDataTaskURLCompletion, &gDataTaskURLCompletionIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(uploadTaskWithRequest:fromData:), (IMP)JCHookUploadReqData, &gUploadReqDataIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(uploadTaskWithRequest:fromData:completionHandler:), (IMP)JCHookUploadReqDataCompletion, &gUploadReqDataCompletionIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(downloadTaskWithRequest:), (IMP)JCHookDownloadReq, &gDownloadReqIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(downloadTaskWithRequest:completionHandler:), (IMP)JCHookDownloadReqCompletion, &gDownloadReqCompletionIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(downloadTaskWithURL:), (IMP)JCHookDownloadURL, &gDownloadURLIMP);
    installed += JCInstallOneInstance([NSURLSession class], @selector(downloadTaskWithURL:completionHandler:), (IMP)JCHookDownloadURLCompletion, &gDownloadURLCompletionIMP);

    installed += JCInstallOneClass([NSURLConnection class], @selector(sendSynchronousRequest:returningResponse:error:), (IMP)JCHookSyncRequest, &gSyncRequestIMP);
    installed += JCInstallOneClass([NSURLConnection class], @selector(sendAsynchronousRequest:queue:completionHandler:), (IMP)JCHookAsyncRequest, &gAsyncRequestIMP);

    gHooksInstalled = installed > 0;
    JCPushEvent([NSString stringWithFormat:@"HOOKS installed=%lu Foundation/NSURLSession capture active", (unsigned long)installed]);
}

#pragma mark - UI

static void JCRefreshUI(void) {
    if (!gStatusLabel || !gTextView) return;
    gStatusLabel.text = [NSString stringWithFormat:@"%@  %@\nCaptured=%llu  Dup=%llu  Rejected=%llu\nNET=%llu PARSER=%llu FILE=%llu DEC=%llu",
                         JC_VERSION, gCaptureEnabled ? @"ACTIVE" : @"PAUSED",
                         gCaptured, gDuplicates, gRejected,
                         gNetworkCaptured, gParserCaptured, gFileCaptured, gDecryptCaptured];
    [gToggleButton setTitle:(gCaptureEnabled ? @"Pause" : @"Resume") forState:UIControlStateNormal];
    NSString *text = [gEvents componentsJoinedByString:@"\n"];
    gTextView.text = text;
    if (text.length) [gTextView scrollRangeToVisible:NSMakeRange(text.length, 0)];
}

@interface JSONCaptureTarget : NSObject
+ (instancetype)shared;
- (void)tick:(NSTimer *)timer;
- (void)tap:(id)sender;
- (void)toggle:(id)sender;
- (void)clear:(id)sender;
- (void)panButton:(UIPanGestureRecognizer *)g;
- (void)panPanel:(UIPanGestureRecognizer *)g;
@end

@implementation JSONCaptureTarget
+ (instancetype)shared {
    static JSONCaptureTarget *s;
    if (!s) s = [[self alloc] init];
    return s;
}

- (UIWindow *)currentWindow {
    UIApplication *app = [UIApplication sharedApplication];
    return app.keyWindow ?: app.windows.lastObject;
}

- (void)makeUI:(UIWindow *)w {
    if (gUIReady || !w) return;
    gWindow = w;

    gFloatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gFloatButton.frame = CGRectMake(18, 285, 58, 52);
    gFloatButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    gFloatButton.layer.cornerRadius = 26;
    gFloatButton.layer.borderWidth = 1.0;
    gFloatButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    [gFloatButton setTitle:@"JSON" forState:UIControlStateNormal];
    gFloatButton.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [gFloatButton addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *bp = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panButton:)] autorelease];
    [gFloatButton addGestureRecognizer:bp];
    [w addSubview:gFloatButton];

    gPanel = [[[UIView alloc] initWithFrame:CGRectMake(48, 78, 366, 450)] autorelease];
    gPanel.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.97];
    gPanel.layer.cornerRadius = 14;
    UIPanGestureRecognizer *pp = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)] autorelease];
    pp.cancelsTouchesInView = NO;
    [gPanel addGestureRecognizer:pp];

    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(12, 8, 342, 24)] autorelease];
    title.text = @"JSON Capture v0.1 · Runtime Collector";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:15];
    [gPanel addSubview:title];

    gStatusLabel = [[[UILabel alloc] initWithFrame:CGRectMake(12, 36, 342, 62)] autorelease];
    gStatusLabel.numberOfLines = 3;
    gStatusLabel.textColor = [UIColor colorWithWhite:0.86 alpha:1];
    gStatusLabel.font = [UIFont systemFontOfSize:10.5];
    [gPanel addSubview:gStatusLabel];

    gToggleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    gToggleButton.frame = CGRectMake(12, 102, 92, 34);
    gToggleButton.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    gToggleButton.layer.cornerRadius = 7;
    [gToggleButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [gToggleButton addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:gToggleButton];

    UIButton *clear = [UIButton buttonWithType:UIButtonTypeSystem];
    clear.frame = CGRectMake(112, 102, 92, 34);
    clear.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    clear.layer.cornerRadius = 7;
    [clear setTitle:@"Clear" forState:UIControlStateNormal];
    [clear setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [clear addTarget:self action:@selector(clear:) forControlEvents:UIControlEventTouchUpInside];
    [gPanel addSubview:clear];

    UILabel *path = [[[UILabel alloc] initWithFrame:CGRectMake(12, 140, 342, 34)] autorelease];
    path.numberOfLines = 2;
    path.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    path.font = [UIFont systemFontOfSize:9.5];
    path.text = @"Output: Documents/JSONCapture/\nnetwork · parser · file · decrypt · outgoing";
    [gPanel addSubview:path];

    gTextView = [[[UITextView alloc] initWithFrame:CGRectMake(10, 178, 346, 262)] autorelease];
    gTextView.backgroundColor = [UIColor colorWithWhite:0.01 alpha:1];
    gTextView.textColor = [UIColor colorWithWhite:0.92 alpha:1];
    gTextView.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightRegular];
    gTextView.editable = NO;
    gTextView.selectable = YES;
    [gPanel addSubview:gTextView];

    gPanel.hidden = YES;
    [w addSubview:gPanel];
    gUIReady = YES;
    JCRefreshUI();
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    UIWindow *w = [self currentWindow];
    if (!w) return;
    if (!gUIReady) [self makeUI:w];
    if (gUIReady && gWindow != w) {
        [w addSubview:gPanel];
        [w addSubview:gFloatButton];
        gWindow = w;
    }
    if (gUIReady) {
        [w bringSubviewToFront:gPanel];
        [w bringSubviewToFront:gFloatButton];
    }
}

- (void)tap:(id)sender {
    (void)sender;
    gPanel.hidden = !gPanel.hidden;
    JCRefreshUI();
}

- (void)toggle:(id)sender {
    (void)sender;
    gCaptureEnabled = !gCaptureEnabled;
    JCPushEvent(gCaptureEnabled ? @"CAPTURE resumed" : @"CAPTURE paused");
    JCRefreshUI();
}

- (void)clear:(id)sender {
    (void)sender;
    dispatch_async(gCaptureQueue, ^{
        @autoreleasepool {
            gInsideInternal++;
            [[NSFileManager defaultManager] removeItemAtPath:gRootPath error:nil];
            JCSetupPaths();
            [gSeenHashes removeAllObjects];
            gInsideInternal--;
            gCaptured = gDuplicates = gRejected = 0;
            gNetworkCaptured = gParserCaptured = gFileCaptured = gDecryptCaptured = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                [gEvents removeAllObjects];
                JCPushEvent(@"CAPTURE storage cleared");
                JCRefreshUI();
            });
        }
    });
}

- (void)panButton:(UIPanGestureRecognizer *)g {
    if (!gWindow) return;
    CGPoint tr = [g translationInView:gWindow];
    CGPoint c = gFloatButton.center;
    c.x += tr.x; c.y += tr.y;
    CGRect b = gWindow.bounds;
    c.x = MAX(29, MIN(b.size.width - 29, c.x));
    c.y = MAX(26, MIN(b.size.height - 26, c.y));
    gFloatButton.center = c;
    [g setTranslation:CGPointZero inView:gWindow];
}

- (void)panPanel:(UIPanGestureRecognizer *)g {
    if (!gWindow) return;
    CGPoint tr = [g translationInView:gWindow];
    CGPoint c = gPanel.center;
    c.x += tr.x; c.y += tr.y;
    gPanel.center = c;
    [g setTranslation:CGPointZero inView:gWindow];
}
@end

__attribute__((constructor)) static void JSONCaptureInit(void) {
    @autoreleasepool {
        gCaptureQueue = dispatch_queue_create("com.hfamap.jsoncapture.capture", DISPATCH_QUEUE_SERIAL);
        gSeenHashes = [[NSMutableSet alloc] init];
        gEvents = [[NSMutableArray alloc] init];
        gTaskStates = [[NSMutableDictionary alloc] init];
        JCSetupPaths();
        JCAppendLog([NSString stringWithFormat:@"[%@] %@ loaded root=%@", JCNowText(), JC_VERSION, gRootPath]);

        dispatch_async(dispatch_get_main_queue(), ^{
            JCInstallHooks();
            [[JSONCaptureTarget shared] tick:nil];
            [NSTimer scheduledTimerWithTimeInterval:0.5 target:[JSONCaptureTarget shared] selector:@selector(tick:) userInfo:nil repeats:YES];
        });
        JCPollDecryptHook(0);
    }
}
