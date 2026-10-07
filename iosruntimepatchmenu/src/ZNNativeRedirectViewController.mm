#import "ZNNativeRedirectViewController.h"

#import "ZNNativeRedirectAction.h"
#import "ZNNativeRedirectRuntime.h"

#include <errno.h>
#include <stdlib.h>

@interface ZNNativeRedirectViewController ()
@property(nonatomic,copy) NSDictionary<NSString *,id> *candidate;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UITextField *targetImageField;
@property(nonatomic,strong) UITextField *targetRVAField;
@property(nonatomic,strong) UISegmentedControl *kindControl;
@property(nonatomic,strong) UITextField *titleField;
@property(nonatomic,strong) UITextField *descriptionField;
@property(nonatomic,strong) UISegmentedControl *controlType;
@property(nonatomic,strong) UILabel *statusLabel;
@property(nonatomic,strong) UILabel *bytesLabel;
@end

@implementation ZNNativeRedirectViewController

- (instancetype)initWithCandidate:(NSDictionary<NSString *,id> *)candidate {
    self=[super init];
    if(self){_candidate=[candidate copy]?:@{};self.title=@"Native Redirect";}
    return self;
}

static NSString * const kZNRDVCDraftDefaults=@"zonoe.native-redirect.drafts.v1";

static uint64_t ZNRDVCParseRVA(NSString *text) {
    NSString *s=[text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!s.length)return 0;
    errno=0;char *end=NULL;
    unsigned long long v=strtoull(s.UTF8String,&end,0);
    if(errno||end==s.UTF8String||(end&&*end)){
        errno=0;end=NULL;v=strtoull(s.UTF8String,&end,16);
    }
    return (!errno&&end!=s.UTF8String&&(!end||!*end))?(uint64_t)v:0;
}

- (uint64_t)sourceRVA {
    for(NSString *key in @[@"methodRVA",@"rva"]){
        id value=self.candidate[key];
        if([value respondsToSelector:@selector(unsignedLongLongValue)]){
            uint64_t r=[value unsignedLongLongValue];if(r)return r;
        }
    }
    return ZNRDVCParseRVA([self.candidate[@"rvaText"] isKindOfClass:NSString.class]?self.candidate[@"rvaText"]:@"");
}
- (NSString *)sourceImage {
    NSString *image=[self.candidate[@"target"] isKindOfClass:NSString.class]?self.candidate[@"target"]:@"";
    return image.length?image:@"UnityFramework";
}
- (UILabel *)label:(NSString *)text font:(CGFloat)size {
    UILabel *l=[UILabel new];l.text=text;l.font=[UIFont systemFontOfSize:size];l.textColor=UIColor.labelColor;l.numberOfLines=0;return l;
}
- (UITextField *)field:(NSString *)placeholder {
    UITextField *f=[UITextField new];f.borderStyle=UITextBorderStyleRoundedRect;f.placeholder=placeholder;
    f.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];f.autocorrectionType=UITextAutocorrectionTypeNo;
    f.autocapitalizationType=UITextAutocapitalizationTypeNone;
    f.returnKeyType=UIReturnKeyDone;
    [f addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged|UIControlEventEditingDidEnd];
    [f addTarget:self action:@selector(fieldDone:) forControlEvents:UIControlEventEditingDidEndOnExit];
    return f;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    b.layer.cornerRadius=7;b.layer.borderWidth=1;b.layer.borderColor=UIColor.separatorColor.CGColor;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closePage:)];
    self.scroll=[UIScrollView new];self.scroll.frame=self.view.bounds;self.scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scroll];

    CGFloat w=MAX(300,CGRectGetWidth(self.view.bounds)-24),x=12,y=14;
    UILabel *sourceTitle=[self label:@"Source" font:15];sourceTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];sourceTitle.frame=CGRectMake(x,y,w,22);[self.scroll addSubview:sourceTitle];y+=26;
    NSString *owner=[self.candidate[@"class"] isKindOfClass:NSString.class]?self.candidate[@"class"]:@"";
    NSString *method=[self.candidate[@"method"] isKindOfClass:NSString.class]?self.candidate[@"method"]:@"";
    UILabel *source=[self label:[NSString stringWithFormat:@"%@\n%@::%@/%@\nRVA 0x%llX",
                                 self.sourceImage,owner,method,self.candidate[@"argumentCount"]?:@0,(unsigned long long)self.sourceRVA] font:11];
    source.frame=CGRectMake(x,y,w,58);source.lineBreakMode=NSLineBreakByCharWrapping;[self.scroll addSubview:source];y+=68;

    UILabel *targetTitle=[self label:@"Redirect Target" font:15];targetTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];targetTitle.frame=CGRectMake(x,y,w,22);[self.scroll addSubview:targetTitle];y+=28;
    self.targetImageField=[self field:@"Target Image"];self.targetImageField.text=self.sourceImage;self.targetImageField.frame=CGRectMake(x,y,w,36);[self.scroll addSubview:self.targetImageField];y+=44;
    self.targetRVAField=[self field:@"Target RVA，例如 0x3099CF8"];self.targetRVAField.keyboardType=UIKeyboardTypeNumbersAndPunctuation;self.targetRVAField.frame=CGRectMake(x,y,w,36);[self.scroll addSubview:self.targetRVAField];y+=44;

    self.kindControl=[[UISegmentedControl alloc]initWithItems:@[@"Function Redirect",@"B",@"BL"]];
    self.kindControl.selectedSegmentIndex=0;self.kindControl.frame=CGRectMake(x,y,w,32);
    [self.kindControl addTarget:self action:@selector(draftControlChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scroll addSubview:self.kindControl];y+=42;

    self.bytesLabel=[self label:@"Original：尚未读取\nStrategy：Function Redirect 使用 Dobby；B/BL 需 ±128MB" font:10];
    self.bytesLabel.frame=CGRectMake(x,y,w,42);self.bytesLabel.lineBreakMode=NSLineBreakByCharWrapping;[self.scroll addSubview:self.bytesLabel];y+=50;

    CGFloat gap=7,bw=(w-gap*2)/3.0;
    UIButton *test=[self button:@"测试 Redirect" action:@selector(testRedirect:)];test.frame=CGRectMake(x,y,bw,36);[self.scroll addSubview:test];
    UIButton *restore=[self button:@"恢复" action:@selector(restoreRedirect:)];restore.frame=CGRectMake(x+bw+gap,y,bw,36);[self.scroll addSubview:restore];
    UIButton *reload=[self button:@"重新读取" action:@selector(reloadBytes:)];reload.frame=CGRectMake(x+(bw+gap)*2,y,bw,36);[self.scroll addSubview:reload];y+=50;

    UILabel *createTitle=[self label:@"Create Method" font:15];createTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];createTitle.frame=CGRectMake(x,y,w,22);[self.scroll addSubview:createTitle];y+=28;
    self.titleField=[self field:@"名称"];self.titleField.text=method.length?[NSString stringWithFormat:@"%@ Redirect",method]:@"Native Redirect";self.titleField.frame=CGRectMake(x,y,w,36);[self.scroll addSubview:self.titleField];y+=44;
    self.descriptionField=[self field:@"说明"];self.descriptionField.frame=CGRectMake(x,y,w,36);[self.scroll addSubview:self.descriptionField];y+=44;
    self.controlType=[[UISegmentedControl alloc]initWithItems:@[@"Switch",@"Button"]];self.controlType.selectedSegmentIndex=0;self.controlType.frame=CGRectMake(x,y,w,32);
    [self.controlType addTarget:self action:@selector(draftControlChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scroll addSubview:self.controlType];y+=42;
    UIButton *create=[self button:@"Create Redirect Method" action:@selector(createRedirect:)];create.frame=CGRectMake(x,y,w,38);[self.scroll addSubview:create];y+=52;

    UILabel *statusTitle=[self label:@"Status" font:15];statusTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];statusTitle.frame=CGRectMake(x,y,w,22);[self.scroll addSubview:statusTitle];y+=28;
    self.statusLabel=[self label:@"Source：READY\nTarget：等待输入\nRuntime Test：IDLE\nBuild：等待创建" font:10.5];
    self.statusLabel.lineBreakMode=NSLineBreakByCharWrapping;self.statusLabel.frame=CGRectMake(x,y,w,120);[self.scroll addSubview:self.statusLabel];y+=132;
    self.scroll.contentSize=CGSizeMake(CGRectGetWidth(self.view.bounds),y);
    [self restoreDraft];
    [self refreshRuntimeStatus];
    [self reloadBytes:nil];
}

- (ZNNativeRedirectAction *)draftAction:(NSString **)error {
    uint64_t source=self.sourceRVA,target=ZNRDVCParseRVA(self.targetRVAField.text);
    if(!source||!target){if(error)*error=@"请填写有效 Source/Target RVA";return nil;}
    ZNNativeRedirectAction *a=[ZNNativeRedirectAction new];
    a.sourceImage=self.sourceImage;a.sourceRVA=source;
    NSString *targetImage=[self.targetImageField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    a.targetImage=targetImage.length?targetImage:self.sourceImage;a.targetRVA=target;
    a.kind=self.kindControl.selectedSegmentIndex==1?ZNNativeRedirectKindBranch:
           (self.kindControl.selectedSegmentIndex==2?ZNNativeRedirectKindBranchLink:ZNNativeRedirectKindFunction);
    a.title=self.titleField.text.length?self.titleField.text:@"Native Redirect";
    a.featureDescription=self.descriptionField.text?:@"";
    a.controlType=self.controlType.selectedSegmentIndex==1?@"button":@"switch";
    return a;
}
- (NSString *)draftKey {
    return [NSString stringWithFormat:@"%@+0x%llX",self.sourceImage,(unsigned long long)self.sourceRVA];
}
- (NSDictionary *)draftDictionary {
    return @{
        @"targetImage":self.targetImageField.text?:@"",
        @"targetRVA":self.targetRVAField.text?:@"",
        @"kind":@(MAX(0,self.kindControl.selectedSegmentIndex)),
        @"title":self.titleField.text?:@"",
        @"description":self.descriptionField.text?:@"",
        @"controlType":@(MAX(0,self.controlType.selectedSegmentIndex)),
    };
}
- (void)saveDraft {
    NSString *key=self.draftKey;if(!key.length)return;
    NSDictionary *all=[NSUserDefaults.standardUserDefaults dictionaryForKey:kZNRDVCDraftDefaults]?:@{};
    NSMutableDictionary *next=[all mutableCopy];
    next[key]=self.draftDictionary;
    [NSUserDefaults.standardUserDefaults setObject:next forKey:kZNRDVCDraftDefaults];
}
- (void)restoreDraft {
    NSDictionary *all=[NSUserDefaults.standardUserDefaults dictionaryForKey:kZNRDVCDraftDefaults];
    NSDictionary *draft=[all[self.draftKey] isKindOfClass:NSDictionary.class]?all[self.draftKey]:nil;
    if(!draft)return;
    NSString *targetImage=[draft[@"targetImage"] isKindOfClass:NSString.class]?draft[@"targetImage"]:@"";
    NSString *targetRVA=[draft[@"targetRVA"] isKindOfClass:NSString.class]?draft[@"targetRVA"]:@"";
    NSString *title=[draft[@"title"] isKindOfClass:NSString.class]?draft[@"title"]:@"";
    NSString *desc=[draft[@"description"] isKindOfClass:NSString.class]?draft[@"description"]:@"";
    if(targetImage.length)self.targetImageField.text=targetImage;
    self.targetRVAField.text=targetRVA;
    if(title.length)self.titleField.text=title;
    self.descriptionField.text=desc;
    NSInteger kind=[draft[@"kind"] integerValue];
    self.kindControl.selectedSegmentIndex=(kind>=0&&kind<3)?kind:0;
    NSInteger control=[draft[@"controlType"] integerValue];
    self.controlType.selectedSegmentIndex=(control>=0&&control<2)?control:0;
}
- (void)refreshRuntimeStatus {
    ZNNativeRedirectAction *installed=[[ZNNativeRedirectRuntime sharedRuntime]
        installedActionForSourceImage:self.sourceImage sourceRVA:self.sourceRVA];
    if(installed){
        [self setStatus:[NSString stringWithFormat:
            @"Source：READY\nTarget：READY\nRuntime Test：INSTALLED · %@\nBuild：%@",installed.canonicalIdentity,
            [ZNNativeRedirectStore sharedStore].actionsSnapshot.count?@"已有方法":@"可创建"]];
    }else{
        [self setStatus:@"Source：READY\nTarget：等待输入\nRuntime Test：IDLE\nBuild：等待创建"];
    }
}
- (void)setStatus:(NSString *)status {self.statusLabel.text=status?:@"";}
- (void)fieldChanged:(UITextField *)field {(void)field;[self saveDraft];}
- (void)fieldDone:(UITextField *)field {[field resignFirstResponder];[self saveDraft];}
- (void)draftControlChanged:(UISegmentedControl *)sender {(void)sender;[self saveDraft];}
- (void)closePage:(id)sender {(void)sender;[self.view endEditing:YES];[self saveDraft];[self dismissViewControllerAnimated:YES completion:nil];}

- (void)testRedirect:(id)sender {
    (void)sender;[self.view endEditing:YES];[self saveDraft];
    NSString *error=nil;ZNNativeRedirectAction *a=[self draftAction:&error];
    if(!a){[self setStatus:error];return;}
    if([[ZNNativeRedirectRuntime sharedRuntime] installAction:a error:&error]){
        [self setStatus:[NSString stringWithFormat:@"Source：READY\nTarget：READY\nRuntime Test：%@\nBuild：可创建",
                         [ZNNativeRedirectRuntime sharedRuntime].lastStatus]];
    }else [self setStatus:error?:@"Native Redirect 测试失败"];
    [self reloadBytes:nil];
}
- (void)restoreRedirect:(id)sender {
    (void)sender;[self.view endEditing:YES];[self saveDraft];
    NSString *error=nil;
    BOOL ok=[[ZNNativeRedirectRuntime sharedRuntime]
        restoreInstalledForSourceImage:self.sourceImage sourceRVA:self.sourceRVA error:&error];
    [self setStatus:ok?@"Runtime Test：RESTORED\nBuild：未改变":(error?:@"恢复失败")];
    [self reloadBytes:nil];
}
- (void)reloadBytes:(id)sender {
    (void)sender;NSString *error=nil;ZNNativeRedirectAction *a=[self draftAction:nil];
    if(!a){a=[ZNNativeRedirectAction new];a.sourceImage=self.sourceImage;a.sourceRVA=self.sourceRVA;}
    NSData *data=[[ZNNativeRedirectRuntime sharedRuntime] currentBytesForAction:a count:8 error:&error];
    if(!data){self.bytesLabel.text=error?:@"Original：读取失败";return;}
    const uint8_t *p=(const uint8_t *)data.bytes;NSMutableString *hex=[NSMutableString string];
    for(NSUInteger i=0;i<data.length;i++){if(i)[hex appendString:@" "];[hex appendFormat:@"%02X",p[i]];}
    self.bytesLabel.text=[NSString stringWithFormat:@"Current：%@\nStrategy：Function Redirect=Dobby；B/BL=direct branch",hex];
}
- (void)createRedirect:(id)sender {
    (void)sender;[self.view endEditing:YES];[self saveDraft];
    NSString *error=nil;ZNNativeRedirectAction *a=[self draftAction:&error];
    if(!a){[self setStatus:error];return;}
    ZNNativeRedirectAction *created=[[ZNNativeRedirectStore sharedStore]
        addSourceImage:a.sourceImage sourceRVA:a.sourceRVA targetImage:a.targetImage targetRVA:a.targetRVA
        kind:a.kind title:a.title featureDescription:a.featureDescription controlType:a.controlType error:&error];
    [self setStatus:created?[NSString stringWithFormat:@"CREATED\n%@\nBuild：READY",created.canonicalIdentity]:(error?:@"创建 Native Redirect 失败")];
}

@end
