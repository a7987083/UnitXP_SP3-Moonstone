# HANDOFF

## 当前上下文

当前工作线：ZonoPatch Runtime Patch Menu `v0.5.7-dev`，阶段为 **ZONOE Toggle + Hybrid Low-Memory Method Finder**。

- Repository: `a7987083/UnitXP_SP3-Moonstone`
- Branch: `feature/runtime-patch-menu-v0.5.7-toggle-method-finder`
- Sealed predecessor: `86edac4d70ef467e9a58912768b6c6c72077842a`
- v0.5.7 Named Offset baseline: `8300cf41589bf8aa9a690152d4dab3dd6333073c`
- Functional code head: `f678d1c1850503eef6926b324112e0782236f522`
- CI-validated head: `3f7c2176304942f4adc24d2941b4b13310ca8af8`
- CI run: `34805178354` / `success`
- Artifact: `ZonoPatch-v0.5.7-NamedOffset-Test`
- Artifact ID: `10332369005`
- Artifact digest: `sha256:10871aa93e276ba1b73dd568d3208b2ea957dd3120e99d9e453dc2fa8b234df3`
- Dylib SHA256: `2de69ca9215e3eebec8a9072d9060a74a6fbaed3523c85b7921f2fbf422c881e`
- Device verified: `false`

注意：当前分支在上述 CI head 之后还有 docs-only 状态提交。不要把 docs-only HEAD 误称为已编译代码；功能/CI 证据以上述两个 SHA 为准。

## 已实现

### 1. ZONOE Feature Toggle

`ZNFeatureGroupUI.mm` 已将 Feature 页原 `UIButton` 文本状态改成自定义 `ZN50FeatureToggleControl : UIControl`。

最终视觉约定：

- ON：theme accent 蓝青色描边/轻微 glow，左侧 `✓`，白色 knob 在右。
- OFF：深色半透明轨道，白色 knob 在左，无额外文字。
- MIXED：knob 居中，低干扰 accent2 指示。
- Full 和 Compact 共用同一套视觉逻辑。

执行语义没有重写：仍走 `ZN50SetFeatureEnabled`，失败按原逻辑 rollback；状态持久化仍是 `zn.f.%016llx.enabled -> BOOL`。

### 2. Hybrid Low-Memory Method Finder

新增：

- `ZNIL2CPPHybridFinder.h/.mm`
- `ZNIL2CPPMethodFinderUI.mm`
- `ZNIL2CPPMethodFinderMenuBinding.mm`

搜索原则：

- 不创建全量 IL2CPP 方法索引。
- Namespace + Class 完整时优先直接 class lookup。
- 只有 Class 或裸方法名时使用 bounded streaming。
- method name 使用 case-insensitive exact match；`gethp` 可以匹配 `GetHP`，但不做模糊 contains。
- Assembly-CSharp 优先。
- 上限：8 candidates / 12,000 classes / 750 ms。
- 达到预算且无法证明唯一时返回错误，不误报唯一。
- 歧义结果要求补充 Class/Namespace/Assembly/argument count。

地址模型：

- RVA = Runtime VA - loaded UnityFramework image base。
- Preferred/IDA VA = 真实 Mach-O `__TEXT.vmaddr + RVA`，不硬编码 `0x100000000`。
- Runtime VA、MethodInfo、Method Pointer 同时返回。
- method pointer 优先 `il2cpp_method_get_pointer`；fallback 只在 executable UnityFramework segment 校验通过时接受。
- 当前 pointer kind：`direct-api / direct-fallback / virtual-fallback`。
- generic / inflated / thunk 还没有可靠分类，禁止宣称已完成。

### 3. Named Offset / Builder 集成

`ZNIL2CPPNamedOffsetWorkspace.mm` 现在通过 Hybrid Finder 解析 symbolic Offset。

流程仍为：

`symbolic expression -> Hybrid Finder -> numeric RVA -> existing Runtime Validator -> existing Static Builder V3`

原 symbolic expression 在验证后恢复显示；validator 持有已验证 numeric RVA。

Method Finder UI 新增 `方法查找` 菜单：

- 搜索
- canonical method / assembly / class
- RVA / Preferred(IDA) VA / Runtime VA / MethodInfo / Method Pointer
- pointer source/kind
- 复制信息
- 加入 Builder

`加入 Builder` 只创建未验证行：target=`UnityFramework`、Offset=原 symbolic expression；不会自动写 Patch 字节，也不会绕过 `读取验证`。

## 生命周期与安全不变量

- Full Deferred Bootstrap 保持。
- 编译结果仍只有一个 constructor：`ZNDeferredColdLauncherBootstrap`。
- 无 compiled Objective-C `+load`。
- Method Finder backend/UI 在首次 ZN 激活后的既有 authoring deferred stage 安装。
- Protection V2 / Static RVA Protection V1 / ZNF1 / Shared Site / no runtime executable-page mutation 等既有不变量继续由 CI 断言。
- 最终 IPA 仍需要整包重签。

## CI 已验证

Run `34805178354`：

- source assertions: PASS
- Named Offset parser: PASS
- Payload Protection V2 layout: PASS
- Feature metadata codec: PASS
- Static RVA Protection: PASS
- Theos arm64 compile/link/sign: PASS
- exported API symbols: PASS
- binary marker checks: PASS
- `__init_offsets == 4`: PASS
- artifact upload: PASS

### 本轮排除过的 CI 假失败

1. `ZNIL2CPPMethodFinderMenuBinding.mm` replacement selector 错放在 primary interface，触发 category method `-Werror`；已把 selector 声明移入 category interface，运行逻辑未变。
2. Binary verify 用 macOS `strings` grep 中文 `方法查找`，编码输出不稳定；已改为 ASCII marker `bounded search -> detail -> Builder`。

不要重新引入这两种写法。

## 尚未验证 / 不得声称已完成

- 真机上 Toggle 最终视觉与点击区域。
- Full / Compact / 主题切换 / 长功能名 / MIXED / persistence / rollback 真机回归。
- 真机 `gethp` / `GetMoney` 的实际 IL2CPP resolution。
- 与已知 numeric RVA、IDA VA 的真实对比。
- 大型 App 连续搜索的峰值内存、耗时与预算合理性。
- hidden/incomplete IL2CPP API 的真实游戏兼容性。
- generic/inflated/thunk 可靠分类。
- Method Finder -> Builder -> `读取验证` -> apply/restore 的真实设备闭环。

## 版本元数据漂移

`ZonoeRuntimeMenu.mm` 仍含历史版本字符串，包括 exported `ZonoePatchGetVersion()` 返回 `0.5.6-ui-consolidated` 及部分 `0.5.5/0.5.6` 注释/日志。

不要直接全局替换。先检查所有调用方、外部 consumer、兼容判断和 artifact 流程，再单独做 metadata cleanup。

## Next Task

拿 final CI artifact 上真实 IL2CPP 游戏：

1. 先验收最终 Toggle UI。
2. 搜索一个已知方法，例如 `gethp` 或 `GetMoney`，记录 UI 输出。
3. 用已知 RVA/IDA 地址交叉核对。
4. 连续重复搜索，观察内存与耗时。
5. 测试同名歧义和隐藏 API 失败路径。
6. `加入 Builder`，填入已知安全 Patch bytes，执行 `读取验证`、临时应用和恢复。

设备证据回来后，再决定是否补 generic/inflated 标记、调整 bounded-search 预算，以及是否进入 `0.5.7.x` 封板。
