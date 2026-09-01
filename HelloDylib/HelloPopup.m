#import <UIKit/UIKit.h>

__attribute__((constructor))
static void hello_popup_init(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"你好"
            message:@"TaiYangShenDian Test Dylib"
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction actionWithTitle:@"确定"
            style:UIAlertActionStyleDefault
            handler:nil]];

        UIWindow *window = UIApplication.sharedApplication.keyWindow;
        UIViewController *vc = window.rootViewController;
        while (vc.presentedViewController)
            vc = vc.presentedViewController;

        [vc presentViewController:alert animated:YES completion:nil];
    });
}
