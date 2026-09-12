#import "ZNStaticMetadataPrivacy.h"
#import "ZNStaticPatchFormat.h"
#import <mach-o/loader.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

BOOL ZNScrubStaticDisplayMetadataAtPath(NSString *path,
                                        NSUInteger *scrubbedEntries,
                                        NSString **error) {
    if (scrubbedEntries) *scrubbedEntries = 0;
    if (!path.length) {
        if (error) *error = @"输出路径为空";
        return NO;
    }

    int fd = open(path.fileSystemRepresentation, O_RDWR);
    if (fd < 0) {
        if (error) *error = [NSString stringWithFormat:@"打开生成二进制失败：errno=%d", errno];
        return NO;
    }

    struct stat st = {};
    if (fstat(fd, &st) != 0 || st.st_size < (off_t)sizeof(struct mach_header_64)) {
        close(fd);
        if (error) *error = @"生成二进制大小无效";
        return NO;
    }

    size_t size = (size_t)st.st_size;
    uint8_t *base = (uint8_t *)mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (base == MAP_FAILED) {
        close(fd);
        if (error) *error = @"mmap 生成二进制失败";
        return NO;
    }

    BOOL ok = NO;
    NSString *localError = nil;
    NSUInteger total = 0;

    do {
        struct mach_header_64 *mh = (struct mach_header_64 *)base;
        if (mh->magic != MH_MAGIC_64) {
            localError = @"隐私清理仅支持 thin 64-bit Mach-O";
            break;
        }

        uint64_t commandEnd = sizeof(*mh) + (uint64_t)mh->sizeofcmds;
        if (commandEnd > size) {
            localError = @"Mach-O load commands 越界";
            break;
        }

        uint8_t *cursor = base + sizeof(*mh);
        uint8_t *limit = base + commandEnd;
        for (uint32_t i = 0; i < mh->ncmds; i++) {
            if (cursor + sizeof(struct load_command) > limit) {
                localError = @"Mach-O load command 损坏";
                break;
            }
            struct load_command *lc = (struct load_command *)cursor;
            if (lc->cmdsize < sizeof(struct load_command) || cursor + lc->cmdsize > limit) {
                localError = @"Mach-O load command size 损坏";
                break;
            }

            if (lc->cmd == LC_SEGMENT_64 && lc->cmdsize >= sizeof(struct segment_command_64)) {
                struct segment_command_64 *seg = (struct segment_command_64 *)cursor;
                if (strncmp(seg->segname, "__ZNDATA", 16) == 0) {
                    if (seg->fileoff > size || seg->filesize > size - seg->fileoff) {
                        localError = @"__ZNDATA file range 越界";
                        break;
                    }

                    uint64_t start = seg->fileoff;
                    uint64_t end = seg->fileoff + seg->filesize;
                    uint64_t scan = (start + 7u) & ~UINT64_C(7);
                    for (; scan + sizeof(ZN44StaticHeader) <= end; scan += 8u) {
                        ZN44StaticHeader *header = (ZN44StaticHeader *)(base + scan);
                        if (header->magic0 != ZN44_STATIC_MAGIC0 || header->magic1 != ZN44_STATIC_MAGIC1) continue;
                        if ((header->version != ZN44_STATIC_VERSION_V1 && header->version != ZN44_STATIC_VERSION_V2) ||
                            header->entrySize != sizeof(ZN44StaticEntry) ||
                            header->count == 0 || header->count > ZN44_STATIC_MAX_ENTRIES) {
                            continue;
                        }

                        uint64_t bytes = sizeof(ZN44StaticHeader) + (uint64_t)header->count * sizeof(ZN44StaticEntry);
                        if (scan + bytes > end) {
                            localError = @"__ZNDATA Static Header 越界";
                            break;
                        }

                        ZN44StaticEntry *entries = (ZN44StaticEntry *)(header + 1);
                        for (uint32_t e = 0; e < header->count; e++) {
                            memset(entries[e].title, 0, sizeof(entries[e].title));
                            memset(entries[e].group, 0, sizeof(entries[e].group));
                            total++;
                        }
                        scan += bytes - 8u;
                    }
                    if (localError) break;
                }
            }
            cursor += lc->cmdsize;
        }
        if (localError) break;
        if (!total) {
            localError = @"未在 __ZNDATA 找到 Static Dispatch metadata";
            break;
        }
        if (msync(base, size, MS_SYNC) != 0) {
            localError = [NSString stringWithFormat:@"隐私清理 msync 失败：errno=%d", errno];
            break;
        }
        ok = YES;
    } while (0);

    munmap(base, size);
    close(fd);

    if (scrubbedEntries) *scrubbedEntries = total;
    if (!ok && error) *error = localError ?: @"生成二进制显示 metadata 清理失败";
    return ok;
}
