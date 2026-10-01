#import "ZNPatchJSONImporter.h"
#import "ZNDeveloperGate.h"
#import <errno.h>
#import <dirent.h>
#import <string.h>

static NSString *gZNJIDiscoveryStatus = @"尚未扫描 JSON";

static NSString *ZNJIKey(id key) {
    if (![key isKindOfClass:NSString.class]) return @"";
    NSString *s = [(NSString *)key lowercaseString];
    NSCharacterSet *drop = [NSCharacterSet characterSetWithCharactersInString:@"_- .\t\r\n"];
    return [[s componentsSeparatedByCharactersInSet:drop] componentsJoinedByString:@""];
}

static id ZNJIValue(NSDictionary *d, NSArray<NSString *> *names) {
    NSSet *wanted = [NSSet setWithArray:names];
    for (id key in d) if ([wanted containsObject:ZNJIKey(key)]) return d[key];
    return nil;
}

static NSString *ZNJIString(id value) {
    return [value isKindOfClass:NSString.class]
        ? [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        : @"";
}

// Importer intentionally does not parse or normalize addresses. ZNOffsetCore is
// the single RVA authority. Explicit JSON offset/rva values are forwarded as
// text and validated later by ZNPatchRuntimeValidator.
static NSString *ZNJIOffsetText(id value) {
    if ([value isKindOfClass:NSString.class]) return ZNJIString(value);
    if ([value isKindOfClass:NSNumber.class]) return [(NSNumber *)value stringValue] ?: @"";
    return @"";
}

static NSString *ZNJIHex(id value) {
    if ([value isKindOfClass:NSArray.class]) {
        NSMutableString *s = [NSMutableString string];
        for (id x in (NSArray *)value) {
            if (![x isKindOfClass:NSNumber.class]) return nil;
            NSInteger n = [x integerValue];
            if (n < 0 || n > 255) return nil;
            [s appendFormat:@"%02lX", (long)n];
        }
        return s.length ? s : nil;
    }
    NSString *input = ZNJIString(value);
    if (!input.length) return nil;
    NSMutableString *s = [NSMutableString string];
    NSCharacterSet *hex = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    for (NSUInteger i = 0; i < input.length; i++) {
        unichar c = [input characterAtIndex:i];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c] || c == ':' || c == '-' || c == ',' || c == '_') continue;
        if ((c == 'x' || c == 'X') && s.length == 1 && [s isEqualToString:@"0"]) { [s setString:@""]; continue; }
        if (![hex characterIsMember:c]) return nil;
        [s appendFormat:@"%C", c];
    }
    if (!s.length || (s.length & 1u)) return nil;
    return s.uppercaseString;
}

static NSDictionary *ZNJIAliases(id root) {
    if (![root isKindOfClass:NSDictionary.class]) return @{};
    id targets = ZNJIValue(root, @[@"targets", @"images", @"modules", @"binaries"]);
    if (![targets isKindOfClass:NSDictionary.class]) return @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [(NSDictionary *)targets enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        NSString *alias = ZNJIString(key), *image = @"";
        if ([obj isKindOfClass:NSString.class]) image = ZNJIString(obj);
        else if ([obj isKindOfClass:NSDictionary.class]) {
            image = ZNJIString(ZNJIValue(obj, @[@"target", @"image", @"binary", @"module", @"modulename", @"executable"]));
        }
        if (alias.length && image.length) out[alias.lowercaseString] = image;
    }];
    return out;
}

static NSString *ZNJIResolveTarget(NSString *target, NSDictionary *aliases) {
    NSString *clean = [target stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *mapped = aliases[clean.lowercaseString];
    return mapped.length ? mapped : clean;
}

static void ZNJIWalk(id node,
                     NSString *path,
                     NSString *parentTarget,
                     NSString *parentTitle,
                     NSString *parentGroup,
                     NSDictionary *aliases,
                     NSMutableArray *out) {
    if ([node isKindOfClass:NSArray.class]) {
        [(NSArray *)node enumerateObjectsUsingBlock:^(id obj, NSUInteger index, BOOL *stop) {
            (void)stop;
            ZNJIWalk(obj, [path stringByAppendingFormat:@"[%lu]", (unsigned long)index], parentTarget, parentTitle, parentGroup, aliases, out);
        }];
        return;
    }
    if (![node isKindOfClass:NSDictionary.class]) return;

    NSDictionary *d = node;
    NSString *ownTarget = ZNJIString(ZNJIValue(d, @[@"target", @"image", @"binary", @"module", @"modulename", @"executable"]));
    NSString *target = ownTarget.length ? ZNJIResolveTarget(ownTarget, aliases) : parentTarget;
    NSString *ownTitle = ZNJIString(ZNJIValue(d, @[@"title", @"name", @"label", @"featuretitle"]));
    NSString *title = ownTitle.length ? ownTitle : parentTitle;
    NSString *ownGroup = ZNJIString(ZNJIValue(d, @[@"group", @"category", @"section", @"tab"]));
    NSString *group = ownGroup.length ? ownGroup : parentGroup;

    // Only explicit RVA semantics are importable. Generic address/addr/location
    // fields are intentionally ignored because their coordinate system is
    // ambiguous and must never be guessed by the importer.
    id offsetValue = ZNJIValue(d, @[@"offset", @"rva"]);
    id enabledValue = ZNJIValue(d, @[@"enabled", @"patch", @"patchdata", @"bytes", @"patchbytes", @"data", @"value", @"on", @"enable", @"replacement", @"replace"]);
    NSString *offsetText = ZNJIOffsetText(offsetValue);
    NSString *hex = ZNJIHex(enabledValue);
    if (offsetText.length && hex.length) {
        [out addObject:@{
            @"target": target ?: @"",
            @"offset": offsetText,
            @"enabled": hex,
            @"title": title ?: @"",
            @"group": group.length ? group : @"Imported",
            @"path": path ?: @"$",
            @"confidence": @1.0
        }];
    }

    [d enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        (void)stop;
        if ([obj isKindOfClass:NSDictionary.class] || [obj isKindOfClass:NSArray.class]) {
            ZNJIWalk(obj, [path stringByAppendingFormat:@".%@", [key description]], target, title, group, aliases, out);
        }
    }];
}

static void ZNJICollectJSONNamesPOSIX(NSString *root, NSMutableOrderedSet<NSString *> *names, NSString **posixError) {
    const char *fs = root.fileSystemRepresentation;
    errno = 0;
    DIR *dir = opendir(fs);
    if (!dir) {
        if (posixError) *posixError = [NSString stringWithFormat:@"opendir errno=%d (%s)", errno, strerror(errno)];
        return;
    }
    struct dirent *ent = NULL;
    while ((ent = readdir(dir)) != NULL) {
        if (!ent->d_name[0] || !strcmp(ent->d_name, ".") || !strcmp(ent->d_name, "..")) continue;
        NSString *name = [[NSString alloc] initWithUTF8String:ent->d_name];
        if (name.length && [name.pathExtension.lowercaseString isEqualToString:@"json"]) [names addObject:name];
    }
    closedir(dir);
}

@implementation ZNPatchJSONImporter

+ (NSArray<NSString *> *)discoverJSONFiles {
    ZNDeveloperGate *gate = [ZNDeveloperGate sharedGate];
    [gate refresh];
    NSString *marker = gate.markerPath;
    if (!marker.length) {
        gZNJIDiscoveryStatus = @"自动扫描失败：未找到文件 1";
        return @[];
    }

    NSString *root = marker.stringByDeletingLastPathComponent;
    NSFileManager *fm = NSFileManager.defaultManager;
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:root isDirectory:&isDir] || !isDir) {
        gZNJIDiscoveryStatus = [NSString stringWithFormat:@"自动扫描失败：1 的父目录不存在 · %@", root];
        return @[];
    }

    NSError *foundationError = nil;
    NSArray<NSString *> *foundationNames = [fm contentsOfDirectoryAtPath:root error:&foundationError];
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (NSString *name in foundationNames ?: @[]) {
        if ([name.pathExtension.lowercaseString isEqualToString:@"json"]) [names addObject:name];
    }

    NSString *posixError = nil;
    if (!foundationNames || names.count == 0) ZNJICollectJSONNamesPOSIX(root, names, &posixError);

    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (NSString *name in names) {
        NSString *candidate = [root stringByAppendingPathComponent:name];
        BOOL childDir = NO;
        if ([fm fileExistsAtPath:candidate isDirectory:&childDir] && !childDir) [found addObject:candidate];
    }
    [found sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a.lastPathComponent localizedStandardCompare:b.lastPathComponent];
    }];

    NSString *method = foundationNames ? @"Foundation" : @"POSIX";
    if (found.count) {
        gZNJIDiscoveryStatus = [NSString stringWithFormat:@"与 1 同目录：发现 %lu 个 JSON · %@", (unsigned long)found.count, method];
    } else {
        NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"与 1 同目录未发现 JSON · %@", root]];
        if (foundationError) [parts addObject:[NSString stringWithFormat:@"Foundation: %@", foundationError.localizedDescription ?: @"未知错误"]];
        if (posixError.length) [parts addObject:[NSString stringWithFormat:@"POSIX: %@", posixError]];
        gZNJIDiscoveryStatus = [parts componentsJoinedByString:@" · "];
    }
    return found;
}

+ (NSString *)discoveryStatus {
    return gZNJIDiscoveryStatus ?: @"尚未扫描 JSON";
}

+ (NSArray<NSDictionary *> *)importFile:(NSString *)path error:(NSString **)error {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&readError];
    if (!data.length) {
        if (error) *error = [NSString stringWithFormat:@"JSON 文件读取失败或为空：%@%@",
                             path.lastPathComponent ?: @"未知文件",
                             readError ? [NSString stringWithFormat:@" · %@", readError.localizedDescription ?: @"未知错误"] : @""];
        return nil;
    }
    NSError *jsonError = nil;
    id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:&jsonError];
    if (!root) {
        if (error) *error = [NSString stringWithFormat:@"JSON 解析失败：%@", jsonError.localizedDescription ?: @"未知错误"];
        return nil;
    }

    NSMutableArray *raw = [NSMutableArray array];
    ZNJIWalk(root, @"$", @"", @"", @"Imported", ZNJIAliases(root), raw);
    if (!raw.count) {
        if (error) *error = @"未识别到显式 offset/rva + enabled/patch/bytes 组合；address/addr/location 不再猜测";
        return nil;
    }

    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *row in raw) {
        NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                         [row[@"target"] lowercaseString],
                         [row[@"offset"] lowercaseString],
                         [row[@"enabled"] uppercaseString]];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        [out addObject:row];
    }
    return out;
}
@end
