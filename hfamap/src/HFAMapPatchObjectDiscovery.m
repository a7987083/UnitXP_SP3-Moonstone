#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void HFAAppendLog(NSString *s) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/HFAMap_Learn.log"];
    FILE *f = fopen(path.fileSystemRepresentation, "a");
    if (!f) return;
    fprintf(f, "%s\n", s.UTF8String);
    fclose(f);
}

static void HFAInspectClass(Class cls) {
    if (!cls) return;
    const char *name = class_getName(cls);
    if (!name) return;
    if (strstr(name, "Patch") || strstr(name, "patch") || strstr(name, "Feature")) {
        HFAAppendLog([NSString stringWithFormat:@"[PATCH-CLASS] %s", name]);
    }
}

static void HFAEnumerateClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)malloc(sizeof(Class) * count);
    if (!classes) return;
    count = objc_getClassList(classes, count);
    for (int i = 0; i < count; i++) {
        HFAInspectClass(classes[i]);
    }
    free(classes);
}

__attribute__((constructor))
static void HFAPatchDiscoveryInit(void) {
    HFAAppendLog(@"[PATCH-DISCOVERY] v1.4.6 PatchObject Discovery loaded");
    dispatch_async(dispatch_get_main_queue(), ^{
        HFAEnumerateClasses();
    });
}
