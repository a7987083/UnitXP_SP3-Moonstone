#include "ZonoeRuntimeMenuV045.mm"
#import "ZNBinaryPatchWorkspace.h"
#import "ZNPatchJSONImporter.h"

// v0.4.8 JSON import layer.
// Primary path: scan only the immediate directory that contains developer file
// `1`, regardless of JSON filename. If exactly one JSON contains recognizable
// Patch entries, import it automatically. Manual document picker remains a
// fallback and reads the selected URL through coordinated security-scoped I/O.

static UIViewController *ZN48TopViewController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented=vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZN48TopViewController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top=((UINavigationController *)vc).visibleViewController;
        return top?ZN48TopViewController(top):vc;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *sel=((UITabBarController *)vc).selectedViewController;
        return sel?ZN48TopViewController(sel):vc;
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        UIViewController *last=((UISplitViewController *)vc).viewControllers.lastObject;
        return last?ZN48TopViewController(last):vc;
    }
    return vc;
}

static void ZN48RelabelJSONList(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *l=(UILabel *)view;
        if ([l.text hasPrefix:@"Application Support JSON"]) {
            l.text=[l.text stringByReplacingOccurrencesOfString:@"Application Support JSON" withString:@"与 1 同目录 JSON"];
        }
    }
    for (UIView *sub in view.subviews) ZN48RelabelJSONList(sub);
}

@interface ZNRuntimeMenuControllerV040 (V048) <UIDocumentPickerDelegate>
- (void)zn48_importJSON:(id)sender;
- (void)zn48_presentManualPicker;
- (void)zn48_renderOther;
- (void)zn48_makeUI:(UIWindow *)window;
- (void)zn48_tick:(NSTimer *)timer;
@end

@implementation ZNRuntimeMenuControllerV040 (V048)

- (void)zn48_presentManualPicker {
    NSArray<NSString *> *types=@[@"public.json",@"public.text",@"public.data"];
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initWithDocumentTypes:types inMode:UIDocumentPickerModeOpen];
    picker.delegate=(id<UIDocumentPickerDelegate>)self;
    picker.allowsMultipleSelection=NO;
    picker.modalPresentationStyle=UIModalPresentationFormSheet;

    UIWindow *window=self.hostWindow;
    if (!window) window=UIApplication.sharedApplication.keyWindow;
    UIViewController *presenter=ZN48TopViewController(window.rootViewController);
    if (!presenter) {
        ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
        ws.lastStatus=@"手动导入失败：找不到可用于弹出文件选择器的 ViewController";
        [self renderPage];
        return;
    }
    [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)zn48_importJSON:(id)sender {
    (void)sender;
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
    if (ws.hasAnyApplied || ws.isBuilding) return;
    [self.hostWindow endEditing:YES];

    if (ws.showJSONFiles) {
        ws.showJSONFiles=NO;
        [self renderPage];
        return;
    }

    [ws refreshJSONFiles];
    NSArray<NSString *> *all=ws.jsonFiles;
    NSMutableArray<NSString *> *valid=[NSMutableArray array];
    NSMutableArray<NSString *> *invalid=[NSMutableArray array];

    for (NSString *path in all) {
        NSString *probeError=nil;
        NSArray *items=[ZNPatchJSONImporter importFile:path error:&probeError];
        if (items.count) [valid addObject:path];
        else [invalid addObject:[NSString stringWithFormat:@"%@：%@",path.lastPathComponent,probeError?:@"非 Patch JSON"]];
    }

    if (valid.count==1) {
        NSString *path=valid.firstObject;
        NSString *importError=nil;
        if ([ws importJSONAtPath:path error:&importError]) {
            ws.lastStatus=[NSString stringWithFormat:@"自动导入成功：%@ · Patch %lu · 同目录 JSON %lu",path.lastPathComponent,(unsigned long)ws.filledCount,(unsigned long)all.count];
        } else {
            ws.lastStatus=[NSString stringWithFormat:@"自动导入失败：%@",importError?:@"未知错误"];
        }
        ws.showJSONFiles=NO;
        [self renderPage];
        return;
    }

    if (valid.count>1) {
        ws.showJSONFiles=YES;
        ws.lastStatus=[NSString stringWithFormat:@"与 1 同目录发现 %lu 个 JSON，其中 %lu 个可识别 Patch；请选择",(unsigned long)all.count,(unsigned long)valid.count];
        [self renderPage];
        ZN48RelabelJSONList(self.contentView);
        return;
    }

    ws.showJSONFiles=NO;
    NSString *discovery=[ZNPatchJSONImporter discoveryStatus];
    if (all.count) {
        NSString *detail=invalid.firstObject?:@"没有可识别的 Patch JSON";
        ws.lastStatus=[NSString stringWithFormat:@"%@ · 未识别 Patch JSON · %@ · 打开手动选择",discovery,detail];
    } else {
        ws.lastStatus=[NSString stringWithFormat:@"%@ · 打开手动选择",discovery];
    }
    [self renderPage];
    [self zn48_presentManualPicker];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url=urls.firstObject;
    ZNBinaryPatchWorkspace *ws=[ZNBinaryPatchWorkspace sharedWorkspace];
    if (!url) {
        ws.lastStatus=@"手动导入失败：没有选择文件";
        [self renderPage];
        return;
    }

    NSString *name=url.lastPathComponent?:@"";
    if (![[name.pathExtension lowercaseString] isEqualToString:@"json"]) {
        ws.lastStatus=[NSString stringWithFormat:@"手动导入失败：%@ 不是 JSON 文件",name.length?name:@"所选文件"];
        [self renderPage];
        return;
    }

    BOOL scoped=[url startAccessingSecurityScopedResource];
    __block NSData *data=nil;
    __block NSError *readError=nil;
    NSError *coordError=nil;
    NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:url options:0 error:&coordError byAccessor:^(NSURL *newURL) {
        data=[NSData dataWithContentsOfURL:newURL options:0 error:&readError];
    }];
    if (scoped) [url stopAccessingSecurityScopedResource];

    if (!data.length) {
        NSError *e=readError?:coordError;
        ws.lastStatus=[NSString stringWithFormat:@"手动导入失败：文件读取失败 · %@",e.localizedDescription?:@"未知错误"];
        [self renderPage];
        return;
    }

    NSString *tmp=[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"znpatch-%@.json",NSUUID.UUID.UUIDString]];
    NSError *writeError=nil;
    if (![data writeToFile:tmp options:NSDataWritingAtomic error:&writeError]) {
        ws.lastStatus=[NSString stringWithFormat:@"手动导入失败：临时文件写入失败 · %@",writeError.localizedDescription?:@"未知错误"];
        [self renderPage];
        return;
    }

    NSString *importError=nil;
    BOOL ok=[ws importJSONAtPath:tmp error:&importError];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
    if (ok) {
        ws.lastStatus=[NSString stringWithFormat:@"手动导入成功：%@ · Patch %lu",name,(unsigned long)ws.filledCount];
    } else {
        ws.lastStatus=[NSString stringWithFormat:@"手动导入失败：%@",importError?:@"未知错误"];
    }
    ws.showJSONFiles=NO;
    [self renderPage];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
}

- (void)zn48_renderOther {
    [self zn48_renderOther];
    ZN48RelabelJSONList(self.contentView);
}

- (void)zn48_makeUI:(UIWindow *)window {
    [self zn48_makeUI:window];
    self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.8    Marker-Sibling Auto JSON + Manual Fallback    iOS %@",UIDevice.currentDevice.systemVersion];
}

- (void)zn48_tick:(NSTimer *)timer {
    [self zn48_tick:timer];
    if (self.uiReady) self.footerLabel.text=[NSString stringWithFormat:@"PatchCore 0.4.8    Marker-Sibling Auto JSON + Manual Fallback    iOS %@",UIDevice.currentDevice.systemVersion];
}

@end

static void ZNSwapV048(Class cls,SEL a,SEL b){
    Method x=class_getInstanceMethod(cls,a),y=class_getInstanceMethod(cls,b);
    if(x&&y) method_exchangeImplementations(x,y);
}

__attribute__((constructor(113))) static void ZNInstallV048JSONImport(void){
    @autoreleasepool {
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(!cls) return;
        ZNSwapV048(cls,@selector(zn44_importJSON:),@selector(zn48_importJSON:));
        ZNSwapV048(cls,@selector(zn44_renderOther),@selector(zn48_renderOther));
        ZNSwapV048(cls,@selector(makeUI:),@selector(zn48_makeUI:));
        ZNSwapV048(cls,@selector(tick:),@selector(zn48_tick:));
        [[ZNRuntimeLogger sharedLogger] log:@"[bootstrap][main] v0.4.8 marker-sibling auto JSON import + coordinated manual fallback installed"];
    }
}
