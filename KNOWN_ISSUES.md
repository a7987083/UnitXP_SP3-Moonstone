# KNOWN_ISSUES

只记录未关闭问题、验证缺口和风险；已完成修改放在 `CHANGELOG_DEV.md`。

## KI-001 — M5.0 Managed-reference Return Chaining 尚未真机验证

Severity: `HIGH`  
Status: `IMPLEMENTED / CI IN PROGRESS / DEVICE VERIFICATION PENDING`

需要真机证明：managed-reference return 被捕获并保活；兼容目标 class 的下一次实例调用实际使用该 returned object；不兼容目标不注入；原手工 receiver 可恢复。

## KI-002 — M5.0 目前只消费显式 Runtime Invoke 返回

Severity: `MEDIUM`  
Status: `BY DESIGN / LATER NATURAL-CALL WORK`

M5.0 依赖 M4.8 的 `il2cpp_runtime_invoke` return metadata。游戏自然发生的 native/IL2CPP 调用尚无通用 exit-hook return capture，因此不能自动把任意自然调用返回值加入 chain。

## KI-003 — GCHandle exports 不完整时只能 raw fallback

Severity: `MEDIUM`  
Status: `COMPATIBILITY FALLBACK`

如果 `il2cpp_gchandle_new/get_target/free` 不是完整导出集，M5.0 保存 process-session raw address。使用前仍做 class validation，但它不具备 moving-GC 保证。真机应记录目标 Unity 版本及 fallback 是否发生。

## KI-004 — Managed-reference chain 当前只保留 latest object

Severity: `LOW`  
Status: `V1 DESIGN`

M5.0 是单槽 last-managed-return 模型。每次新的非空 managed-reference return 会替换并释放前一 chain handle。后续 Object Inspector 若需要 history/stack，应单独设计有上限的 receiver history。

## KI-005 — Complex ValueType / ref/out 尚未纳入 Generic Invoke / Chaining

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION / FAIL CLOSED`

复杂 struct/value type、ref/out、普通 pointer ABI 仍需 metadata/layout 驱动，不应把 boxed value object 误当 managed receiver。

## KI-006 — M4.9 generated Runtime `执行` UI 修复待真机复验

Severity: `HIGH`  
Status: `FIX IMPLEMENTED / CI VERIFIED / DEVICE VERIFICATION PENDING`

用户此前报告生成后看不到预期 `执行`/参数弹窗。M4.9 已改为最外层 Runtime Method Action renderer；必须在 M5.0 真机回归中先确认按钮可见，再测试 chaining。

## KI-007 — M4.9 Editable Args 真机效果尚未确认

Severity: `HIGH`  
Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

`/1-/8` 弹窗输入会组装 one-shot argument vector 并走 Generic Invoke。必须确认修改后的某一个参数真实进入目标方法，而非仅 UI 改变。

## KI-008 — 同方法多 Runtime 按钮待生成物真机确认

Severity: `MEDIUM`  
Status: `FIX IMPLEMENTED / DEVICE VERIFICATION PENDING`

authoring 已取消 canonical method 去重，并使用独立 actionID。需要验证同一 method/signature、甚至相同参数的多个按钮都能进入生成二进制并各自显示。

## KI-009 — M4.8 natural-call return capture 未实现

Severity: `MEDIUM`  
Status: `PLANNED`

当前 return capture 仅覆盖 explicit Runtime Invoke。自然调用需要 exit/post-call hook、ARM64 GPR/FP/struct-return ABI 处理和线程/递归安全 frame tracking。

## KI-010 — Object/Collection Inspector 尚未实现

Severity: `MEDIUM`  
Status: `NEXT PHASE`

M5.0 只提供安全 managed-object root。字段枚举、System.String 解码、Array/List/Dictionary 导航、递归/cycle guard、JSON/TXT export 仍未实现。

## KI-011 — Protection V1 尚未真实 `.znpatched` / 最终 IPA 验证

Severity: `HIGH`  
Status: `OPEN`

CI 已确认 codec/build/binary verify，但仍缺真实目标 `.znpatched + build_report.json + 冷启动` 证据。

## KI-012 — Generated binary 后处理仅支持 thin 64-bit Mach-O

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

未来 FAT/universal 需要按 slice 解析。

## KI-013 — Generated binary ad-hoc 重签不能替代最终 IPA 签名

Severity: `MEDIUM`  
Status: `RELEASE REQUIREMENT`

最终仍需整包重签、安装、冷启动验证。

## KI-014 — 部分 Objective-C bridge declaration 仍依赖 warning suppression

Severity: `LOW`  
Status: `PRE-SEAL CLEANUP`

多 milestone category/swizzle 层较多，封板前应整理专用接口/协议并减少隐式 selector declaration 技术债。

## KI-015 — M4.4/M4.6 receiver selection 仍是 process-session 状态

Severity: `MEDIUM`  
Status: `BY DESIGN`

不序列化 raw object pointer。重启后 receiver 与 managed-return chain 都必须重新解析/捕获。

## KI-016 — Shared/generic native code 仍可能产生 MethodInfo 歧义

Severity: `MEDIUM`  
Status: `BY DESIGN / NEEDS OBSERVATION`

Full Signature 已降低同名/同 arity 歧义，但 IL2CPP generic sharing 仍可能让多个 MethodInfo 共用 native pointer。不得仅凭地址猜一个 managed method。

## KI-017 — M4.5 owning-method 大型游戏扫描预算

Severity: `MEDIUM`  
Status: `KNOWN LIMITATION`

Interior ownership 需要安全 next-method 上界；live scan 到预算或缺上界会 fail closed。后续可做可缓存排序 Method Index。

## KI-018 — 完整多游戏回归尚未完成

Severity: `HIGH`  
Status: `OPEN`

M4.7-M5.0 的 receiver、multi-arg、return decode、editable args、duplicate buttons、managed chaining 需要跨多个 IL2CPP 游戏/Unity 版本回归。任何单游戏真机成功都不能等同通用性证明。
