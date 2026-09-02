#import "HFAPatchLogger.h"

static dispatch_queue_t HFAPatchLogQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.hfa.patchmenu.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

NSString *HFAPatchSupportDirectory(void)
{
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                NSUserDomainMask,
                                                                YES).firstObject;
    if (documents.length == 0) {
        documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    }
    return [documents stringByAppendingPathComponent:@"HFAPatch"];
}

NSString *HFAPatchExternalConfigPath(void)
{
    return [HFAPatchSupportDirectory() stringByAppendingPathComponent:@"config.json"];
}

NSString *HFAPatchLogPath(void)
{
    return [HFAPatchSupportDirectory() stringByAppendingPathComponent:@"HFAPatchMenu.log"];
}

void HFAPatchLog(NSString *format, ...)
{
    if (format.length == 0) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    });

    NSString *line = [NSString stringWithFormat:@"[%@] %@\n",
                      [formatter stringFromDate:[NSDate date]], message];
    NSLog(@"[HFAPatchMenu] %@", message);

    dispatch_async(HFAPatchLogQueue(), ^{
        NSFileManager *manager = NSFileManager.defaultManager;
        NSString *directory = HFAPatchSupportDirectory();
        [manager createDirectoryAtPath:directory
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:nil];

        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path = HFAPatchLogPath();
        if (![manager fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
            return;
        }

        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    });
}
