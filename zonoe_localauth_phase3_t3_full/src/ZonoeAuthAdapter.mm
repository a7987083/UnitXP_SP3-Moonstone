#import <Foundation/Foundation.h>
#import "../include/ZonoeAuthAdapter.h"
#import <os/lock.h>

static NSString * const kLoginURL = @"http://43.242.203.214/auth/login";
static NSString * const kRegisterURL = @"http://43.242.203.214/auth/register";
static NSString * const kChangePasswordURL = @"http://43.242.203.214/auth/change_password";
static os_unfair_lock gLogLock = OS_UNFAIR_LOCK_INIT;

static NSString *LogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"ZonoeLocalAuth_Phase3_T3_Full.log"];
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

static BOOL ValidString(NSString *s) {
    return [s isKindOfClass:NSString.class] && s.length > 0 && s.length <= 64;
}

static void SendJSON(NSString *urlString,
                     NSDictionary *payload,
                     NSString *tag,
                     ZonoeAuthCompletion completion) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        Finish(completion, NO, @"BAD_AUTH_URL", nil);
        return;
    }

    NSError *encodeError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&encodeError];
    if (!body || encodeError) {
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

    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            ZLog(@"[%@] network error domain=%@ code=%ld", tag, error.domain, (long)error.code);
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
            ZLog(@"[%@] bad response status=%ld bytes=%lu", tag, (long)status, (unsigned long)data.length);
            Finish(completion, NO, @"BAD_RESPONSE", nil);
            return;
        }

        NSDictionary *json = (NSDictionary *)obj;
        BOOL ok = [[json objectForKey:@"ok"] boolValue];
        NSString *message = [[json objectForKey:@"message"] isKindOfClass:NSString.class]
            ? [json objectForKey:@"message"] : @"BAD_RESPONSE";
        NSMutableDictionary *info = [json mutableCopy];
        [info removeObjectForKey:@"ok"];
        [info removeObjectForKey:@"message"];
        ZLog(@"[%@] response status=%ld ok=%d msg=%@", tag, (long)status, ok, message);
        Finish(completion, ok, message, info.count ? info : nil);
    }];
}

void ZonoeAuthLogin(NSString *username, NSString *password, ZonoeAuthCompletion completion) {
    if (!ValidString(username) || !ValidString(password)) {
        Finish(completion, NO, @"ACCOUNT_OR_PASSWORD_INVALID", nil);
        return;
    }
    ZLog(@"[LOGIN] request userLen=%lu passLen=%lu", (unsigned long)username.length, (unsigned long)password.length);
    SendJSON(kLoginURL, @{@"username":username, @"password":password}, @"LOGIN", completion);
}

void ZonoeAuthRegister(NSString *username, NSString *password, NSString *channel, ZonoeAuthCompletion completion) {
    if (!ValidString(username) || !ValidString(password)) {
        Finish(completion, NO, @"ACCOUNT_OR_PASSWORD_INVALID", nil);
        return;
    }
    NSMutableDictionary *payload = [@{@"username":username, @"password":password} mutableCopy];
    if ([channel isKindOfClass:NSString.class] && channel.length > 0 && channel.length <= 64) {
        payload[@"channel"] = channel;
    }
    ZLog(@"[REGISTER] request userLen=%lu passLen=%lu channelLen=%lu", (unsigned long)username.length, (unsigned long)password.length, (unsigned long)channel.length);
    SendJSON(kRegisterURL, payload, @"REGISTER", completion);
}

void ZonoeAuthChangePassword(NSString *username,
                             NSString *oldPassword,
                             NSString *newPassword,
                             ZonoeAuthCompletion completion) {
    if (!ValidString(username) || !ValidString(oldPassword) || !ValidString(newPassword)) {
        Finish(completion, NO, @"ACCOUNT_OR_PASSWORD_INVALID", nil);
        return;
    }
    ZLog(@"[CHANGE_PASSWORD] request userLen=%lu oldLen=%lu newLen=%lu",
         (unsigned long)username.length,
         (unsigned long)oldPassword.length,
         (unsigned long)newPassword.length);
    SendJSON(kChangePasswordURL,
             @{@"username":username, @"old_password":oldPassword, @"new_password":newPassword},
             @"CHANGE_PASSWORD",
             completion);
}

__attribute__((constructor)) static void ZonoeAuthAdapterEntry(void) {
    @autoreleasepool {
        ZLog(@"=== ZonoeLocalAuth Phase3 T3 Full Adapter loaded ===");
        ZLog(@"[NOTE] explicit project calls: login/register/change_password; credentials are never written to logs");
    }
}
