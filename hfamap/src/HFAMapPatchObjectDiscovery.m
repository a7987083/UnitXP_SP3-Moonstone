#import <Foundation/Foundation.h>

static void HFAPatchDiscoveryLog(void) {
    @autoreleasepool {
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/HFAMap_Learn.log"];
        FILE *f = fopen(path.fileSystemRepresentation, "a");
        if (!f) return;
        fprintf(f, "[PATCH-DISCOVERY] v1.4.6 module loaded\n");
        fclose(f);
    }
}

__attribute__((constructor))
static void HFAPatchDiscoveryInit(void) {
    HFAPatchDiscoveryLog();
}
