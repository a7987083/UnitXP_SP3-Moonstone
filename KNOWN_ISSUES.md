# KNOWN_ISSUES

只记录当前未关闭问题、验证缺口和设计边界。

## KI-M54-001 — Unified Method Finder 可见性已真机确认

Severity: `HIGH`  
Status: `DEVICE VISIBILITY ACCEPTED / INTERACTION REGRESSION PENDING`

2026-09-24 用户真机反馈 M5.4 Unified/搜索历史界面“有了”。因此此前“最终 Unified renderer 未接管 / 搜索历史仍不可见”的核心阻塞项可关闭。当前剩余风险转为交互与后端行为回归，而不是基础页面是否出现。

## KI-M54-002 — 旧 Method Finder UI 源码仍在编译

Severity: `MEDIUM`  
Status: `INTENTIONAL TRANSITION BOUNDARY`

M5.4 已将旧 renderer 从最终 UI 路径截断，但 M4.x/M5.x 若干 installer 同时混有 backend/action swizzle 与 UI wrapper，因此旧文件暂时仍编译并部分安装，以保留 resolver、Invoke、Builder、candidate binding、receiver capture、chain 等能力。完整回归通过后，应继续拆分 mixed installer，并从 Makefile / install graph 物理移除已废弃 renderer 实现。

## KI-M54-003 — Unified Search History 交互仍待真机验收

Severity: `MEDIUM`  
Status: `VISIBLE ON DEVICE / INTERACTION VERIFICATION PENDING`

搜索历史已经真机可见。仍需验证：点击历史仅回填 方法名、不自动搜索；手动点击搜索后执行正确查询；重启持久化；重复项去重；超过 50 条时淘汰最旧项。

## KI-M54-004 — Unified Results 行为装饰器需完整回归

Severity: `HIGH`  
Status: `SOURCE/CI/BINARY VERIFIED / DEVICE REGRESSION PENDING`

Unified Results 直接渲染 `/0-/8` typed arg rows。M4.6.2 candidate binding、M4.7 receiver-capture long press、M5.1/M5.2 chain create/execute/restart 仍作为窄行为装饰器包在 Unified 外层。需要真机确认 Test 不串 candidate、receiver gesture 正确、创建方法和链按钮状态机无回归。

## KI-M53-001 — Runtime 四控件自动执行尚未真机完整验收

Severity: `HIGH`  
Status: `IMPLEMENTED / CI+BINARY VERIFIED / DEVICE VERIFICATION PENDING`

M5.3 将 Runtime Button/Switch/Number/Slider 绑定到真实 invoke：Button 点击、Switch 改值、Number 编辑结束、Slider 松手执行。成功静默，失败显示 `执行失败`。M5.4 未改其后端，但 UI 架构变更后仍需回归。

## KI-M53-002 — Static Number/Slider V1 仅支持 MOVZ(+MOVK) 整数常量

Severity: `HIGH`  
Status: `IMPLEMENTED / FAIL-CLOSED OUTSIDE SUPPORTED ENCODING / DEVICE VERIFICATION PENDING`

V1 仅处理可验证 ARM64 MOVZ + compatible MOVK immediate。负数、浮点、FMOV、ADD/SUB/ORR immediate、任意 raw bytes 均不猜测编码。

## KI-M53-003 — Static dynamic V1 需要 executable-page runtime write

Severity: `HIGH`  
Status: `ARCHITECTURAL LIMIT / DEVICE VERIFICATION REQUIRED`

Static Number/Slider V1 会对生成 ON variant instruction page 做 transactional RX→RW 写入。受限签名/非越狱环境可能拒绝；此时必须 fail closed。若目标设备不允许，下一代应使用构建期 parameterized stub + RW value cell，而不是弱化保护或盲写。

## KI-M53-004 — Static Slider 范围仍使用旧默认值

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

Builder 尚未增加 Static 专用 min/max/step 元数据。应在动态后端目标设备验收后再扩展。

## KI-M52-001 — Immediate Chain V2 Level 0 返回问题仍开放

Severity: `HIGH`  
Status: `PARTIAL DEVICE EVIDENCE / INVESTIGATION OPEN`

用户已真机确认 `执行链` 入口存在并进入执行器，但一次链执行在 Level 1 前停止：`previous managed return is null`。仍需区分 `yo::wB()/0` 真实返回 null 与 Root receiver/return propagation 丢失。M5.4 UI 重构不解决这一后端问题。

## KI-M52-009 — Suffixless generated binary 缺完整真机验收

Severity: `HIGH`  
Status: `SOURCE+CI COMPILE VERIFIED / FIXTURE+DEVICE PENDING`

真实 UnityFramework Builder 输出、替回 IPA、签名、安装、冷启动仍需完整设备证据。

## Legacy open validation gaps

- Enum member-name dropdown 尚未实现。
- Chain V2 typed per-node rows、任意 Level-N object arg、ref/out、复杂 ValueType 仍未实现。
- M5.0 managed object lifetime / class compatibility 在不同 Unity/IL2CPP 版本仍需设备证据。
- Protection V1/V2 真实 staging -> final IPA 冷启动证据仍未自动关闭。
