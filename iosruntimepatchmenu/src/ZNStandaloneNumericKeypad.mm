#import "ZNInputService.h"
#import <objc/runtime.h>
#import "ZNPatchCore.h"

static const NSInteger kZNStandaloneNumberTagBase = 469000;
static const NSInteger kZNStandaloneNumberTagLimit = 469512;

static const void *kZNInputOverlayKey = &kZNInputOverlayKey;
static const void *kZNInputFieldKey = &kZNInputFieldKey;
static const void *kZNInputModeKey = &kZNInputModeKey;

static UIViewController *ZNInputTopController(UIViewController *vc) {
    if (!vc) return nil;
    UIViewController *presented = vc.presentedViewController;
    if (presented && !presented.isBeingDismissed) return ZNInputTopController(presented);
    if ([vc isKindOfClass:UINavigationController.class]) {
        UIViewController *top = ((UINavigationController *)vc).visibleViewController;
        return top ? ZNInputTopController(top) : vc;
    }
    if ([vc isKindOfClass:UITabBarController.class]) {
        UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
        return selected ? ZNInputTopController(selected) : vc;
    }
    if ([vc isKindOfClass:UISplitViewController.class]) {
        UIViewController *last = ((UISplitViewController *)vc).viewControllers.lastObject;
        return last ? ZNInputTopController(last) : vc;
    }
    return vc;
}

static NSString *ZNInputModeName(ZNInputMode mode) {
    switch (mode) {
        case ZNInputModeInteger: return @"整数输入";
        case ZNInputModeDecimal: return @"数值输入";
        case ZNInputModeHexAddress: return @"Offset / Address";
        case ZNInputModeHexBytes: return @"Patch HEX";
        case ZNInputModeNumericFlexible: return @"Runtime 参数";
        default: return @"文本输入";
    }
}

@interface ZNStandaloneNumericKeypadController : UIViewController
@property(nonatomic,strong) UILabel *valueLabel;
@property(nonatomic,strong) NSMutableString *buffer;
@property(nonatomic,assign) ZNInputMode mode;
@property(nonatomic,copy) void (^completion)(NSString *value, BOOL accepted);
@end

@implementation ZNStandaloneNumericKeypadController

- (NSArray<NSArray<NSString *> *> *)rowsForMode {
    if (self.mode == ZNInputModeHexAddress) {
        return @[
            @[@"A",@"B",@"C",@"D"],
            @[@"E",@"F",@"x",@"⌫"],
            @[@"7",@"8",@"9",@"清空"],
            @[@"4",@"5",@"6",@"取消"],
            @[@"1",@"2",@"3",@"0"],
        ];
    }
    if (self.mode == ZNInputModeHexBytes) {
        return @[
            @[@"A",@"B",@"C",@"D"],
            @[@"E",@"F",@"⌫",@"清空"],
            @[@"7",@"8",@"9",@"取消"],
            @[@"4",@"5",@"6",@"00"],
            @[@"1",@"2",@"3",@"0"],
        ];
    }
    if (self.mode == ZNInputModeInteger) {
        return @[
            @[@"7",@"8",@"9",@"⌫"],
            @[@"4",@"5",@"6",@"清空"],
            @[@"1",@"2",@"3",@"-"],
            @[@"0",@"00",@"取消",@"确认"],
        ];
    }
    if (self.mode == ZNInputModeNumericFlexible) {
        return @[
            @[@"A",@"B",@"C",@"D"],
            @[@"E",@"F",@"x",@"⌫"],
            @[@"7",@"8",@"9",@"清空"],
            @[@"4",@"5",@"6",@"-"],
            @[@"1",@"2",@"3",@"."],
            @[@"0",@"00",@"取消",@"确认"],
        ];
    }
    return @[
        @[@"7",@"8",@"9",@"⌫"],
        @[@"4",@"5",@"6",@"清空"],
        @[@"1",@"2",@"3",@"-"],
        @[@"0",@"00",@".",@"取消"],
    ];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:.52];

    NSArray *rows = [self rowsForMode];
    CGFloat width = MIN(336.0, CGRectGetWidth(UIScreen.mainScreen.bounds)-24.0);
    CGFloat gap = 7.0, left = 16.0, bh = 44.0, top = 102.0;
    CGFloat panelH = top + rows.count * (bh + gap) + 64.0;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0,0,width,panelH)];
    panel.center = self.view.center;
    panel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    panel.backgroundColor = [UIColor colorWithWhite:.08 alpha:.98];
    panel.layer.cornerRadius = 16;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:.16].CGColor;
    [self.view addSubview:panel];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16,12,width-32,24)];
    title.text = ZNInputModeName(self.mode);
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [panel addSubview:title];

    self.valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(16,42,width-32,48)];
    self.valueLabel.backgroundColor = [UIColor colorWithWhite:.14 alpha:1];
    self.valueLabel.textColor = UIColor.whiteColor;
    self.valueLabel.textAlignment = NSTextAlignmentRight;
    self.valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:21 weight:UIFontWeightMedium];
    self.valueLabel.layer.cornerRadius = 9;
    self.valueLabel.clipsToBounds = YES;
    self.valueLabel.adjustsFontSizeToFitWidth = YES;
    self.valueLabel.minimumScaleFactor = .55;
    [panel addSubview:self.valueLabel];

    CGFloat bw=(width-left*2-gap*3)/4.0;
    for(NSUInteger r=0;r<rows.count;r++){
        NSArray<NSString *> *row=rows[r];
        for(NSUInteger c=0;c<row.count;c++){
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
            button.frame=CGRectMake(left+c*(bw+gap),top+r*(bh+gap),bw,bh);
            NSString *key=row[c];
            [button setTitle:key forState:UIControlStateNormal];
            [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            button.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            button.backgroundColor=[UIColor colorWithWhite:.17 alpha:1];
            button.layer.cornerRadius=9;
            [button addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
            [panel addSubview:button];
        }
    }

    BOOL rowsContainConfirm = NO;
    for (NSArray<NSString *> *row in rows) if ([row containsObject:@"确认"]) rowsContainConfirm = YES;
    if (!rowsContainConfirm) {
        UIButton *ok=[UIButton buttonWithType:UIButtonTypeSystem];
        ok.frame=CGRectMake(16,top+rows.count*(bh+gap)+2,width-32,46);
        [ok setTitle:@"确认" forState:UIControlStateNormal];
        [ok setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        ok.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        ok.backgroundColor=[UIColor colorWithRed:.24 green:.42 blue:.92 alpha:1];
        ok.layer.cornerRadius=10;
        [ok addTarget:self action:@selector(confirmTapped:) forControlEvents:UIControlEventTouchUpInside];
        [panel addSubview:ok];
    }
}

- (void)setInitialValue:(NSString *)value {
    self.buffer=[NSMutableString stringWithString:value.length?value:@"0"];
    self.valueLabel.text=self.buffer;
}

- (void)finishAccepted:(BOOL)accepted {
    if(self.completion) self.completion(self.buffer.length?self.buffer:@"0",accepted);
}

- (void)keyTapped:(UIButton *)button {
    NSString *key=[button titleForState:UIControlStateNormal]?:@"";
    if([key isEqualToString:@"确认"]){[self finishAccepted:YES];return;}
    if([key isEqualToString:@"取消"]){[self finishAccepted:NO];return;}
    if([key isEqualToString:@"⌫"]){
        if(self.buffer.length)[self.buffer deleteCharactersInRange:NSMakeRange(self.buffer.length-1,1)];
    } else if([key isEqualToString:@"清空"]){
        [self.buffer setString:@""];
    } else if([key isEqualToString:@"-"]){
        if([self.buffer hasPrefix:@"-"])[self.buffer deleteCharactersInRange:NSMakeRange(0,1)];
        else [self.buffer insertString:@"-" atIndex:0];
    } else if([key isEqualToString:@"."]){
        if([self.buffer rangeOfString:@"."].location==NSNotFound)[self.buffer appendString:@"."];
    } else if([key isEqualToString:@"x"]){
        if(![self.buffer.lowercaseString hasPrefix:@"0x"]){
            if([self.buffer isEqualToString:@"0"]) [self.buffer appendString:@"x"];
            else if(self.buffer.length==0) [self.buffer appendString:@"0x"];
        }
    } else {
        if([self.buffer isEqualToString:@"0"] && ![key isEqualToString:@"00"]) [self.buffer setString:key];
        else [self.buffer appendString:key];
    }
    self.valueLabel.text=self.buffer.length?self.buffer:@"0";
}

- (void)confirmTapped:(id)sender {(void)sender;[self finishAccepted:YES];}
@end

@interface ZNKeyboardService : NSObject
@property(nonatomic,weak) UITextField *activeField;
@property(nonatomic,assign) BOOL keyboardVisible;
@property(nonatomic,assign) NSInteger recoveryBudget;
+ (instancetype)shared;
- (void)bindSystemField:(UITextField *)field;
@end

@implementation ZNKeyboardService
+ (instancetype)shared {
    static ZNKeyboardService *s; static dispatch_once_t once;
    dispatch_once(&once,^{s=[ZNKeyboardService new];[s installObservers];});
    return s;
}
- (void)installObservers {
    NSNotificationCenter *nc=NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(willShow:) name:UIKeyboardWillShowNotification object:nil];
    [nc addObserver:self selector:@selector(didShow:) name:UIKeyboardDidShowNotification object:nil];
    [nc addObserver:self selector:@selector(willHide:) name:UIKeyboardWillHideNotification object:nil];
    [nc addObserver:self selector:@selector(didHide:) name:UIKeyboardDidHideNotification object:nil];
}
- (void)bindSystemField:(UITextField *)field {
    [field removeTarget:self action:@selector(begin:) forControlEvents:UIControlEventEditingDidBegin];
    [field removeTarget:self action:@selector(end:) forControlEvents:UIControlEventEditingDidEnd];
    [field addTarget:self action:@selector(begin:) forControlEvents:UIControlEventEditingDidBegin];
    [field addTarget:self action:@selector(end:) forControlEvents:UIControlEventEditingDidEnd];
}
- (void)begin:(UITextField *)field {
    self.activeField=field;
    self.recoveryBudget=2;
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.13-input] system begin tag=%ld responder=%d",(long)field.tag,field.isFirstResponder]];
}
- (void)end:(UITextField *)field {
    [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.13-input] system end tag=%ld keyboard=%d",(long)field.tag,self.keyboardVisible]];
}
- (void)willShow:(NSNotification *)note {
    (void)note; self.keyboardVisible=YES;
    [[ZNRuntimeLogger sharedLogger] log:@"[m5.13-input] keyboard willShow"];
}
- (void)didShow:(NSNotification *)note {
    (void)note; self.keyboardVisible=YES;
    [[ZNRuntimeLogger sharedLogger] log:@"[m5.13-input] keyboard didShow"];
    [self recoverIfNeededAfter:0.05];
    [self recoverIfNeededAfter:0.15];
}
- (void)willHide:(NSNotification *)note {
    (void)note; self.keyboardVisible=NO;
    [[ZNRuntimeLogger sharedLogger] log:@"[m5.13-input] keyboard willHide"];
}
- (void)didHide:(NSNotification *)note {
    (void)note; self.keyboardVisible=NO; self.activeField=nil; self.recoveryBudget=0;
    [[ZNRuntimeLogger sharedLogger] log:@"[m5.13-input] keyboard didHide"];
}
- (void)recoverIfNeededAfter:(NSTimeInterval)delay {
    __weak typeof(self) weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        ZNKeyboardService *self=weakSelf;
        UITextField *field=self.activeField;
        if(!self || !self.keyboardVisible || !field || !field.window || field.hidden || !field.enabled) return;
        if(field.isFirstResponder || self.recoveryBudget<=0) return;
        self.recoveryBudget--;
        BOOL ok=[field becomeFirstResponder];
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.13-input] responder recovery tag=%ld ok=%d remaining=%ld",(long)field.tag,ok,(long)self.recoveryBudget]];
    });
}
@end

@interface ZNInputService : NSObject
@property(nonatomic,weak) UIViewController *presentedPad;
+ (instancetype)shared;
- (void)openCustomField:(UIButton *)sender;
@end

@implementation ZNInputService
+ (instancetype)shared { static ZNInputService *s; static dispatch_once_t once; dispatch_once(&once,^{s=[ZNInputService new];}); return s; }

- (void)openCustomField:(UIButton *)sender {
    UITextField *field=objc_getAssociatedObject(sender,kZNInputFieldKey);
    NSNumber *modeBox=objc_getAssociatedObject(sender,kZNInputModeKey);
    if(!field || !field.enabled || !field.window) return;
    [field resignFirstResponder];

    UIViewController *presenter=ZNInputTopController(field.window.rootViewController);
    if(!presenter || presenter.isBeingDismissed || presenter.presentedViewController) {
        presenter=ZNInputTopController(field.window.rootViewController);
    }
    if(!presenter) return;

    ZNStandaloneNumericKeypadController *vc=[ZNStandaloneNumericKeypadController new];
    vc.mode=(ZNInputMode)modeBox.integerValue;
    vc.modalPresentationStyle=UIModalPresentationOverFullScreen;
    vc.modalTransitionStyle=UIModalTransitionStyleCrossDissolve;
    __weak UITextField *weakField=field;
    __weak UIViewController *weakVC=vc;
    ZNInputMode modeValue=vc.mode;
    vc.completion=^(NSString *value,BOOL accepted){
        UITextField *strongField=weakField;
        if(accepted&&strongField){
            strongField.text=value;
            [strongField sendActionsForControlEvents:UIControlEventEditingChanged];
            [strongField sendActionsForControlEvents:UIControlEventEditingDidEnd];
            [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.13-input] custom commit tag=%ld mode=%ld",(long)strongField.tag,(long)modeValue]];
        }
        [weakVC dismissViewControllerAnimated:NO completion:nil];
    };
    [vc setInitialValue:field.text?:@"0"];
    self.presentedPad=vc;
    [presenter presentViewController:vc animated:NO completion:^{
        [[ZNRuntimeLogger sharedLogger] log:[NSString stringWithFormat:@"[m5.13-input] custom pad presented tag=%ld mode=%ld; no keyWindow/no firstResponder",(long)field.tag,(long)vc.mode]];
    }];
}
@end

void ZNInputServiceBindField(UITextField *field, ZNInputMode mode) {
    if(!field) return;
    if(mode==ZNInputModeSystemText){
        [[ZNKeyboardService shared] bindSystemField:field];
        return;
    }

    field.inputView=[[UIView alloc] initWithFrame:CGRectMake(0,0,1,1)];
    field.userInteractionEnabled=NO;

    UIButton *overlay=objc_getAssociatedObject(field,kZNInputOverlayKey);
    if(!overlay){
        overlay=[UIButton buttonWithType:UIButtonTypeCustom];
        overlay.backgroundColor=UIColor.clearColor;
        overlay.autoresizingMask=field.autoresizingMask;
        overlay.accessibilityLabel=field.placeholder.length?field.placeholder:@"ZonoPatch input";
        [overlay addTarget:[ZNInputService shared] action:@selector(openCustomField:) forControlEvents:UIControlEventTouchUpInside];
        objc_setAssociatedObject(field,kZNInputOverlayKey,overlay,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    overlay.frame=field.frame;
    overlay.enabled=field.enabled;
    objc_setAssociatedObject(overlay,kZNInputFieldKey,field,OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(overlay,kZNInputModeKey,@(mode),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(field.superview && overlay.superview!=field.superview){
        [overlay removeFromSuperview];
        [field.superview addSubview:overlay];
    }
    if(overlay.superview) [overlay.superview bringSubviewToFront:overlay];
}

@interface ZNRuntimeMenuControllerV040 : NSObject
@property(nonatomic,strong) UIView *contentView;
- (void)zn50_renderFeatureGroupsFull;
- (void)zn50_renderFeatureGroupsCompact;
@end

@interface ZNRuntimeMenuControllerV040 (ZNStandaloneNumericKeypadBinding)
- (void)znsk_renderFull;
- (void)znsk_renderCompact;
@end

@implementation ZNRuntimeMenuControllerV040 (ZNStandaloneNumericKeypadBinding)
- (void)znsk_bindFields {
    NSMutableArray<UIView *> *stack=[NSMutableArray arrayWithObject:self.contentView];
    while(stack.count){
        UIView *view=stack.lastObject;[stack removeLastObject];[stack addObjectsFromArray:view.subviews];
        if(![view isKindOfClass:UITextField.class])continue;
        UITextField *field=(UITextField *)view;
        if(field.tag>=kZNStandaloneNumberTagBase&&field.tag<kZNStandaloneNumberTagLimit){
            ZNInputServiceBindField(field,ZNInputModeDecimal);
        }
    }
}
- (void)znsk_renderFull {[self znsk_renderFull];[self znsk_bindFields];}
- (void)znsk_renderCompact {[self znsk_renderCompact];[self znsk_bindFields];}
@end

static void ZNSKSwap(Class cls,SEL original,SEL replacement){
    Method a=class_getInstanceMethod(cls,original),b=class_getInstanceMethod(cls,replacement);
    if(a&&b)method_exchangeImplementations(a,b);
}

extern "C" void ZNInstallStandaloneNumericKeypadDeferred(void){
    static dispatch_once_t once;
    dispatch_once(&once,^{
        [ZNKeyboardService shared];
        Class cls=NSClassFromString(@"ZNRuntimeMenuControllerV040");
        if(!cls)return;
        ZNSKSwap(cls,@selector(zn50_renderFeatureGroupsFull),@selector(znsk_renderFull));
        ZNSKSwap(cls,@selector(zn50_renderFeatureGroupsCompact),@selector(znsk_renderCompact));
        [[ZNRuntimeLogger sharedLogger]log:@"[m5.13-input] Input Service installed: modal custom pads + system keyboard responder service; no custom keyWindow"];
    });
}
