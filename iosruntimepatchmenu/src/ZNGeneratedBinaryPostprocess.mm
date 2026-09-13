#import "ZNGeneratedBinaryPostprocess.h"
#import "ZNStaticMetadataPrivacy.h"
#import "ZNStaticRVAProtection.h"
#import "ZNAdhocMachOSigner.h"

BOOL ZNPostProcessGeneratedBinaryOutputs(NSArray<NSString *> *innerOutputs,
                                         NSString *innerReport,
                                         NSArray<NSString *> **outputs,
                                         NSString **report,
                                         NSString **error) {
    if (!innerOutputs.count) {
        if (error) *error = @"Static Binary Builder V3 未返回任何输出";
        return NO;
    }

    NSMutableArray<NSDictionary *> *signing = [NSMutableArray array];
    NSString *failure = nil;
    NSString *folder = nil;
    NSUInteger totalEncodedNames = 0;
    NSUInteger totalProtectedRVAs = 0;
    NSUInteger generatedTargets = 0;

    for (NSString *path in innerOutputs) {
        if (![path.pathExtension.lowercaseString isEqualToString:@"znpatched"]) continue;
        generatedTargets++;
        if (!folder.length) folder = path.stringByDeletingLastPathComponent;

        NSUInteger encodedNames = 0;
        NSString *privacyError = nil;
        if (!ZNScrubStaticDisplayMetadataAtPath(path, &encodedNames, &privacyError)) {
            failure = [NSString stringWithFormat:@"%@：%@",
                       path.lastPathComponent,
                       privacyError ?: @"显示 metadata 编码失败"];
            break;
        }
        totalEncodedNames += encodedNames;

        // Fixed v0.5.4 order: the display-name codec consumes the ordinary V3
        // Static Entry first. RVA protection then transforms site/off/on fields,
        // and the signer hashes only that final on-disk representation.
        NSUInteger protectedRVAs = 0;
        NSString *rvaError = nil;
        if (!ZN55ProtectStaticRVAsAtPath(path, &protectedRVAs, &rvaError)) {
            failure = [NSString stringWithFormat:@"%@：%@",
                       path.lastPathComponent,
                       rvaError ?: @"Static RVA Protection V1 失败"];
            break;
        }
        totalProtectedRVAs += protectedRVAs;

        NSDictionary *signMetadata = nil;
        NSString *signError = nil;
        if (!ZNAdhocResignMachOAtPath(path, &signMetadata, &signError)) {
            failure = [NSString stringWithFormat:@"%@：%@",
                       path.lastPathComponent,
                       signError ?: @"ad-hoc CodeDirectory 重建失败"];
            break;
        }

        NSMutableDictionary *item = [signMetadata mutableCopy] ?: [NSMutableDictionary dictionary];
        item[@"output"] = path;
        item[@"encodedFeatureMetadataEntries"] = @(encodedNames);
        item[@"protectedStaticRVAEntries"] = @(protectedRVAs);
        [signing addObject:item];
    }

    if (!failure && generatedTargets == 0) {
        failure = @"Builder 输出中没有 .znpatched 目标";
    }

    if (failure) {
        if (folder.length) [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
        if (error) *error = [NSString stringWithFormat:@"生成后二进制后处理失败：%@", failure];
        return NO;
    }

    // Add machine-readable evidence to V3's existing report without changing
    // the Static Dispatch format or runtime ABI.
    for (NSString *path in innerOutputs) {
        if (![path.lastPathComponent isEqualToString:@"build_report.json"]) continue;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data.length) continue;
        NSMutableDictionary *object = [[NSJSONSerialization JSONObjectWithData:data
                                                                        options:NSJSONReadingMutableContainers
                                                                          error:nil] mutableCopy];
        if (![object isKindOfClass:NSMutableDictionary.class]) continue;

        object[@"generatedBinaryPipeline"] = @{
            @"mode": @"explicit-v0.5.6",
            @"builder": @"Static Binary Builder V3",
            @"postprocessOrder": @[@"Payload Layout V2 (Builder)", @"ZNF1", @"Static RVA Protection V1", @"Adhoc CodeDirectory"],
            @"runtimeBuilderSwizzle": @NO,
            @"asyncLoadOrderDependency": @NO,
            @"legacyV1Compiled": @NO,
            @"legacySigningBridgeCompiled": @NO,
        };
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
            @"encodedEntries": @(totalEncodedNames),
            @"displayNameStorage": @"generated-macho-static-entry-encoded",
            @"legacyRegistryFallbackWritten": @NO,
            @"hostPreferencesContainTargetRVANameMap": @NO,
            @"titleGroupFieldsZeroed": @NO,
            @"staticEntryABIPreserved": @YES,
        };
        object[@"generatedBinaryProtection"] = @{
            @"mode": @"payload-v2+static-rva-protection-v1",
            @"plainStaticRVAFieldsPresent": @NO,
            @"protectedFields": @[@"siteRVA", @"offRVA", @"onRVA"],
            @"protectedEntries": @(totalProtectedRVAs),
            @"perOutputNonce": @YES,
            @"integrityCheck": @YES,
            @"runtimeDecodesOnDemand": @YES,
            @"runtimeWritesPlainRVAsBackToStaticEntry": @NO,
            @"scope": @"static-analysis-cost-layer",
            @"payloadProtectionV2": @YES,
            @"payloadLayout": @"fragmented-16-byte-slot-chain-v1",
            @"maxContiguousSourceInstructions": @1,
            @"runtimeExecutableWrites": @NO,
            @"directSiteBranchStillArchitectural": @YES,
        };

        NSData *updated = [NSJSONSerialization dataWithJSONObject:object
                                                          options:NSJSONWritingPrettyPrinted
                                                            error:nil];
        if (updated) [updated writeToFile:path atomically:YES];
        break;
    }

    if (outputs) *outputs = innerOutputs;
    if (report) {
        *report = [NSString stringWithFormat:@"%@\nv0.5.6 使用显式保护流水线：V3 Payload V2 → ZNF1 → Static RVA Protection V1 → ad-hoc CodeDirectory。已移除 Builder +load/swizzle 与异步 SigningBridge 顺序依赖；替换回 IPA 后仍需正常整包重签。",
                   innerReport ?: @"Static Binary Builder V3 生成成功"];
    }
    return YES;
}
