#import "ZNStaticBinaryBuilder.h"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchRuntimeValidator.h"
#import "ZNPatchCore.h"
#import "ZNFeatureNameRegistry.h"
#import "ZNStaticMetadataPrivacy.h"
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

    // Keep a compatibility copy in the host registry for old generated outputs.
    // New ZNF1 outputs do not depend on this registry: their FeatureID + encoded
    // display name travels inside the generated Mach-O itself.
    NSMutableArray<NSDictionary *> *nameEntries = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *nextPatchIDByTarget = [NSMutableDictionary dictionary];
    for (ZNBinaryPatchRow *row in workspace.rows) {
        if (!row.offsetText.length && !row.enabledText.length) continue;
        if (!row.validated || !row.validator) continue;

        NSString *target = (row.explicitTarget && row.target.length) ? row.target : workspace.defaultTarget;
        if (!target.length) continue;
        uint32_t patchID = nextPatchIDByTarget[target].unsignedIntValue + 1u;
        nextPatchIDByTarget[target] = @(patchID);

        NSDictionary *module = [[ZNModuleManager sharedManager] moduleNamed:target];
        NSString *runtimeTarget = [module[@"path"] lastPathComponent];
        if (!runtimeTarget.length) runtimeTarget = target;

        [nameEntries addObject:@{
            @"target": target,
            @"runtimeTarget": runtimeTarget,
            @"siteRVA": @(row.validator.rva),
            @"patchID": @(patchID),
            @"title": row.title ?: @"",
            @"group": row.group ?: @"",
        }];
    }

    NSMutableArray<NSDictionary *> *signing = [NSMutableArray array];
    NSString *failure = nil;
    NSString *folder = nil;
    NSUInteger totalEncoded = 0;

    for (NSString *path in innerOutputs) {
        if (![path.pathExtension.lowercaseString isEqualToString:@"znpatched"]) continue;
        if (!folder.length) folder = path.stringByDeletingLastPathComponent;

        NSUInteger encoded = 0;
        NSString *privacyError = nil;
        if (!ZNScrubStaticDisplayMetadataAtPath(path, &encoded, &privacyError)) {
            failure = [NSString stringWithFormat:@"%@：%@", path.lastPathComponent,
                       privacyError ?: @"显示 metadata 编码失败"];
            break;
        }
        totalEncoded += encoded;

        NSDictionary *signMetadata = nil;
        NSString *signError = nil;
        if (!ZNAdhocResignMachOAtPath(path, &signMetadata, &signError)) {
            failure = [NSString stringWithFormat:@"%@：%@", path.lastPathComponent,
                       signError ?: @"ad-hoc CodeDirectory 重建失败"];
            break;
        }
        NSMutableDictionary *item = [signMetadata mutableCopy] ?: [NSMutableDictionary dictionary];
        item[@"output"] = path;
        item[@"encodedFeatureMetadataEntries"] = @(encoded);
        [signing addObject:item];
    }

    if (failure) {
        if (folder.length) [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
        if (error) *error = [NSString stringWithFormat:@"生成后二进制后处理失败：%@", failure];
        return NO;
    }

    // Legacy cache only. A reinstall may erase it without losing Feature names,
    // because new outputs resolve from the embedded ZNF1 representation first.
    for (NSDictionary *entry in nameEntries) {
        uint64_t siteRVA = [entry[@"siteRVA"] unsignedLongLongValue];
        uint32_t patchID = [entry[@"patchID"] unsignedIntValue];
        NSString *title = entry[@"title"];
        NSString *group = entry[@"group"];
        NSString *target = entry[@"target"];
        NSString *runtimeTarget = entry[@"runtimeTarget"];

        ZNFeatureNameRegistryStore(target, siteRVA, patchID, title, group);
        if (runtimeTarget.length && [runtimeTarget caseInsensitiveCompare:target] != NSOrderedSame) {
            ZNFeatureNameRegistryStore(runtimeTarget, siteRVA, patchID, title, group);
        }
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
        object[@"generatedBinaryPrivacy"] = @{
            @"targetMachODisplayNames": @NO,
            @"plainDisplayNamesPresent": @NO,
            @"embeddedFeatureID": @YES,
            @"displayMetadataCodec": @"ZNF1",
            @"encodedEntries": @(totalEncoded),
            @"displayNameStorage": @"generated-macho-static-entry-encoded",
            @"legacyRegistryFallbackWritten": @YES,
            @"titleGroupFieldsZeroed": @NO,
            @"staticEntryABIPreserved": @YES,
        };
        NSData *updated = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
        if (updated) [updated writeToFile:path atomically:YES];
        break;
    }

    if (outputs) *outputs = innerOutputs;
    if (report) {
        *report = [NSString stringWithFormat:@"%@\n已将生成 Mach-O 的功能名转换为稳定 FeatureID + ZNF1 编码 metadata，并重建 SHA-1/SHA-256 CodeDirectory 后逐页校验；NSUserDefaults 仅保留旧版兼容缓存。替换回 IPA 后仍需正常整包重签。",
                   innerReport ?: @"Static Binary Builder 生成成功"];
    }
    return YES;
}

@end
