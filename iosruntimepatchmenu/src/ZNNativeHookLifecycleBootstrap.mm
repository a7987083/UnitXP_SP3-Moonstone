#import "ZNNativeHookLifecycleBootstrap.h"

#import <mach-o/dyld.h>

#import "ZNNativeHookRuntime.h"
#import "ZNNativeHookScheduler.h"
#import "ZNPatchCore.h"

@interface ZNNativeHookLifecycleBootstrap ()
@property(nonatomic,strong) dispatch_queue_t queue;
@property(nonatomic,assign) BOOL started;
@property(nonatomic,assign) BOOL scheduled;
@property(nonatomic,assign) uint32_t lastImageCount;
@end

static void ZNNativeHookLifecycleImageAdded(const struct mach_header *mh, intptr_t slide) {
    (void)mh;
    (void)slide;
    [[ZNNativeHookLifecycleBootstrap sharedBootstrap] requestReconcile];
}

@implementation ZNNativeHookLifecycleBootstrap

+ (instancetype)sharedBootstrap {
    static ZNNativeHookLifecycleBootstrap *bootstrap;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bootstrap=[ZNNativeHookLifecycleBootstrap new];
    });
    return bootstrap;
}

- (instancetype)init {
    self=[super init];
    if(!self)return nil;
    _queue=dispatch_queue_create("com.zonoe.native-hook.lifecycle-bootstrap",DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)start {
    @synchronized(self) {
        if(self.started)return;
        self.started=YES;
    }

    // dyld immediately replays already-loaded images. requestReconcile coalesces
    // those callbacks, so startup performs one Hook-only discovery pass.
    _dyld_register_func_for_add_image(ZNNativeHookLifecycleImageAdded);
    [self requestReconcile];

    [[ZNRuntimeLogger sharedLogger] log:
     @"[native-hook-lifecycle] early bootstrap started; hook prepare detached from menu activation"];
}

- (void)requestReconcile {
    @synchronized(self) {
        if(self.scheduled)return;
        self.scheduled=YES;
    }

    __weak typeof(self) weakSelf=self;
    dispatch_async(self.queue,^{
        typeof(self) self=weakSelf;
        if(!self)return;

        uint32_t before=_dyld_image_count();
        ZNNativeHookRuntime *runtime=[ZNNativeHookRuntime sharedRuntime];
        [runtime refreshGeneratedActions];
        NSArray *actions=[runtime.generatedActions copy]?:@[];
        [[ZNNativeHookScheduler sharedScheduler] reconcileActions:actions];

        @synchronized(self) {
            self.lastImageCount=_dyld_image_count();
            self.scheduled=NO;
        }

        [[ZNRuntimeLogger sharedLogger] log:
         [NSString stringWithFormat:@"[native-hook-lifecycle] reconcile images=%u->%u actions=%lu",
          before,self.lastImageCount,(unsigned long)actions.count]];

        // If another image arrived while the pass was running, schedule exactly
        // one additional pass; the runtime's unchanged-image path is O(1).
        if(_dyld_image_count()!=self.lastImageCount)[self requestReconcile];
    });
}

@end

__attribute__((constructor(201))) static void ZNNativeHookEarlyLifecycleBootstrap(void) {
    @autoreleasepool {
        [[ZNNativeHookLifecycleBootstrap sharedBootstrap] start];
    }
}
