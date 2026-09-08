#include "ZonoeRuntimeMenuV045.mm"
#import "ZNBinaryPatchWorkspace.h"

// v0.4.7 manual JSON import layer.
// The automatic sandbox directory scan is no longer used by the UI.
// Tapping `导入 JSON` presents UIDocumentPickerViewController so the user can
// select any visible *.json / *.hfapatch.json file explicitly.

static UIViewController *ZN47TopViewController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented=vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZN47TopViewController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top=((UINavigationController *)vc).visibleViewController;
        return top?ZN47TopViewController(top):vc;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *sel=((UITabBarController *)vc).selectedViewController;
        return sel?ZN47TopViewController(sel):vc;
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        UIViewController *last=((UISplitViewController *)vc).viewControllers.lastObject;
        return last?ZN47TopViewController(last):vc;
    }
    return vc;
}

@interface ZNRuntimeMenuControllerV040 (V047) <UIDocumentPickerDelegate>
- (void)zn47_importJSON:(id)sender;
- (void)zn47_makeUI:(UIWindow *)window;
- (void)zn47_tick:(NSTimer *)timer;
@end

@implementation ZNRuntimeMenuControllerV040 (V047)

- (void)zn47_importJSON:(id)sender {
    (void)sender;
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
    if (ws.hasAnyApplied || ws.isBuilding) return;

    // Manual picker replaces directory discovery. Keep the old list collapsed.
    ws.showJSONFiles=NO;
    [self.hostWindow endEditing:YES];

    NSArray<NSString *> *types=@[@"public.json",@"public.text",@"public.data"];
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeImport];
    picker.delegate=(id<UIDocumentPickerDelegate>)self;
    picker.allowsMultipleSelection=NO;
    picker.modalPresentationStyle=UIModalPresentationFormSheet;

    UIWindow *window=self.hostWindow;
    if (!window) window=UIApplication.sharedApplication.keyWindow;
    UIViewController *presenter=ZN47TopViewController(window.rootViewController);
    if (!presenter) {
        ws.lastStatus=@"导入失败：找不到可用于弹出文件选择器的 ViewController";
        [self renderPage];
        return;
    }
    [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url=urls.firstObject;
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
    if (!url) {
        ws.lastStatus=@"导入失败：没有选择文件";
        [self renderPage];
        return;
    }

    NSString *name=url.lastPathComponent?:@"";
    if (![[name.pathExtension lowercaseString] isEqualToString:@"json"]) {
        ws.lastStatus=[NSString stringWithFormat:@"导入失败：%@ 不是 JSON 文件",name.length?name:@"所选文件"];
        [self renderPage];
        return;
    }

    BOOL scoped=[url startAccessingSecurityScopedResource];
    NSString *error=nil;
    BOOL ok=[ws importJSONAtPath:url.path error:&error];
    if (scoped) [url stopAccessingSecurityScopedResource];

    if (ok) {
        ws.lastStatus=[NSString stringWithFormat:@"已导入：%@ · Patch %lu",name,(unsigned long)ws.filledCount];
    } else {
        ws.lastStatus=[NSString stringWithFormat:@"导入失败：%@",error?:@"未知错误"];
    }
    [self renderPage];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
}

- (void)zn47_makeUI:(UIWindow *)window {
    [self zn47_makeUI:window];
    [ZNBinaryPatchWorkspace sharedWorkspace].showJSONFiles=NO;
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.7    Manual JSON Import + Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn47_tick:(NSTimer *)timer {
    [self zn47_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.7    Manual JSON Import + Binary Builder    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV047(Class cls,SEL a,SEL b){
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if(x&&y) method_exchangeImplementations(x,y);
}

__attribute__((constructor(112))) static void ZNInstallV047ManualJSONImport(void){
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(!cls) return;
        ZNSwapV047(cls,@selector(zn44_importJSON:),@selector(zn47_importJSON:));
        ZNSwapV047(cls,@selector(makeUI:),@selector(zn47_makeUI:));
        ZNSwapV047(cls,@selector(tick:),@selector(zn47_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.7 manual UIDocumentPicker JSON import installed"];
    }
}
