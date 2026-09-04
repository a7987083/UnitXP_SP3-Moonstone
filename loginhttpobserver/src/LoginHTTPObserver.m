#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static UIWindow *gWindow;
static UIButton *gFloatButton;
static UIView *gPanel;
static UITextView *gTextView;
static UILabel *gStatusLabel;
static NSMutableArray *gEvents;
static NSString *gLogPath;
static BOOL gUIReady = NO;
static BOOL gHooksInstalled = NO;
static NSInteger gHookDelayTicks = 0;
static unsigned long long gSeq = 0;

static IMP gDataTaskReqIMP;
static IMP gDataTaskReqCompletionIMP;
static IMP gDataTaskURLIMP;
static IMP gDataTaskURLCompletionIMP;
static IMP gUploadReqDataIMP;
static IMP gUploadReqDataCompletionIMP;
static IMP gMutableSetURLIMP;
static IMP gSyncRequestIMP;
static IMP gAsyncRequestIMP;

static NSString *NowText(void) {
    NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
    fmt.dateFormat = @"HH:mm:ss.SSS";
    return [fmt stringFromDate:[NSDate date]];
}

static NSString *DataPreview(NSData *data, NSUInteger limit) {
    if (!data || data.length == 0) return @"";
    NSUInteger n = MIN(data.length, limit);
    NSData *slice = [data subdataWithRange:NSMakeRange(0, n)];
    NSString *utf8 = [[[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding] autorelease];
    if (utf8) {
        NSString *s = [utf8 stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
        s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        if (data.length > n) s = [s stringByAppendingFormat:@" ... <truncated %lu/%lu>", (unsigned long)n, (unsigned long)data.length];
        return s;
    }
    const unsigned char *p = slice.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:n * 2];
    for (NSUInteger i = 0; i < n; i++) [hex appendFormat:@"%02x", p[i]];
    if (data.length > n) [hex appendFormat:@"...<truncated %lu/%lu>", (unsigned long)n, (unsigned long)data.length];
    return [NSString stringWithFormat:@"<binary hex=%@>", hex];
}

static void AppendFile(NSString *line) {
    if (!gLogPath || !line) return;
    @synchronized([NSFileHandle class]) {
        FILE *f = fopen(gLogPath.fileSystemRepresentation, "a");
        if (!f) return;
        NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(d.bytes, 1, d.length, f);
        fflush(f);
        fclose(f);
    }
}

static void RefreshUI(void) {
    if (!gTextView || !gStatusLabel) return;
    NSString *text = [gEvents componentsJoinedByString:@"\n"];
    gTextView.text = text;
    NSRange r = NSMakeRange(text.length, 0);
    if (text.length) [gTextView scrollRangeToVisible:r];
    gStatusLabel.text = [NSString stringWithFormat:@"HTTP observer: %@   events=%llu\nLog: Documents/LoginHTTPTrace.log",
                         gHooksInstalled ? @"ACTIVE" : @"WAITING", gSeq];
}

static void PushEvent(NSString *summary, NSString *detail) {
    if (!summary) return;
    unsigned long long seq = ++gSeq;
    NSString *line = [NSString stringWithFormat:@"[%@] #%llu %@", NowText(), seq, summary];
    AppendFile(line);
    if (detail.length) AppendFile([NSString stringWithFormat:@"    %@", detail]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!gEvents) gEvents = [[NSMutableArray alloc] init];
        [gEvents addObject:line];
        if (gEvents.count > 24) [gEvents removeObjectAtIndex:0];
        RefreshUI();
    });
}

static NSString *RequestDetail(NSURLRequest *req) {
    if (!req) return @"request=(null)";
    NSMutableString *s = [NSMutableString string];
    NSDictionary *headers = req.allHTTPHeaderFields;
    if (headers.count) [s appendFormat:@"headers=%@", headers];
    NSData *body = req.HTTPBody;
    if (body.length) {
        if (s.length) [s appendString:@" | "];
        [s appendFormat:@"body=%@", DataPreview(body, 2048)];
    }
    return s;
}

static void LogRequest(NSURLRequest *req, NSString *source) {
    if (!req) return;
    NSString *method = req.HTTPMethod.length ? req.HTTPMethod : @"GET";
    NSString *url = req.URL.absoluteString ?: @"(null-url)";
    NSString *tag = [url containsString:@"118.145.146.208"] ? @" TARGET" : @"";
    PushEvent([NSString stringWithFormat:@"REQ%@ %@ %@ [%@]", tag, method, url, source ?: @"?"], RequestDetail(req));
}

static void LogURL(NSURL *url, NSString *source) {
    if (!url) return;
    NSString *u = url.absoluteString ?: @"(null-url)";
    NSString *tag = [u containsString:@"118.145.146.208"] ? @" TARGET" : @"";
    PushEvent([NSString stringWithFormat:@"URL%@ %@ [%@]", tag, u, source ?: @"?"], @"");
}

static void LogResponse(NSURLResponse *resp, NSData *data, NSError *err, NSString *source) {
    NSInteger status = 0;
    if ([resp isKindOfClass:[NSHTTPURLResponse class]]) status = [(NSHTTPURLResponse *)resp statusCode];
    NSString *url = resp.URL.absoluteString ?: @"(null-url)";
    NSString *tag = [url containsString:@"118.145.146.208"] ? @" TARGET" : @"";
    NSMutableString *detail = [NSMutableString string];
    if (err) [detail appendFormat:@"error=%@", err];
    if (data.length) {
        if (detail.length) [detail appendString:@" | "];
        [detail appendFormat:@"response=%@", DataPreview(data, 4096)];
    }
    PushEvent([NSString stringWithFormat:@"RESP%@ status=%ld %@ [%@]", tag, (long)status, url, source ?: @"?"], detail);
}

typedef NSURLSessionDataTask *(*DataTaskReqFn)(id, SEL, NSURLRequest *);
typedef NSURLSessionDataTask *(*DataTaskReqCompletionFn)(id, SEL, NSURLRequest *, void (^)(NSData *, NSURLResponse *, NSError *));
typedef NSURLSessionDataTask *(*DataTaskURLFn)(id, SEL, NSURL *);
typedef NSURLSessionDataTask *(*DataTaskURLCompletionFn)(id, SEL, NSURL *, void (^)(NSData *, NSURLResponse *, NSError *));
typedef NSURLSessionUploadTask *(*UploadReqDataFn)(id, SEL, NSURLRequest *, NSData *);
typedef NSURLSessionUploadTask *(*UploadReqDataCompletionFn)(id, SEL, NSURLRequest *, NSData *, void (^)(NSData *, NSURLResponse *, NSError *));
typedef void (*SetURLFn)(id, SEL, NSURL *);
typedef NSData *(*SyncRequestFn)(id, SEL, NSURLRequest *, NSURLResponse **, NSError **);
typedef void (*AsyncRequestFn)(id, SEL, NSURLRequest *, NSOperationQueue *, void (^)(NSURLResponse *, NSData *, NSError *));

static NSURLSessionDataTask *HookDataTaskWithRequest(id self, SEL _cmd, NSURLRequest *req) {
    LogRequest(req, @"NSURLSession dataTaskWithRequest");
    return ((DataTaskReqFn)gDataTaskReqIMP)(self, _cmd, req);
}

static NSURLSessionDataTask *HookDataTaskWithRequestCompletion(id self, SEL _cmd, NSURLRequest *req,
                                                               void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    LogRequest(req, @"NSURLSession dataTaskWithRequest:completion");
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        LogResponse(resp, data, err, @"NSURLSession completion");
        if (completion) completion(data, resp, err);
    };
    return ((DataTaskReqCompletionFn)gDataTaskReqCompletionIMP)(self, _cmd, req, wrapped);
}

static NSURLSessionDataTask *HookDataTaskWithURL(id self, SEL _cmd, NSURL *url) {
    LogURL(url, @"NSURLSession dataTaskWithURL");
    return ((DataTaskURLFn)gDataTaskURLIMP)(self, _cmd, url);
}

static NSURLSessionDataTask *HookDataTaskWithURLCompletion(id self, SEL _cmd, NSURL *url,
                                                           void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    LogURL(url, @"NSURLSession dataTaskWithURL:completion");
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        LogResponse(resp, data, err, @"NSURLSession URL completion");
        if (completion) completion(data, resp, err);
    };
    return ((DataTaskURLCompletionFn)gDataTaskURLCompletionIMP)(self, _cmd, url, wrapped);
}

static NSURLSessionUploadTask *HookUploadWithRequestData(id self, SEL _cmd, NSURLRequest *req, NSData *body) {
    LogRequest(req, @"NSURLSession uploadTaskWithRequest");
    if (body.length) PushEvent([NSString stringWithFormat:@"UPLOAD body-bytes=%lu", (unsigned long)body.length], DataPreview(body, 2048));
    return ((UploadReqDataFn)gUploadReqDataIMP)(self, _cmd, req, body);
}

static NSURLSessionUploadTask *HookUploadWithRequestDataCompletion(id self, SEL _cmd, NSURLRequest *req, NSData *body,
                                                                   void (^completion)(NSData *, NSURLResponse *, NSError *)) {
    LogRequest(req, @"NSURLSession uploadTaskWithRequest:completion");
    if (body.length) PushEvent([NSString stringWithFormat:@"UPLOAD body-bytes=%lu", (unsigned long)body.length], DataPreview(body, 2048));
    void (^wrapped)(NSData *, NSURLResponse *, NSError *) = ^(NSData *data, NSURLResponse *resp, NSError *err) {
        LogResponse(resp, data, err, @"NSURLSession upload completion");
        if (completion) completion(data, resp, err);
    };
    return ((UploadReqDataCompletionFn)gUploadReqDataCompletionIMP)(self, _cmd, req, body, wrapped);
}

static void HookMutableSetURL(id self, SEL _cmd, NSURL *url) {
    if (url.absoluteString.length && ([url.absoluteString containsString:@"118.145.146.208"] || [url.absoluteString containsString:@"/master/GM/"])) {
        LogURL(url, @"NSMutableURLRequest setURL");
    }
    ((SetURLFn)gMutableSetURLIMP)(self, _cmd, url);
}

static NSData *HookSyncRequest(id self, SEL _cmd, NSURLRequest *req, NSURLResponse **resp, NSError **err) {
    LogRequest(req, @"NSURLConnection sync");
    NSData *data = ((SyncRequestFn)gSyncRequestIMP)(self, _cmd, req, resp, err);
    LogResponse(resp ? *resp : nil, data, err ? *err : nil, @"NSURLConnection sync");
    return data;
}

static void HookAsyncRequest(id self, SEL _cmd, NSURLRequest *req, NSOperationQueue *queue,
                             void (^completion)(NSURLResponse *, NSData *, NSError *)) {
    LogRequest(req, @"NSURLConnection async");
    void (^wrapped)(NSURLResponse *, NSData *, NSError *) = ^(NSURLResponse *resp, NSData *data, NSError *err) {
        LogResponse(resp, data, err, @"NSURLConnection async");
        if (completion) completion(resp, data, err);
    };
    ((AsyncRequestFn)gAsyncRequestIMP)(self, _cmd, req, queue, wrapped);
}

static BOOL InstallOneInstance(Class cls, SEL sel, IMP hook, IMP *originalOut) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    IMP old = method_setImplementation(m, hook);
    if (originalOut) *originalOut = old;
    return old != NULL;
}

static BOOL InstallOneClass(Class cls, SEL sel, IMP hook, IMP *originalOut) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) return NO;
    IMP old = method_setImplementation(m, hook);
    if (originalOut) *originalOut = old;
    return old != NULL;
}

static void InstallHTTPHooks(void) {
    if (gHooksInstalled) return;
    NSUInteger installed = 0;
    installed += InstallOneInstance([NSURLSession class], @selector(dataTaskWithRequest:), (IMP)HookDataTaskWithRequest, &gDataTaskReqIMP);
    installed += InstallOneInstance([NSURLSession class], @selector(dataTaskWithRequest:completionHandler:), (IMP)HookDataTaskWithRequestCompletion, &gDataTaskReqCompletionIMP);
    installed += InstallOneInstance([NSURLSession class], @selector(dataTaskWithURL:), (IMP)HookDataTaskWithURL, &gDataTaskURLIMP);
    installed += InstallOneInstance([NSURLSession class], @selector(dataTaskWithURL:completionHandler:), (IMP)HookDataTaskWithURLCompletion, &gDataTaskURLCompletionIMP);
    installed += InstallOneInstance([NSURLSession class], @selector(uploadTaskWithRequest:fromData:), (IMP)HookUploadWithRequestData, &gUploadReqDataIMP);
    installed += InstallOneInstance([NSURLSession class], @selector(uploadTaskWithRequest:fromData:completionHandler:), (IMP)HookUploadWithRequestDataCompletion, &gUploadReqDataCompletionIMP);
    installed += InstallOneInstance([NSMutableURLRequest class], @selector(setURL:), (IMP)HookMutableSetURL, &gMutableSetURLIMP);
    installed += InstallOneClass([NSURLConnection class], @selector(sendSynchronousRequest:returningResponse:error:), (IMP)HookSyncRequest, &gSyncRequestIMP);
    installed += InstallOneClass([NSURLConnection class], @selector(sendAsynchronousRequest:queue:completionHandler:), (IMP)HookAsyncRequest, &gAsyncRequestIMP);
    gHooksInstalled = installed > 0;
    PushEvent([NSString stringWithFormat:@"HOOKS installed=%lu delayed-after-UI", (unsigned long)installed], @"No connect/getaddrinfo interpose. Read-only HTTP observation.");
}

@interface LoginHTTPObserverTarget : NSObject
+ (instancetype)shared;
- (void)tick:(NSTimer *)timer;
- (void)tap:(id)sender;
- (void)panButton:(UIPanGestureRecognizer *)g;
- (void)panPanel:(UIPanGestureRecognizer *)g;
@end

@implementation LoginHTTPObserverTarget
+ (instancetype)shared {
    static LoginHTTPObserverTarget *s;
    if (!s) s = [[self alloc] init];
    return s;
}

- (UIWindow *)currentWindow {
    UIApplication *app = [UIApplication sharedApplication];
    UIWindow *w = app.keyWindow;
    if (w) return w;
    return app.windows.lastObject;
}

- (void)makeUI:(UIWindow *)w {
    if (gUIReady || !w) return;
    gWindow = w;
    gEvents = [[NSMutableArray alloc] init];

    gFloatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    gFloatButton.frame = CGRectMake(18, 165, 58, 52);
    gFloatButton.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.94];
    gFloatButton.layer.cornerRadius = 26;
    [gFloatButton setTitle:@"HTTP" forState:UIControlStateNormal];
    gFloatButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [gFloatButton addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *bp = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panButton:)] autorelease];
    [gFloatButton addGestureRecognizer:bp];
    [w addSubview:gFloatButton];

    gPanel = [[[UIView alloc] initWithFrame:CGRectMake(52, 82, 360, 360)] autorelease];
    gPanel.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.97];
    gPanel.layer.cornerRadius = 14;
    UIPanGestureRecognizer *pp = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)] autorelease];
    pp.cancelsTouchesInView = NO;
    [gPanel addGestureRecognizer:pp];

    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(12, 8, 336, 44)] autorelease];
    title.textColor = [UIColor whiteColor];
    title.numberOfLines = 2;
    title.font = [UIFont boldSystemFontOfSize:16];
    title.text = @"Login HTTP Observer v5\nDelayed after HFAMap-style UI ready";
    [gPanel addSubview:title];

    gStatusLabel = [[[UILabel alloc] initWithFrame:CGRectMake(12, 54, 336, 42)] autorelease];
    gStatusLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    gStatusLabel.numberOfLines = 2;
    gStatusLabel.font = [UIFont systemFontOfSize:11];
    [gPanel addSubview:gStatusLabel];

    gTextView = [[[UITextView alloc] initWithFrame:CGRectMake(10, 100, 340, 250)] autorelease];
    gTextView.backgroundColor = [UIColor colorWithWhite:0.015 alpha:1];
    gTextView.textColor = [UIColor colorWithWhite:0.92 alpha:1];
    gTextView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    gTextView.editable = NO;
    gTextView.selectable = YES;
    [gPanel addSubview:gTextView];

    gPanel.hidden = YES;
    [w addSubview:gPanel];
    gUIReady = YES;
    gHookDelayTicks = 2;
    PushEvent(@"UI-READY; HTTP hooks will install after delay", @"");
    RefreshUI();
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
    if (gUIReady && !gHooksInstalled) {
        if (gHookDelayTicks > 0) gHookDelayTicks--;
        else InstallHTTPHooks();
    }
    if (gUIReady) {
        [w bringSubviewToFront:gPanel];
        [w bringSubviewToFront:gFloatButton];
    }
}

- (void)tap:(id)sender {
    (void)sender;
    gPanel.hidden = !gPanel.hidden;
    RefreshUI();
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

__attribute__((constructor)) static void LoginHTTPObserverInit(void) {
    @autoreleasepool {
        NSString *home = NSHomeDirectory();
        if (home.length) gLogPath = [[home stringByAppendingPathComponent:@"Documents/LoginHTTPTrace.log"] retain];
        AppendFile(@"\n[LoginHTTPObserver v5] loaded; waiting for UI before hooks");
        dispatch_async(dispatch_get_main_queue(), ^{
            LoginHTTPObserverTarget *t = [LoginHTTPObserverTarget shared];
            [NSTimer scheduledTimerWithTimeInterval:0.5 target:t selector:@selector(tick:) userInfo:nil repeats:YES];
        });
    }
}
