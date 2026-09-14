# ROADMAP

## 当前阶段

- Project: ZonoPatch Runtime Patch Menu
- Version: `0.5.7-dev`
- Branch: `feature/runtime-patch-menu-v0.5.7-toggle-method-finder`
- Stage: `ZONOE Toggle + Hybrid Low-Memory Method Finder`
- Functional code head: `f678d1c1850503eef6926b324112e0782236f522`
- CI-validated head: `3f7c2176304942f4adc24d2941b4b13310ca8af8`
- Final CI run: `34805178354` — `success`
- Artifact: `ZonoPatch-v0.5.7-NamedOffset-Test` / ID `10332369005`
- Device validation: `PENDING`

## 基线

- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a`
- v0.5.7 Named Offset baseline: `8300cf41589bf8aa9a690152d4dab3dd6333073c`
- 不直接修改 sealed release 分支；后续功能继续从当前开发线推进。

## 已完成 — 当前开发线

### ZONOE Feature Toggle

- Feature 页由文字 `开/关/MIXED` 按钮改为自定义 `UIControl`。
- ON：主题 accent 描边/轻微 glow、左侧 `✓`、右侧白色 knob。
- OFF：深色半透明轨道、左侧 knob、无额外文字。
- MIXED：居中 knob + 低干扰状态提示。
- 保留原 `ZN50SetFeatureEnabled` transaction/rollback、Shared Site 行为与 `zn.f.%016llx.enabled` 持久化。

### Hybrid Low-Memory Method Finder

- 新增 `ZNIL2CPPHybridFinder`，不建立全量方法索引。
- 完整 Namespace/Class 优先直接定位；裸方法名/不完整限定使用 bounded streaming。
- 方法名大小写不敏感但要求 exact match，例如 `gethp` 可匹配 `GetHP`。
- Assembly-CSharp 优先。
- 当前预算：最多 8 个候选、12,000 个类、750 ms。
- 歧义不自动取第一个，要求用户进一步限定。
- 地址输出：RVA、真实 Mach-O `__TEXT.vmaddr` 推导的 Preferred/IDA VA、Runtime VA、MethodInfo、Method Pointer。
- Pointer 当前区分 `direct-api / direct-fallback / virtual-fallback`；仅 executable UnityFramework 地址可接受。
- Named Offset 已切到 Hybrid Finder；最终仍进入原 Runtime Validator / Static Builder V3。

### Method Finder UI

- 新增开发者菜单 `方法查找`。
- 提供搜索、地址详情、复制信息、加入 Builder。
- `加入 Builder` 只写入 symbolic expression + `UnityFramework` target，不自动填 Patch 字节、不绕过 `读取验证`。

## CI Gate — 已通过

Run `34805178354` 已完成：

- source assertions: PASS
- Named Offset parser tests: PASS
- Payload Protection V2 layout tests: PASS
- Feature metadata codec tests: PASS
- Static RVA Protection tests: PASS
- Theos arm64 build/link/sign: PASS
- binary verify: PASS
- exactly one constructor / no compiled ObjC `+load`: PASS
- artifact upload: PASS

Final dylib SHA256:
`2de69ca9215e3eebec8a9072d9060a74a6fbaed3523c85b7921f2fbf422c881e`

## 下一阶段 — Physical Device Acceptance

Status: `NEXT`

必须在真实 IL2CPP 游戏上完成：

1. 检查最终 Toggle 在 Full / Compact / 多主题下的尺寸、点击、ON/OFF/MIXED、长名称布局。
2. 验证 Feature 持久化恢复、Shared Site、失败 rollback 的视觉与实际状态一致。
3. 用已知方法测试 `gethp` / `GetMoney`，确认大小写不敏感 exact match；与已知数值 RVA 对比。
4. 核对 RVA / Preferred(IDA) VA / Runtime VA / MethodInfo / Method Pointer。
5. 连续搜索，观察耗时、内存和候选截断；验证超预算不会误报唯一结果。
6. 验证同名重载/同名类歧义会被拒绝。
7. 验证隐藏/缺失 IL2CPP API 时安全失败，不崩溃。
8. Method Finder -> 加入 Builder -> 填入已知安全 Patch -> `读取验证` -> 临时应用/恢复 -> generated binary build。

## Device Acceptance 之后

- 根据真实游戏证据调整 8 / 12,000 / 750 ms 搜索预算。
- 增加 generic / inflated 可靠识别；thunk 只在有确定证据时标记，不猜测。
- 如 Runtime API 隐藏率高，再评估 `global-metadata.dat + UnityFramework` metadata-backed narrowing。
- 补真实 generated `.znpatched` fixture/gate 和最终 IPA 重签回归。
- 审计 `ZonoePatchGetVersion` 及旧 `0.5.5/0.5.6` 内部版本字符串的调用方后，再统一版本元数据。
- 设备验收通过后再决定封为 `0.5.7.x` 还是下一功能版本。
