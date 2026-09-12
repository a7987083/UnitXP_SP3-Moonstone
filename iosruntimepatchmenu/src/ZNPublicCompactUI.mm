#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Public menu presentation policy for v0.5.1 Protection V1.
// Keep the existing compact layout implementation and make it the default
// presentation after this migration. Users can still expand through the
// existing mode button; this only changes the post-upgrade default.

static NSString * const kZNPublicCompactMigrationKey = @"zonoe.public-compact-ui.v1";
static NSString * const kZNCompactModeDefaultsKey = @"ZonoePatch.CompactMode";
static NSString * const kZNSelectedCategoryDefaultsKey = @"ZonoePatch.SelectedCategory";
static NSString * const kZNLegacyFeatureNameRegistryDefaultsKey = @"zonoe.feature-name-registry.v1";

@interface ZNRuntimeMenuControllerV040 : NSObject
+ (instancetype)shared;
@property(nonatomic,assign) BOOL compactMode;
@property(nonatomic,assign) NSInteger selectedCategory;
@property(nonatomic,strong) UILabel *subtitleLabel;
- (void)layoutPanel;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNPublicCompactUI)

- (void)znpublic_layoutPanel {
    [self znpublic_layoutPanel];
    if (self.compactMode) {
        self.subtitleLabel.text = @"0.5.1";
        self.subtitleLabel.alpha = 0.72;
    }
}

+ (void)load {
    Method original = class_getInstanceMethod(self, @selector(layoutPanel));
    Method replacement = class_getInstanceMethod(self, @selector(znpublic_layoutPanel));
    if (original && replacement) method_exchangeImplementations(original, replacement);
}

@end

__attribute__((constructor(121))) static void ZNInstallPublicCompactDefaults(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;

        // The old v0.5 Privacy UI registry linked target/RVA/patchID directly to
        // title/group. New ZNF1 outputs do not depend on it, so remove it on
        // every launch and never recreate it.
        [defaults removeObjectForKey:kZNLegacyFeatureNameRegistryDefaultsKey];

        BOOL migrated = [defaults boolForKey:kZNPublicCompactMigrationKey];
        if (!migrated) {
            [defaults setBool:YES forKey:kZNCompactModeDefaultsKey];
            [defaults setInteger:0 forKey:kZNSelectedCategoryDefaultsKey];
            [defaults setBool:YES forKey:kZNPublicCompactMigrationKey];

            // If the controller was instantiated by an earlier constructor,
            // update the in-memory state too. Otherwise these defaults are read
            // normally when the singleton is first created.
            Class cls = NSClassFromString(@"ZNRuntimeMenuControllerV040");
            if (cls && [cls respondsToSelector:@selector(shared)]) {
                ZNRuntimeMenuControllerV040 *controller = [cls shared];
                controller.compactMode = YES;
                controller.selectedCategory = 0;
            }
        }

        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kZNLegacyFeatureNameRegistryDefaultsKey];
        NSLog(@"[ZonoPatch] public compact UI installed; legacy feature-name registry purged");
    }
}
