#import <Foundation/Foundation.h>
#import "../include/ZonoeAuthAdapter.h"
#import <os/lock.h>

static NSString * const kAuthURL = @"http://43.242.203.214/auth/login";
static os_unfair_lock gLogLock = OS_UNFAIR_LOCK_INIT;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase2_T3.log"];
}

static void ZLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    os_unfair_lock_lock(&gLogLock);
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    if (!h) {
        [[NSFileManager defaultManager] createFileAtPath:LogPath() contents:nil attributes:nil];
        h = [NSFileHandle fileHandleForWritingAtPath:LogPath()];
    }
    [h seekToEndOfFile];
    [h writeData:data];
    [h closeFile];
    os_unfair_lock_unlock(&gLogLock);
}

static void Finish(ZonoeAuthCompletion completion, BOOL ok, NSString *message, NSDictionary *info) {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(ok, message ?: @"UNKNOWN", info);
    });
}

void ZonoeAuthLogin(NSString *username,
                    NSString *password,
                    ZonoeAuthCompletion completion) {
    if (![username isKindOfClass:NSString.class] ||
        ![password isKindOfClass:NSString.class] ||
        username.length == 0 ||
        password.length == 0) {
        Finish(completion, NO, @"ACCOUNT_OR_PASSWORD_EMPTY", nil);
        return;
    }

    if (username.length > 64 || password.length > 64) {
        Finish(completion, NO, @"ACCOUNT_OR_PASSWORD_INVALID", nil);
        return;
    }

    NSURL *url = [NSURL URLWithString:kAuthURL];
    if (!url) {
        Finish(completion, NO, @"BAD_AUTH_URL", nil);
        return;
    }

    NSDictionary *payload = @{
        @"username": username,
        @"password": password
    };

    NSError *jsonError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&jsonError];
    if (!body || jsonError) {
        Finish(completion, NO, @"REQUEST_ENCODE_FAILED", nil);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                   timeoutInterval:8.0];
    req.HTTPMethod = @"POST";
    req.HTTPBody = body;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    ZLog(@"[T3] auth request userLen=%lu passLen=%lu",
         (unsigned long)username.length,
         (unsigned long)password.length);

    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            ZLog(@"[T3] network error domain=%@ code=%ld", error.domain, (long)error.code);
            Finish(completion, NO, @"NETWORK_ERROR", nil);
            return;
        }

        NSInteger status = 0;
        if ([response isKindOfClass:NSHTTPURLResponse.class]) {
            status = ((NSHTTPURLResponse *)response).statusCode;
        }

        NSError *parseError = nil;
        id obj = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError] : nil;
        if (![obj isKindOfClass:NSDictionary.class] || parseError) {
            ZLog(@"[T3] bad response status=%ld bytes=%lu", (long)status, (unsigned long)data.length);
            Finish(completion, NO, @"BAD_RESPONSE", nil);
            return;
        }

        NSDictionary *json = (NSDictionary *)obj;
        BOOL ok = [[json objectForKey:@"ok"] boolValue];
        NSString *message = [[json objectForKey:@"message"] isKindOfClass:NSString.class]
            ? [json objectForKey:@"message"]
            : @"BAD_RESPONSE";

        NSMutableDictionary *info = [json mutableCopy];
        [info removeObjectForKey:@"ok"];
        [info removeObjectForKey:@"message"];

        ZLog(@"[T3] auth response status=%ld ok=%d msg=%@", (long)status, ok, message);
        Finish(completion, ok, message, info.count ? info : nil);
    }];
}

__attribute__((constructor)) static void ZonoeAuthAdapterEntry(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase2 T3 Explicit Auth Adapter loaded ===");
        ZLog(@"[NOTE] adapter is called explicitly by the test project; no SDK request interception is installed");
    }
}
