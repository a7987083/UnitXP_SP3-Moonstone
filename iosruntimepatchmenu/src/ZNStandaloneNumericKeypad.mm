#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "ZNPatchCore.h"

static const NSInteger kZNStandaloneNumberTagBase = 469000;
static const NSInteger kZNStandaloneNumberTagLimit = 469512;

@interface ZNStandaloneNumericKeypadController : UIViewController
@property(nonatomic,strong) UILabel *valueLabel;
@property(nonatomic,strong) NSMutableString *buffer;
@property(nonatomic,copy) void (^completion)(NSString *value, BOOL accepted);
@end

@implementation ZNStandaloneNumericKeypadController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:.52];

    CGFloat width = MIN(330.0, CGRectGetWidth(UIScreen.mainScreen.bounds)-28.0);
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0,0,width,360)];
    panel.center = self.view.center;
    panel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    panel.backgroundColor = [UIColor colorWithWhite:.08 alpha:.98];
    panel.layer.cornerRadius = 16;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:.16].CGColor;
    [self.view addSubview:panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16,12,width-32,24)];
    title.text = @"数值输入";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [panel addSubview:title];

    self.valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(16,42,width-32,48)];
    self.valueLabel.backgroundColor = [UIColor colorWithWhite:.14 alpha:1];
    self.valueLabel.textColor = UIColor.whiteColor;
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:22 weight:UIFontWeightMedium];
    self.valueLabel.layer.cornerRadius = 9;
    self.valueLabel.clipsToBounds = YES;
    [panel addSubview:self.valueLabel];

    NSArray<NSArray<NSString *> *> *rows = @[
        @[@"7",@"8",@"9",@"⌫"],
        @[@"4",@"5",@"6",@"清空"],
        @[@"1",@"2",@"3",@"-"],
        @[@"0",@"00",@".",@"取消"],
    ];
    CGFloat gap=7, left=16, top=102;
    CGFloat bw=(width-left*2-gap*3)/4.0, bh=44;
    NSInteger tag=100;
    for(NSUInteger r=0;r<rows.count;r++){
        for(NSUInteger c=0;c<rows[r].count;c++){
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
            button.frame=CGRectMake(left+c*(bw+gap),top+r*(bh+gap),bw,bh);
            [button setTitle:rows[r][c] forState:UIControlStateNormal];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            button.backgroundColor=[UIColor colorWithWhite:.17 alpha:1];
            button.layer.cornerRadius=9;
            button.tag=tag++;
            [button addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
            [panel addSubview:button];
        }
    }

    UIButton *ok=[UIButton buttonWithType:UIButtonTypeSystem];
    ok.frame=CGRectMake(16,top+4*(bh+gap)+2,width-32,46);
    [ok setTitle:@"确认" forState:UIControlStateNormal];
    [ok setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    ok.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    ok.backgroundColor=[UIColor colorWithRed:.24 green:.42 blue:.92 alpha:1];
    ok.layer.cornerRadius=10;
    [ok addTarget:self action:@selector(confirmTapped:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:ok];
}
- (void)setInitialValue:(NSString *)value {
    self.buffer=[NSMutableString stringWithString:value.length?value:@"0"];
    self.valueLabel.text=self.buffer;
}
- (void)keyTapped:(UIButton *)button {
    NSString *key=[button titleForState:UIControlStateNormal]?:@"";
    if([key isEqualToString:@"⌫"]){if(self.buffer.length)[self.buffer deleteCharactersInRange:NSMakeRange(self.buffer.length-1,1)];}
    else if([key isEqualToString:@"清空"]){[self.buffer setString:@""];}
    else if([key isEqualToString:@"取消"]){if(self.completion)self.completion(self.buffer?:@"",NO);return;}
    else if([key isEqualToString:@"-"]){if([self.buffer hasPrefix:@"-"])[self.buffer deleteCharactersInRange:NSMakeRange(0,1)];else [self.buffer insertString:@"-" atIndex:0];}
    else if([key isEqualToString:@"."]){if([self.buffer rangeOfString:@"."].location==NSNotFound)[self.buffer appendString:@"."];}
    else {
        if([self.buffer isEqualToString:@"0"])[self.buffer setString:key]; else [self.buffer appendString:key];
    }
    self.valueLabel.text=self.buffer.length?self.buffer:@"0";
}
- (void)confirmTapped:(id)sender {(void)sender;if(self.completion)self.completion(self.buffer.length?self.buffer:@"0",YES);}
@end

@interface ZNStandaloneNumericKeypad : NSObject
@property(nonatomic,strong) UIWindow *window;
+ (instancetype)shared;
- (void)presentFromField:(UITextField *)field;
@end
@implementation ZNStandaloneNumericKeypad
+ (instancetype)shared { static ZNStandaloneNumericKeypad *s; static dispatch_once_t once; dispatch_once(&once,^{s=[ZNStandaloneNumericKeypad new];}); return s; }
- (UIWindowScene *)activeScene {
    if(@available(iOS 13.0,*)){
        for(UIScene *scene in UIApplication.sharedApplication.connectedScenes){
            if([scene isKindOfClass:UIWindowScene.class] && scene.activationState==UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
        }
    }
    return nil;
}
- (void)dismiss {
    self.window.hidden=YES;
    self.window.rootViewController=nil;
    self.window=nil;
}
- (void)presentFromField:(UITextField *)field {
    [field resignFirstResponder];
    ZNStandaloneNumericKeypadController *vc=[ZNStandaloneNumericKeypadController new];
    __weak typeof(self) weakSelf=self;
    __weak UITextField *weakField=field;
    vc.completion=^(NSString *value,BOOL accepted){
        UITextField *strongField=weakField;
        if(accepted&&strongField){
            strongField.text=value;
            [strongField sendActionsForControlEvents:UIControlEventEditingChanged];
            [strongField sendActionsForControlEvents:UIControlEventEditingDidEnd];
        }
        [weakSelf dismiss];
    };
    UIWindow *window=nil;
    if(@available(iOS 13.0,*)){
        UIWindowScene *scene=[self activeScene];
        if(scene)window=[[UIWindow alloc]initWithWindowScene:scene];
    }
    if(!window)window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];
    window.frame=UIScreen.mainScreen.bounds;
    window.windowLevel=UIWindowLevelAlert+80;
    window.rootViewController=vc;
    window.hidden=NO;
    [window makeKeyAndVisible];
    self.window=window;
    [vc setInitialValue:field.text?:@"0"];
}
@end

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end
@interface ZNRuntimeMenuControllerV040 (ZNStandaloneNumericKeypadBinding)
- (void)znsk_renderFull;
- (void)znsk_renderCompact;
- (void)znsk_numberBegin:(UITextField *)field;
@end
@implementation ZNRuntimeMenuControllerV040 (ZNStandaloneNumericKeypadBinding)
- (void)znsk_bindFields {
    NSMutableArray<UIView *> *stack=[NSMutableArray arrayWithObject:self.contentView];
    while(stack.count){
        UIView *view=stack.lastObject;[stack removeLastObject];[stack addObjectsFromArray:view.subviews];
        if(![view isKindOfClass:UITextField.class])continue;
        UITextField *field=(UITextField *)view;
        if(field.tag<kZNStandaloneNumberTagBase||field.tag>=kZNStandaloneNumberTagLimit)continue;
        field.inputView=[[UIView alloc]initWithFrame:CGRectMake(0,0,1,1)];
        [field removeTarget:self action:@selector(znsk_numberBegin:) forControlEvents:UIControlEventEditingDidBegin];
        [field addTarget:self action:@selector(znsk_numberBegin:) forControlEvents:UIControlEventEditingDidBegin];
    }
}
- (void)znsk_renderFull {[self znsk_renderFull];[self znsk_bindFields];}
- (void)znsk_renderCompact {[self znsk_renderCompact];[self znsk_bindFields];}
- (void)znsk_numberBegin:(UITextField *)field {[[ZNStandaloneNumericKeypad shared] presentFromField:field];}
@end

static void ZNSKSwap(Class cls,SEL original,SEL replacement){Method a=class_getInstanceMethod(cls,original),b=class_getInstanceMethod(cls,replacement);if(a&&b)method_exchangeImplementations(a,b);}
extern "C" void ZNInstallStandaloneNumericKeypadDeferred(void){
    static dispatch_once_t once;dispatch_once(&once,^{
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");if(!cls)return;
        ZNSKSwap(cls,@selector(zn50_renderFeatureGroupsFull),@selector(znsk_renderFull));
        ZNSKSwap(cls,@selector(zn50_renderFeatureGroupsCompact),@selector(znsk_renderCompact));
        [[ZNRuntimeLogger sharedLogger]log:@"[m5.12-keypad] standalone numeric keypad installed; system keyboard disabled for ordinary Number controls"];
    });
}
