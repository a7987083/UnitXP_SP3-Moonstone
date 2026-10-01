from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "iosruntimepatchmenu" / "src"
menu_path = SRC / "ZonoeRuntimeMenu.mm"
core_path = SRC / "ZNPatchCore.mm"

menu = menu_path.read_text(encoding="utf-8")
core = core_path.read_text(encoding="utf-8")

# Remove the four early Foundation/mock slider identities. Runtime Method uses
# ZNRuntimeArgumentControlType* and is intentionally outside this transformation.
for line in (
    'static NSString * const kZNFeatureSpeed = @"speed";\n',
    'static NSString * const kZNFeatureDamage = @"damage";\n',
    'static NSString * const kZNFeatureJump = @"jump";\n',
    'static NSString * const kZNFeatureAttackSpeed = @"attack_speed";\n',
):
    if menu.count(line) != 1:
        raise SystemExit(f"menu identity expected once: {line.strip()}")
    menu = menu.replace(line, "", 1)

for line in (
    '        ZNEnabledKey(kZNFeatureSpeed): @NO,\n',
    '        ZNEnabledKey(kZNFeatureDamage): @NO,\n',
    '        ZNEnabledKey(kZNFeatureJump): @NO,\n',
    '        ZNEnabledKey(kZNFeatureAttackSpeed): @NO,\n',
    '        ZNValueKey(kZNFeatureSpeed): @2.5,\n',
    '        ZNValueKey(kZNFeatureDamage): @5.0,\n',
    '        ZNValueKey(kZNFeatureJump): @1.5,\n',
    '        ZNValueKey(kZNFeatureAttackSpeed): @1.8,\n',
):
    if menu.count(line) != 1:
        raise SystemExit(f"menu default expected once: {line.strip()}")
    menu = menu.replace(line, "", 1)

old_player = '        [self addSection:@"玩家" subtitle:@"角色与能力相关修改" y:&y width:width]; [self addFullSwitch:@"无敌" subtitle:@"当前仅改变界面状态" featureID:kZNFeatureInvincible y:&y width:width]; [self addFullComposite:@"伤害倍率" featureID:kZNFeatureDamage fallback:5 min:1 max:20 y:&y width:width];\n'
new_player = '        [self addSection:@"玩家" subtitle:@"角色与能力相关修改" y:&y width:width]; [self addFullSwitch:@"无敌" subtitle:@"当前仅改变界面状态" featureID:kZNFeatureInvincible y:&y width:width];\n'
if menu.count(old_player) != 1:
    raise SystemExit("player slider row not uniquely found")
menu = menu.replace(old_player, new_player, 1)

old_battle = '        [self addSection:@"战斗" subtitle:@"数值类功能统一使用组合 Slider" y:&y width:width]; [self addFullComposite:@"伤害倍率" featureID:kZNFeatureDamage fallback:5 min:1 max:20 y:&y width:width]; [self addFullComposite:@"攻速修改" featureID:kZNFeatureAttackSpeed fallback:1.8 min:1 max:5 y:&y width:width];\n'
new_battle = '        [self addSection:@"战斗" subtitle:@"Static Offset 数值滑块已移除" y:&y width:width];\n'
if menu.count(old_battle) != 1:
    raise SystemExit("battle slider rows not uniquely found")
menu = menu.replace(old_battle, new_battle, 1)

old_move = '        [self addSection:@"移动" subtitle:@"功能名 + 当前值 + Slider + 开关" y:&y width:width]; [self addFullComposite:@"移速修改" featureID:kZNFeatureSpeed fallback:2.5 min:1 max:5 y:&y width:width]; [self addFullComposite:@"跳跃高度" featureID:kZNFeatureJump fallback:1.5 min:1 max:5 y:&y width:width];\n'
new_move = '        [self addSection:@"移动" subtitle:@"Static Offset 数值滑块已移除" y:&y width:width];\n'
if menu.count(old_move) != 1:
    raise SystemExit("move slider rows not uniquely found")
menu = menu.replace(old_move, new_move, 1)

old_compact = '    [self addCompactSwitch:@"无敌" featureID:kZNFeatureInvincible y:&y width:width]; [self addCompactComposite:@"移速" featureID:kZNFeatureSpeed fallback:2.5 min:1 max:5 y:&y width:width]; [self addCompactComposite:@"伤害" featureID:kZNFeatureDamage fallback:5 min:1 max:20 y:&y width:width]; [self addCompactComposite:@"跳跃" featureID:kZNFeatureJump fallback:1.5 min:1 max:5 y:&y width:width];\n'
new_compact = '    [self addCompactSwitch:@"无敌" featureID:kZNFeatureInvincible y:&y width:width];\n'
if menu.count(old_compact) != 1:
    raise SystemExit("compact mock sliders not uniquely found")
menu = menu.replace(old_compact, new_compact, 1)

for line in (
    '    [self registerDescriptor:@"speed" name:@"移速修改" category:@"移动" value:2.5 control:ZNFeatureControlTypeSlider];\n',
    '    [self registerDescriptor:@"damage" name:@"伤害倍率" category:@"战斗" value:5.0 control:ZNFeatureControlTypeSlider];\n',
    '    [self registerDescriptor:@"jump" name:@"跳跃高度" category:@"移动" value:1.5 control:ZNFeatureControlTypeSlider];\n',
    '    [self registerDescriptor:@"attack_speed" name:@"攻速修改" category:@"战斗" value:1.8 control:ZNFeatureControlTypeSlider];\n',
):
    if core.count(line) != 1:
        raise SystemExit(f"core mock slider descriptor expected once: {line.strip()}")
    core = core.replace(line, "", 1)

# These legacy identities/control renderings must be gone from the consolidated
# menu/core, while Runtime Method slider types may remain elsewhere.
for forbidden in (
    'kZNFeatureSpeed', 'kZNFeatureDamage', 'kZNFeatureJump', 'kZNFeatureAttackSpeed',
    '@"speed" name:@"移速修改"', '@"damage" name:@"伤害倍率"',
    '@"jump" name:@"跳跃高度"', '@"attack_speed" name:@"攻速修改"',
):
    if forbidden in menu or forbidden in core:
        raise SystemExit(f"legacy mock slider residue remains: {forbidden}")

menu_path.write_text(menu, encoding="utf-8")
core_path.write_text(core, encoding="utf-8")
print("M5.10.7 legacy Foundation/mock sliders removed")
