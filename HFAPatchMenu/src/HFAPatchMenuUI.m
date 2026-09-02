#import "HFAPatchMenuUI.h"
#import "HFAPatchEngine.h"
#import "HFAPatchLogger.h"

#import <UIKit/UIKit.h>

@interface HFAPatchOverlayWindow : UIWindow
@end

@implementation HFAPatchOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}
@end

@interface HFAPatchOverlayController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UIButton *floatingButton;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, copy) NSArray<NSString *> *groups;
@property(nonatomic, copy) NSDictionary<NSString *, NSArray<HFAPatchFeature *> *> *featuresByGroup;
@end

@implementation HFAPatchOverlayController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    [self buildFloatingButton];
    [self buildPanel];
    [self reloadConfiguration];
}

- (void)buildFloatingButton
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(16, 180, 52, 52);
    button.layer.cornerRadius = 26;
    button.layer.borderWidth = 1;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    button.backgroundColor = [UIColor colorWithRed:0.11 green:0.13 blue:0.17 alpha:0.94];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [button setTitle:@"HFA" forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:0.25 green:0.82 blue:1 alpha:1] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)]];
    [self.view addSubview:button];
    self.floatingButton = button;
}

- (void)buildPanel
{
    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = [UIColor colorWithRed:0.075 green:0.085 blue:0.11 alpha:0.97];
    panel.layer.cornerRadius = 16;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    panel.clipsToBounds = YES;
    panel.hidden = YES;
    [self.view addSubview:panel];
    self.panel = panel;

    CGFloat preferredWidth = MIN(360.0, UIScreen.mainScreen.bounds.size.width - 24.0);
    CGFloat preferredHeight = MIN(520.0, UIScreen.mainScreen.bounds.size.height - 80.0);
    [NSLayoutConstraint activateConstraints:@[
        [panel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [panel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [panel.widthAnchor constraintEqualToConstant:preferredWidth],
        [panel.heightAnchor constraintEqualToConstant:preferredHeight],
    ]];

    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"HFAPatchMenu v0.1";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    [panel addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:close];

    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.font = [UIFont systemFontOfSize:11];
    status.textColor = [UIColor colorWithWhite:0.72 alpha:1];
    status.numberOfLines = 2;
    [panel addSubview:status];
    self.statusLabel = status;

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.backgroundColor = UIColor.clearColor;
    table.dataSource = self;
    table.delegate = self;
    table.rowHeight = 48;
    [panel addSubview:table];
    self.tableView = table;

    UIButton *reload = [UIButton buttonWithType:UIButtonTypeSystem];
    reload.translatesAutoresizingMaskIntoConstraints = NO;
    [reload setTitle:@"重新读取配置" forState:UIControlStateNormal];
    reload.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [reload addTarget:self action:@selector(reloadConfiguration) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:reload];

    UIButton *disableAll = [UIButton buttonWithType:UIButtonTypeSystem];
    disableAll.translatesAutoresizingMaskIntoConstraints = NO;
    [disableAll setTitle:@"全部关闭" forState:UIControlStateNormal];
    [disableAll setTitleColor:[UIColor colorWithRed:1 green:0.38 blue:0.38 alpha:1] forState:UIControlStateNormal];
    disableAll.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [disableAll addTarget:self action:@selector(disableAllFeatures) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:disableAll];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [title.topAnchor constraintEqualToAnchor:panel.topAnchor constant:14],
        [close.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-14],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [status.trailingAnchor constraintEqualToAnchor:close.trailingAnchor],
        [status.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:7],
        [table.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],
        [table.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [table.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:6],
        [reload.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [reload.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-12],
        [disableAll.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [disableAll.centerYAnchor constraintEqualToAnchor:reload.centerYAnchor],
        [table.bottomAnchor constraintEqualToAnchor:reload.topAnchor constant:-6],
    ]];
}

- (void)togglePanel
{
    self.panel.hidden = !self.panel.hidden;
}

- (void)dragButton:(UIPanGestureRecognizer *)recognizer
{
    CGPoint translation = [recognizer translationInView:self.view];
    CGPoint center = self.floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;

    CGFloat radius = CGRectGetWidth(self.floatingButton.bounds) / 2.0;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    center.x = MAX(radius + 4, MIN(CGRectGetWidth(self.view.bounds) - radius - 4, center.x));
    center.y = MAX(safe.top + radius + 4,
                   MIN(CGRectGetHeight(self.view.bounds) - safe.bottom - radius - 4, center.y));
    self.floatingButton.center = center;
    [recognizer setTranslation:CGPointZero inView:self.view];
}

- (void)rebuildGroups
{
    NSArray<HFAPatchFeature *> *features = HFAPatchEngine.sharedEngine.configuration.features ?: @[];
    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<HFAPatchFeature *> *> *byGroup = [NSMutableDictionary dictionary];
    for (HFAPatchFeature *feature in features) {
        if (!byGroup[feature.group]) {
            byGroup[feature.group] = [NSMutableArray array];
            [groups addObject:feature.group];
        }
        [byGroup[feature.group] addObject:feature];
    }
    self.groups = groups;
    self.featuresByGroup = byGroup;
}

- (void)reloadConfiguration
{
    BOOL ready = [HFAPatchEngine.sharedEngine reloadConfiguration];
    [self rebuildGroups];
    if (ready) {
        HFAPatchConfiguration *configuration = HFAPatchEngine.sharedEngine.configuration;
        self.statusLabel.textColor = [UIColor colorWithRed:0.35 green:0.88 blue:0.58 alpha:1];
        self.statusLabel.text = [NSString stringWithFormat:@"已匹配：%@ · %lu 个功能",
                                 configuration.name, (unsigned long)configuration.features.count];
        [self.floatingButton setTitleColor:[UIColor colorWithRed:0.25 green:0.82 blue:1 alpha:1]
                                  forState:UIControlStateNormal];
    } else {
        self.statusLabel.textColor = [UIColor colorWithRed:1 green:0.48 blue:0.4 alpha:1];
        self.statusLabel.text = HFAPatchEngine.sharedEngine.configurationError ?: @"配置不可用";
        [self.floatingButton setTitleColor:[UIColor colorWithRed:1 green:0.42 blue:0.35 alpha:1]
                                  forState:UIControlStateNormal];
    }
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.groups.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.featuresByGroup[self.groups[(NSUInteger)section]].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return self.groups[(NSUInteger)section];
}

- (HFAPatchFeature *)featureAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *group = self.groups[(NSUInteger)indexPath.section];
    return self.featuresByGroup[group][(NSUInteger)indexPath.row];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"HFAPatchFeatureCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.backgroundColor = [UIColor colorWithWhite:1 alpha:0.055];
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }

    HFAPatchFeature *feature = [self featureAtIndexPath:indexPath];
    NSString *stateError = nil;
    HFAPatchFeatureState state = [HFAPatchEngine.sharedEngine stateForFeature:feature error:&stateError];
    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = state == HFAPatchFeatureStateEnabled;
    toggle.enabled = state != HFAPatchFeatureStateUnavailable;
    toggle.accessibilityIdentifier = feature.identifier;
    [toggle addTarget:self action:@selector(featureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.textLabel.text = feature.title;
    if (state == HFAPatchFeatureStateMixed) {
        cell.detailTextLabel.text = @"部分地址状态不一致";
        cell.detailTextLabel.textColor = [UIColor colorWithRed:1 green:0.68 blue:0.25 alpha:1];
    } else if (state == HFAPatchFeatureStateUnavailable) {
        cell.detailTextLabel.text = stateError ?: @"不可用";
        cell.detailTextLabel.textColor = [UIColor colorWithRed:1 green:0.4 blue:0.4 alpha:1];
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu Patch · %@",
                                     (unsigned long)feature.patches.count,
                                     state == HFAPatchFeatureStateEnabled ? @"已开启" : @"已关闭"];
        cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1];
    }
    return cell;
}

- (HFAPatchFeature *)featureWithIdentifier:(NSString *)identifier
{
    for (HFAPatchFeature *feature in HFAPatchEngine.sharedEngine.configuration.features) {
        if ([feature.identifier isEqualToString:identifier]) return feature;
    }
    return nil;
}

- (void)featureSwitchChanged:(UISwitch *)sender
{
    HFAPatchFeature *feature = [self featureWithIdentifier:sender.accessibilityIdentifier];
    if (!feature) return;
    NSString *error = nil;
    if (![HFAPatchEngine.sharedEngine setFeature:feature enabled:sender.isOn error:&error]) {
        sender.on = !sender.isOn;
        [self showError:error ?: @"Patch执行失败"];
    }
    [self.tableView reloadData];
}

- (void)disableAllFeatures
{
    [HFAPatchEngine.sharedEngine disableAll];
    [self.tableView reloadData];
}

- (void)showError:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"HFAPatchMenu"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

@interface HFAPatchMenuUI ()
@property(nonatomic, strong) HFAPatchOverlayWindow *window;
@property(nonatomic, strong) HFAPatchOverlayController *controller;
@end

@implementation HFAPatchMenuUI

+ (instancetype)sharedUI
{
    static HFAPatchMenuUI *ui;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ ui = [[HFAPatchMenuUI alloc] init]; });
    return ui;
}

- (void)start
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.window) return;
        HFAPatchOverlayController *controller = [[HFAPatchOverlayController alloc] init];
        HFAPatchOverlayWindow *window = nil;
        if (@available(iOS 13.0, *)) {
            UIWindowScene *activeScene = nil;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if ([scene isKindOfClass:UIWindowScene.class] &&
                    scene.activationState == UISceneActivationStateForegroundActive) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                }
            }
            if (activeScene) window = [[HFAPatchOverlayWindow alloc] initWithWindowScene:activeScene];
        }
        if (!window) window = [[HFAPatchOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        window.frame = UIScreen.mainScreen.bounds;
        window.windowLevel = UIWindowLevelAlert - 2;
        window.backgroundColor = UIColor.clearColor;
        window.rootViewController = controller;
        window.hidden = NO;
        self.controller = controller;
        self.window = window;
        HFAPatchLog(@"[UI-READY]");
    });
}

- (void)reload
{
    dispatch_async(dispatch_get_main_queue(), ^{ [self.controller reloadConfiguration]; });
}

@end
