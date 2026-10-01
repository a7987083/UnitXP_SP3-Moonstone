#import "ZNTypedValueDispatchRuntime.h"
#import "ZNTypedValueStaticFormat.h"
#import "ZNStaticPatchFormat.h"
#import "ZNH5GGValueBackend.h"
#import "ZNPatchCore.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>

@interface ZNTypedValueRuntimeRecord ()
@property(nonatomic,copy,readwrite) NSString *target;
@property(nonatomic,copy,readwrite) NSString *title;
@property(nonatomic,copy,readwrite) NSString *valueType;
@property(nonatomic,assign,readwrite) uint64_t rva;
@property(nonatomic,assign,readwrite) ZNTVStaticControl control;
@property(nonatomic,assign,readwrite) double minValue;
@property(nonatomic,assign,readwrite) double maxValue;
@property(nonatomic,assign,readwrite) double stepValue;
@property(nonatomic,assign,readwrite) double defaultValue;
@property(nonatomic,copy,readwrite) NSString *currentValueText;
@property(nonatomic,assign) uintptr_t imageBase;
@end
@implementation ZNTypedValueRuntimeRecord
@end

@interface ZNTypedValueDispatchRuntime ()
@property(nonatomic,copy,readwrite) NSArray<ZNTypedValueRuntimeRecord *> *records;
@end

static uint64_t ZNTVAlign8Runtime(uint64_t value) { return (value + 7ULL) & ~7ULL; }

static NSString *ZNTVFixedString(const char *bytes, size_t cap, NSString *fallback) {
    size_t n = bytes ? strnlen(bytes, cap) : 0;
    if (!n) return fallback ?: @"";
    NSString *s = [[NSString alloc] initWithBytes:bytes length:n encoding:NSUTF8StringEncoding];
    return s.length ? s : (fallback ?: @"");
}

@implementation ZNTypedValueDispatchRuntime

+ (instancetype)sharedRuntime {
    static ZNTypedValueDispatchRuntime *runtime;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        runtime = [ZNTypedValueDispatchRuntime new];
        runtime.records = @[];
        [[NSNotificationCenter defaultCenter] addObserver:runtime
                                                 selector:@selector(zn_imageAdded:)
                                                     name:@"ZNModuleManagerImageAdded"
                                                   object:nil];
    });
    return runtime;
}

- (void)zn_imageAdded:(NSNotification *)note {
    (void)note;
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}

- (void)refresh {
    NSMutableArray<ZNTypedValueRuntimeRecord *> *found = [NSMutableArray array];
    NSString *bundleRoot = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    uint32_t imageCount = _dyld_image_count();

    for (uint32_t imageIndex = 0; imageIndex < imageCount; imageIndex++) {
        const char *rawPath = _dyld_get_image_name(imageIndex);
        if (!rawPath) continue;
        NSString *path = [[NSString stringWithUTF8String:rawPath] stringByStandardizingPath];
        if (!path.length || ![path hasPrefix:bundleRoot]) continue;

        const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(imageIndex);
        if (!mh || mh->magic != MH_MAGIC_64) continue;
        uintptr_t runtimeHeader = (uintptr_t)mh;
        const uint8_t *cursor = (const uint8_t *)(mh + 1);
        const uint8_t *limit = cursor + mh->sizeofcmds;

        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if (cursor + sizeof(struct load_command) > limit) break;
            const struct load_command *lc = (const struct load_command *)cursor;
            if (lc->cmdsize < sizeof(*lc) || cursor + lc->cmdsize > limit) break;
            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                const struct segment_command_64 *seg = (const struct segment_command_64 *)cursor;
                uint64_t sectionBytes = (uint64_t)seg->nsects * sizeof(struct section_64);
                if (strncmp(seg->segname, "__ZNDATA", 16) == 0 &&
                    lc->cmdsize >= sizeof(*seg) + sectionBytes) {
                    const struct section_64 *secs = (const struct section_64 *)(seg + 1);
                    for (uint32_t j = 0; j < seg->nsects; j++) {
                        const struct section_64 *sec = &secs[j];
                        if (strncmp(sec->sectname, "__zndata", 16) != 0) continue;
                        if (sec->size < sizeof(ZN44StaticHeader)) break;
                        uintptr_t sectionStart = runtimeHeader + (uintptr_t)(sec->addr - seg->vmaddr) + (uintptr_t)(seg->vmaddr - ((const struct segment_command_64 *)seg)->vmaddr);
                        // __ZNDATA is builder-owned and its runtime section address is
                        // relative to this image's header by image RVA. Recover imageVMBase.
                        uint64_t imageVMBase = UINT64_MAX;
                        const uint8_t *c2 = (const uint8_t *)(mh + 1);
                        for (uint32_t k = 0; k < mh->ncmds; k++) {
                            if (c2 + sizeof(struct load_command) > limit) break;
                            const struct load_command *lc2 = (const struct load_command *)c2;
                            if (lc2->cmdsize < sizeof(*lc2) || c2 + lc2->cmdsize > limit) break;
                            if (lc2->cmd == LC_SEGMENT_64 && lc2->cmdsize >= sizeof(struct segment_command_64)) {
                                const struct segment_command_64 *s2 = (const struct segment_command_64 *)c2;
                                if (strncmp(s2->segname, SEG_TEXT, 16) == 0) { imageVMBase = s2->vmaddr; break; }
                            }
                            c2 += lc2->cmdsize;
                        }
                        if (imageVMBase == UINT64_MAX || sec->addr < imageVMBase) break;
                        sectionStart = runtimeHeader + (uintptr_t)(sec->addr - imageVMBase);
                        uintptr_t sectionEnd = sectionStart + (uintptr_t)sec->size;

                        const ZN44StaticHeader *staticHeader = (const ZN44StaticHeader *)sectionStart;
                        if (staticHeader->magic0 != ZN44_STATIC_MAGIC0 || staticHeader->magic1 != ZN44_STATIC_MAGIC1 ||
                            staticHeader->entrySize != sizeof(ZN44StaticEntry) || staticHeader->count > ZN44_STATIC_MAX_ENTRIES) break;
                        uint64_t staticUsed = sizeof(ZN44StaticHeader) + (uint64_t)staticHeader->count * sizeof(ZN44StaticEntry);
                        uintptr_t typedAddress = sectionStart + (uintptr_t)ZNTVAlign8Runtime(staticUsed);
                        if (typedAddress + sizeof(ZNTVStaticHeader) > sectionEnd) break;

                        const ZNTVStaticHeader *typedHeader = (const ZNTVStaticHeader *)typedAddress;
                        if (typedHeader->magic0 != ZNTV_STATIC_MAGIC0 || typedHeader->magic1 != ZNTV_STATIC_MAGIC1 ||
                            typedHeader->version != ZNTV_STATIC_VERSION || typedHeader->entrySize != sizeof(ZNTVStaticEntry) ||
                            typedHeader->count > ZNTV_STATIC_MAX_ENTRIES) break;
                        uint64_t total = sizeof(ZNTVStaticHeader) + (uint64_t)typedHeader->count * sizeof(ZNTVStaticEntry);
                        if (typedAddress + total > sectionEnd) break;

                        const ZNTVStaticEntry *entries = (const ZNTVStaticEntry *)(typedHeader + 1);
                        for (uint32_t n = 0; n < typedHeader->count; n++) {
                            const ZNTVStaticEntry *src = &entries[n];
                            NSString *type = ZNTVFixedString(src->valueType, sizeof(src->valueType), @"F32").uppercaseString;
                            if (![ZNH5GGValueBackend isSupportedType:type]) continue;
                            ZNTypedValueRuntimeRecord *record = [ZNTypedValueRuntimeRecord new];
                            record.target = path.lastPathComponent ?: @"main";
                            record.title = ZNTVFixedString(src->title, sizeof(src->title), [NSString stringWithFormat:@"Value #%u", n + 1]);
                            record.valueType = type;
                            record.rva = src->rva;
                            record.control = src->control == ZNTVStaticControlNumber ? ZNTVStaticControlNumber : ZNTVStaticControlSlider;
                            record.minValue = src->minValue;
                            record.maxValue = src->maxValue;
                            record.stepValue = src->stepValue;
                            record.defaultValue = src->defaultValue;
                            record.imageBase = runtimeHeader;
                            record.currentValueText = @"";
                            [found addObject:record];
                        }
                        break;
                    }
                }
            }
            cursor += lc->cmdsize;
        }
    }

    self.records = found;
    for (ZNTypedValueRuntimeRecord *record in self.records) [self refreshValueForRecord:record error:nil];
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.11-value-runtime] discovered=%lu backend=%@",
                                          (unsigned long)self.records.count,
                                          [ZNH5GGValueBackend sharedBackend].availabilityText]];
}

- (BOOL)refreshValueForRecord:(ZNTypedValueRuntimeRecord *)record error:(NSString **)error {
    if (!record || !record.imageBase || !record.rva) { if (error) *error = @"Typed Value record 无效"; return NO; }
    uint64_t address = (uint64_t)record.imageBase + record.rva;
    NSString *value = [[ZNH5GGValueBackend sharedBackend] readAddress:address type:record.valueType error:error];
    if (!value.length) return NO;
    record.currentValueText = value;
    return YES;
}

- (BOOL)setValueText:(NSString *)value forRecord:(ZNTypedValueRuntimeRecord *)record error:(NSString **)error {
    if (!record || !record.imageBase || !record.rva) { if (error) *error = @"Typed Value record 无效"; return NO; }
    NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:value ?: @"" locale:@{NSLocaleDecimalSeparator:@"."}];
    if ([number isEqualToNumber:NSDecimalNumber.notANumber]) { if (error) *error = @"数值格式无效"; return NO; }
    double d = number.doubleValue;
    if (record.control == ZNTVStaticControlSlider && (d < record.minValue || d > record.maxValue)) {
        if (error) *error = [NSString stringWithFormat:@"数值超出范围 %.6g ~ %.6g", record.minValue, record.maxValue];
        return NO;
    }
    uint64_t address = (uint64_t)record.imageBase + record.rva;
    if (![[ZNH5GGValueBackend sharedBackend] writeAddress:address value:value type:record.valueType error:error]) return NO;
    record.currentValueText = value ?: @"";
    return YES;
}

- (NSArray<NSString *> *)diagnosticLines {
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"Typed Value：%lu · %@", (unsigned long)self.records.count, [ZNH5GGValueBackend sharedBackend].availabilityText]];
    for (ZNTypedValueRuntimeRecord *r in self.records) {
        [lines addObject:[NSString stringWithFormat:@"%@ · %@+0x%llX · %@ · %@",
                          r.title, r.target, r.rva, r.valueType, r.control == ZNTVStaticControlSlider ? @"Slider" : @"Number"]];
        if (lines.count >= 12) break;
    }
    return lines;
}

@end
