#import "ZNNativeRedirectViewController.h"

#import "ZNNativeRedirectAction.h"
#import "ZNNativeRedirectRuntime.h"
#import "ZNIL2CPPABIMetadata.h"
#import "ZNIL2CPPHybridFinder.h"
#import "ZNIL2CPPMethodFinderSearchV3.h"

static NSString * const kZNRDVCDraftDefaults=@"zonoe.method-redirect.drafts.v2";

@interface ZNNativeRedirectViewController ()
@property(nonatomic,copy) NSDictionary<NSString *,id> *candidate;
@property(nonatomic,copy) NSDictionary<NSString *,id> *targetCandidate;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UITextField *targetSearchField;
@property(nonatomic,strong) UILabel *targetSummaryLabel;
@property(nonatomic,strong) UITextField *titleField;
@property(nonatomic,strong) UITextField *descriptionField;
@property(nonatomic,strong) UISegmentedControl *controlType;
@property(nonatomic,strong) UILabel *statusLabel;
@end

@implementation ZNNativeRedirectViewController

- (instancetype)initWithCandidate:(NSDictionary<NSString *,id> *)candidate {
    self=[super init];
    if(self){_candidate=[candidate copy]?:@{};self.title=@"Method Redirect";}
    return self;
}

static NSString *ZNRDVCString(id value) {
    return [value isKindOfClass:NSString.class]?value:@"";
}
static NSString *ZNRDVCIdentity(NSDictionary *candidate) {
    NSString *assembly=ZNRDVCString(candidate[@"assembly"]);
    NSString *ns=ZNRDVCString(candidate[@"namespace"]);
    NSString *cls=ZNRDVCString(candidate[@"class"]);
    NSString *method=ZNRDVCString(candidate[@"method"]);
    NSUInteger argc=[candidate[@"argumentCount"] unsignedIntegerValue];
    NSString *owner=ns.length?[NSString stringWithFormat:@"%@.%@",ns,cls]:cls;
    return [NSString stringWithFormat:@"%@!%@::%@/%lu",assembly,owner,method,(unsigned long)argc];
}
static NSString *ZNRDVCABIText(NSDictionary *candidate) {
    NSDictionary *abi=ZNIL2CPPDescribeMethodABI(candidate);
    if(![abi[@"available"] boolValue])return ZNRDVCString(abi[@"reason"]);
    return ZNRDVCString(abi[@"signature"]);
}

- (UILabel *)label:(NSString *)text font:(CGFloat)size {
    UILabel *l=[UILabel new];l.text=text;l.font=[UIFont systemFontOfSize:size];l.textColor=UIColor.labelColor;
    l.numberOfLines=0;l.lineBreakMode=NSLineBreakByCharWrapping;return l;
}
- (UITextField *)field:(NSString *)placeholder {
    UITextField *f=[UITextField new];f.borderStyle=UITextBorderStyleRoundedRect;f.placeholder=placeholder;
    f.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];f.autocorrectionType=UITextAutocorrectionTypeNo;
    f.autocapitalizationType=UITextAutocapitalizationTypeNone;f.returnKeyType=UIReturnKeyDone;
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
- (NSString *)draftKey {
    return [NSString stringWithFormat:@"source:%@",ZNRDVCIdentity(self.candidate)];
}
- (NSDictionary *)draftDictionary {
    return @{
        @"targetExpression":self.targetSearchField.text?:@"",
        @"targetIdentity":self.targetCandidate?ZNRDVCIdentity(self.targetCandidate):@"",
        @"title":self.titleField.text?:@"",
        @"description":self.descriptionField.text?:@"",
        @"controlType":@(MAX(0,self.controlType.selectedSegmentIndex)),
    };
}
- (void)saveDraft {
    NSString *key=self.draftKey;if(!key.length)return;
    NSDictionary *all=[NSUserDefaults.standardUserDefaults dictionaryForKey:kZNRDVCDraftDefaults]?:@{};
    NSMutableDictionary *next=[all mutableCopy];next[key]=self.draftDictionary;
    [NSUserDefaults.standardUserDefaults setObject:next forKey:kZNRDVCDraftDefaults];
}
- (void)restoreDraft {
    NSDictionary *all=[NSUserDefaults.standardUserDefaults dictionaryForKey:kZNRDVCDraftDefaults];
    NSDictionary *draft=[all[self.draftKey] isKindOfClass:NSDictionary.class]?all[self.draftKey]:nil;
    if(!draft)return;
    NSString *expression=ZNRDVCString(draft[@"targetExpression"]);
    NSString *identity=ZNRDVCString(draft[@"targetIdentity"]);
    if(expression.length)self.targetSearchField.text=expression;
    NSString *title=ZNRDVCString(draft[@"title"]);if(title.length)self.titleField.text=title;
    self.descriptionField.text=ZNRDVCString(draft[@"description"]);
    NSInteger control=[draft[@"controlType"] integerValue];
    self.controlType.selectedSegmentIndex=(control>=0&&control<2)?control:0;

    NSString *query=identity.length?identity:expression;
    if(query.length){
        NSString *error=nil;
        NSArray *matches=[[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:query limit:16 error:&error];
        for(NSDictionary *c in matches?:@[]){
            if(!identity.length||[ZNRDVCIdentity(c) isEqualToString:identity]){self.targetCandidate=c;break;}
        }
    }
    [self refreshTargetSummary];
}
- (void)refreshTargetSummary {
    if(!self.targetCandidate){
        self.targetSummaryLabel.text=@"Target Method：未选择\n输入方法名、Class::Method 或完整方法身份后点“选择目标方法”。";
        return;
    }
    NSString *reason=nil;
    BOOL compatible=[[ZNNativeRedirectRuntime sharedRuntime] supportsSourceCandidate:self.candidate
                                                                    targetCandidate:self.targetCandidate
                                                                             reason:&reason];
    self.targetSummaryLabel.text=[NSString stringWithFormat:
        @"Target Method\n%@\n%@\nABI：%@%@",
        ZNRDVCIdentity(self.targetCandidate),
        ZNRDVCABIText(self.targetCandidate),
        compatible?@"COMPATIBLE":@"UNSUPPORTED",
        reason.length?[NSString stringWithFormat:@" · %@",reason]:@""];
}
- (void)refreshRuntimeStatus {
    ZNNativeRedirectAction *installed=[[ZNNativeRedirectRuntime sharedRuntime] installedActionForSourceCandidate:self.candidate];
    if(installed){
        self.statusLabel.text=[NSString stringWithFormat:
            @"Source：READY\nTarget：%@\nRuntime Test：INSTALLED\n%@",
            installed.targetIdentity,[ZNNativeRedirectRuntime sharedRuntime].lastStatus?:@""];
    }else{
        self.statusLabel.text=@"Source：READY\nTarget：等待选择\nRuntime Test：IDLE\nBuild：等待创建";
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closePage:)];

    self.scroll=[UIScrollView new];self.scroll.frame=self.view.bounds;
    self.scroll.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scroll];

    CGFloat w=MAX(300,CGRectGetWidth(self.view.bounds)-24),x=12,y=14;
    UILabel *sourceTitle=[self label:@"Source Method" font:15];
    sourceTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];sourceTitle.frame=CGRectMake(x,y,w,22);
    [self.scroll addSubview:sourceTitle];y+=26;

    UILabel *source=[self label:[NSString stringWithFormat:@"%@\n%@",ZNRDVCIdentity(self.candidate),ZNRDVCABIText(self.candidate)] font:10.5];
    source.frame=CGRectMake(x,y,w,66);[self.scroll addSubview:source];y+=74;

    UILabel *targetTitle=[self label:@"Target Method" font:15];
    targetTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];targetTitle.frame=CGRectMake(x,y,w,22);
    [self.scroll addSubview:targetTitle];y+=28;

    CGFloat chooseW=112,gap=7;
    self.targetSearchField=[self field:@"例如 AddGemCommand::Execute/0"];
    self.targetSearchField.frame=CGRectMake(x,y,w-chooseW-gap,36);[self.scroll addSubview:self.targetSearchField];
    UIButton *choose=[self button:@"选择目标方法" action:@selector(selectTargetMethod:)];
    choose.frame=CGRectMake(CGRectGetMaxX(self.targetSearchField.frame)+gap,y,chooseW,36);[self.scroll addSubview:choose];y+=44;

    self.targetSummaryLabel=[self label:@"Target Method：未选择" font:10.5];
    self.targetSummaryLabel.frame=CGRectMake(x,y,w,88);[self.scroll addSubview:self.targetSummaryLabel];y+=96;

    CGFloat bw=(w-gap)/2.0;
    UIButton *test=[self button:@"测试 Method Redirect" action:@selector(testRedirect:)];
    test.frame=CGRectMake(x,y,bw,36);[self.scroll addSubview:test];
    UIButton *restore=[self button:@"恢复" action:@selector(restoreRedirect:)];
    restore.frame=CGRectMake(x+bw+gap,y,bw,36);[self.scroll addSubview:restore];y+=50;

    UILabel *createTitle=[self label:@"Create Method Redirect" font:15];
    createTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];createTitle.frame=CGRectMake(x,y,w,22);
    [self.scroll addSubview:createTitle];y+=28;

    NSString *sourceMethod=ZNRDVCString(self.candidate[@"method"]);
    self.titleField=[self field:@"名称"];
    self.titleField.text=sourceMethod.length?[NSString stringWithFormat:@"%@ Redirect",sourceMethod]:@"Method Redirect";
    self.titleField.frame=CGRectMake(x,y,w,36);[self.scroll addSubview:self.titleField];y+=44;

    self.descriptionField=[self field:@"说明"];self.descriptionField.frame=CGRectMake(x,y,w,36);
    [self.scroll addSubview:self.descriptionField];y+=44;

    self.controlType=[[UISegmentedControl alloc]initWithItems:@[@"Switch",@"Button"]];
    self.controlType.selectedSegmentIndex=0;self.controlType.frame=CGRectMake(x,y,w,32);
    [self.controlType addTarget:self action:@selector(controlChanged:) forControlEvents:UIControlEventValueChanged];
    [self.scroll addSubview:self.controlType];y+=42;

    UIButton *create=[self button:@"Create Method Redirect" action:@selector(createRedirect:)];
    create.frame=CGRectMake(x,y,w,38);[self.scroll addSubview:create];y+=52;

    UILabel *statusTitle=[self label:@"Status" font:15];
    statusTitle.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];statusTitle.frame=CGRectMake(x,y,w,22);
    [self.scroll addSubview:statusTitle];y+=28;

    self.statusLabel=[self label:@"" font:10.5];self.statusLabel.frame=CGRectMake(x,y,w,130);
    [self.scroll addSubview:self.statusLabel];y+=142;
    self.scroll.contentSize=CGSizeMake(CGRectGetWidth(self.view.bounds),y);

    [self restoreDraft];
    [self refreshRuntimeStatus];
}

- (void)fieldChanged:(UITextField *)field {(void)field;[self saveDraft];}
- (void)fieldDone:(UITextField *)field {[field resignFirstResponder];[self saveDraft];}
- (void)controlChanged:(UISegmentedControl *)sender {(void)sender;[self saveDraft];}
- (void)closePage:(id)sender {
    (void)sender;[self.view endEditing:YES];[self saveDraft];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)selectTargetMethod:(UIButton *)sender {
    [self.view endEditing:YES];
    NSString *query=[self.targetSearchField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!query.length){self.statusLabel.text=@"请输入 Target 方法名或 Class::Method";return;}
    NSString *error=nil;
    NSArray<NSDictionary *> *matches=[[ZNIL2CPPHybridFinder sharedFinder] zn60_searchCandidates:query limit:32 error:&error];
    if(!matches.count){self.statusLabel.text=error?:@"没有找到 Target 方法";return;}

    UIAlertController *picker=[UIAlertController alertControllerWithTitle:@"选择 Target Method"
                                                                  message:[NSString stringWithFormat:@"找到 %lu 个候选",(unsigned long)matches.count]
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf=self;
    for(NSUInteger i=0;i<MIN(matches.count,(NSUInteger)20);i++){
        NSDictionary *candidate=matches[i];
        NSString *title=[NSString stringWithFormat:@"%@ · %@",ZNRDVCIdentity(candidate),ZNRDVCString(candidate[@"rvaText"])];
        [picker addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
            weakSelf.targetCandidate=candidate;
            weakSelf.targetSearchField.text=ZNRDVCIdentity(candidate);
            [weakSelf refreshTargetSummary];
            [weakSelf saveDraft];
        }]];
    }
    if(matches.count>20)picker.message=[picker.message stringByAppendingString:@"\n仅显示前 20 个，请缩小搜索条件。"];
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover=picker.popoverPresentationController;
    if(popover){popover.sourceView=sender;popover.sourceRect=sender.bounds;}
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)testRedirect:(id)sender {
    (void)sender;[self.view endEditing:YES];[self saveDraft];
    if(!self.targetCandidate){self.statusLabel.text=@"请先选择 Target Method";return;}
    NSString *error=nil;
    BOOL ok=[[ZNNativeRedirectRuntime sharedRuntime] installSourceCandidate:self.candidate
                                                            targetCandidate:self.targetCandidate
                                                                      error:&error];
    self.statusLabel.text=ok
        ? [NSString stringWithFormat:@"Runtime Test：INSTALLED\n%@",[ZNNativeRedirectRuntime sharedRuntime].lastStatus]
        : (error?:@"Method Redirect 测试失败");
}

- (void)restoreRedirect:(id)sender {
    (void)sender;[self.view endEditing:YES];[self saveDraft];
    NSString *error=nil;
    BOOL ok=[[ZNNativeRedirectRuntime sharedRuntime] restoreSourceCandidate:self.candidate error:&error];
    self.statusLabel.text=ok?@"Runtime Test：RESTORED\nSource 已恢复原方法":(error?:@"恢复失败");
}

- (void)createRedirect:(id)sender {
    (void)sender;[self.view endEditing:YES];[self saveDraft];
    if(!self.targetCandidate){self.statusLabel.text=@"请先选择 Target Method";return;}
    NSString *reason=nil;
    if(![[ZNNativeRedirectRuntime sharedRuntime] supportsSourceCandidate:self.candidate targetCandidate:self.targetCandidate reason:&reason]){
        self.statusLabel.text=reason?:@"Source/Target ABI 不兼容";return;
    }
    NSString *error=nil;
    ZNNativeRedirectAction *created=[[ZNNativeRedirectStore sharedStore]
        addSourceCandidate:self.candidate
           targetCandidate:self.targetCandidate
                     title:self.titleField.text
        featureDescription:self.descriptionField.text
               controlType:self.controlType.selectedSegmentIndex==1?@"button":@"switch"
                     error:&error];
    self.statusLabel.text=created
        ? [NSString stringWithFormat:@"CREATED\n%@\n等待生成 Method Redirect descriptor",created.canonicalIdentity]
        : (error?:@"创建 Method Redirect 失败");
}

@end
