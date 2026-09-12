#import "ZNStaticBinaryBuilder.h"
#import "ZNAdhocMachOSigner.h"
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

// V3 performs its builder swizzle in +load. This bridge deliberately installs
// one main-queue turn later, so it wraps the final builder implementation rather
// than competing with the V3 category's +load order.
@implementation ZNStaticBinaryBuilder (ZNGeneratedBinarySigningBridge)

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            Method active = class_getClassMethod(self, @selector(buildWorkspace:outputs:report:error:));
            Method wrapper = class_getClassMethod(self, @selector(znsigned_buildWorkspace:outputs:report:error:));
            if (active && wrapper) method_exchangeImplementations(active, wrapper);
        });
    });
}

+ (BOOL)znsigned_buildWorkspace:(ZNBinaryPatchWorkspace *)workspace
                        outputs:(NSArray<NSString *> **)outputs
                         report:(NSString **)report
                          error:(NSString **)error {
    NSArray<NSString *> *innerOutputs = nil;
    NSString *innerReport = nil;
    NSString *innerError = nil;

    // After our exchange this selector points at the builder implementation
    // that was active before the bridge (V3 on the current branch).
    BOOL ok = [self znsigned_buildWorkspace:workspace
                                    outputs:&innerOutputs
                                     report:&innerReport
                                      error:&innerError];
    if (!ok) {
        if (error) *error = innerError ?: @"Static Binary Builder 生成失败";
        return NO;
    }

    NSMutableArray<NSDictionary *> *signing = [NSMutableArray array];
    NSString *failure = nil;
    NSString *folder = nil;
    for (NSString *path in innerOutputs) {
        if (![path.pathExtension.lowercaseString isEqualToString:@"znpatched"]) continue;
        if (!folder.length) folder = path.stringByDeletingLastPathComponent;

        NSDictionary *signMetadata = nil;
        NSString *signError = nil;
        if (!ZNAdhocResignMachOAtPath(path, &signMetadata, &signError)) {
            failure = [NSString stringWithFormat:@"%@：%@", path.lastPathComponent, signError ?: @"ad-hoc CodeDirectory 重建失败"];
            break;
        }
        NSMutableDictionary *item = [signMetadata mutableCopy] ?: [NSMutableDictionary dictionary];
        item[@"output"] = path;
        [signing addObject:item];
    }

    if (failure) {
        if (folder.length) [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
        if (error) *error = [NSString stringWithFormat:@"生成后二进制签名自检失败：%@", failure];
        return NO;
    }

    // Add machine-readable post-process evidence without changing V3's core
    // report schema. The package still needs its normal final IPA re-sign.
    for (NSString *path in innerOutputs) {
        if (![path.lastPathComponent isEqualToString:@"build_report.json"]) continue;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) continue;
        NSMutableDictionary *object = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy];
        if (![object isKindOfClass:NSMutableDictionary.class]) continue;
        object[@"generatedBinarySignature"] = @{
            @"mode": @"zonoe-self-contained-adhoc",
            @"rebuiltBeforeExport": @YES,
            @"pageHashesVerified": @YES,
            @"outputs": signing,
            @"finalPackageResignRequired": @YES,
        };
        NSData *updated = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
        if (updated) [updated writeToFile:path atomically:YES];
        break;
    }

    if (outputs) *outputs = innerOutputs;
    if (report) {
        *report = [NSString stringWithFormat:@"%@\n已重建生成 Mach-O 的 SHA-1/SHA-256 CodeDirectory 并逐页校验；替换回 IPA 后仍需正常整包重签。",
                   innerReport ?: @"Static Binary Builder 生成成功"];
    }
    return YES;
}

@end
