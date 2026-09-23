# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — v0.5.8-dev M5.0 Managed-reference Return Chaining V1

分支：`feature/runtime-patch-menu-v0.5.8-m5.0-managed-return-chaining-v1`

CI-validated product source head：`ec6ed852c24684cb92dbfc927afe16797eccbc0d`

实际修改：

- 新增 `iosruntimepatchmenu/src/ZNM50ManagedReturnChaining.mm`。
- M5.0 安装在 M4.8 Return Capture 与 M4.9 Generic Invoke 之后，作为最外层 `executeAction:error:` 包装层。
- 只消费 M4.8 已确认的 `returnKind == managed reference / GPR64`；boxed primitive/value type 不进入 chaining。
- 非空 managed reference 返回值优先通过 `il2cpp_gchandle_new` 建立强 non-pinned GCHandle 保活。
- 下一次 Runtime Action 执行前，用 `znm44_validateInstanceAddress` 验证 chain object 是否兼容目标 Assembly/Namespace/Class。
- 只有验证通过才临时将 chain object 注入现有 instance selection；不兼容时完全回退旧 receiver resolver。
- 临时注入前保存原 selected receiver；如果存在原 receiver，则额外创建 keepalive GCHandle，避免临时替换 selection 时释放原 handle 后出现 moving-GC/stale-pointer 窗口。
- 调用完成后恢复原 receiver；若原来没有 selection，则清除临时 selection。
- 如果本次调用又返回 managed reference，则 chain 自动推进到新的返回对象。
- result dictionary 增加 `managedReturnChained` / `managedReturnGeneration` 运行期诊断字段。
- 新增日志标记 `[m5.0-chain]`：installed / captured / receiver injected。
- `Makefile` 纳入 M5.0 translation unit；`ZNBuildVersion.h` 更新到 `0.5.8 · M5.0`。
- 新增独立 workflow `.github/workflows/build-runtime-patch-menu-v0.5.8-m5.0-managed-return-chaining-v1.yml`。

CI / Build：

- Final product Run: `35927940785` — success
- Job: `107407405755`
- Source Contract: PASS
- Dobby arm64: PASS
- Build M5.0: PASS
- Binary Verify: PASS
- Artifact Upload: PASS
- Artifact: `ZonoPatch-v0.5.8-M5.0-Managed-Return-Chaining-V1`
- Artifact ID: `10779609055`
- Artifact ZIP size: `563220`
- Artifact digest: `sha256:31d49ef89513677ce8b566f066c679f45010ee4905af062fa3216f9190a396fe`
- Dylib: `ZonoPatch_v0.5.8_M5.0_Managed_Return_Chaining_V1.dylib`
- Dylib size: `1254432`
- Dylib SHA256: `a75e30a9400bafdf7bfcf8e59c65a7f651a422522cd5e1d529f84eb06b4e9cd7`
- Downloaded artifact `SHA256.txt` and independently calculated dylib hash matched exactly.

验证边界：

- M5.0 当前是源码完成 / CI 编译通过 / Binary Verify 通过 / Artifact 下载哈希复核通过。
- Managed-reference Return Chaining 真机验证仍为 PENDING。
- 自然游戏调用 return capture 未实现。
- complex ValueType/ref/out/pointer chaining 未实现。
- generated Runtime Action ABI 未升级；raw managed object pointer 不写入生成文件。

## 2026-09-24 — v0.5.8-dev M4.9 Generic Invoke + Runtime Editable Args fixes

- Runtime Method Action 改为外层 renderer 直接追加 `执行` 按钮，修复真机未出现执行/弹窗的问题路径。
- `/1-/8` 点击执行可编辑本次参数并继续走 Generic Invoke + M4.8 Return Capture。
- 取消“同方法只能创建一个按钮”的限制。
- method identity 与 button/action identity 分离；每个按钮使用独立 actionID。
- 修复后 CI Run `35923124792` success；Artifact ID `10778172167`。
- 真机仍需确认生成二进制中 Runtime `执行` 行与参数弹窗。

## 2026-09-24 — v0.5.8-dev M4.8 Return Capture

- 显式 `il2cpp_runtime_invoke` 后读取返回对象并按 IL2CPP ABI 分类。
- primitive/value return 通过 `il2cpp_object_unbox` 解码。
- object reference 保留 managed object pointer 表示。
- 用户真机确认：`System.Int32` 返回值可正确显示为 `1`，raw 为 boxed object pointer。
- M4.8 hotfix head：`7cbc583f65f49eeb3b4a6fd64181046ea10c08c0`。

## 2026-09-23 — M4.7 Receiver + Multi-Arg

- Stable product head：`0bc5909b1714aa49002c758dc3c88f945da2adf3`。
- CI Run `35844122215` success。
- 用户真机观察 receiver capture 得到稳定实例地址；不等同完整回归。

## Historical anchors

- M4.5 Owning Method CI head: `fa2f9db21b507da64feb6ffe0acc6a29d71aff2e`, run `35795001139`.
- M4.4.2 Search Restore: `fe8655444420bc9445ee741e2d3c4cffbaead066`.
- M4 Runtime Method Call V1 user device evidence: `/0` create/test/generated binary usable.
- Method Finder V3 M2.2 device-accepted: `19b912c840e7223adbc2c26ef80185c32b8eb77a`.
- Offset Resolver V2 baseline: `a3b8db8651eaea23ec0ae7e5fca497e8f67bcf6c`.
- v0.5.6.2 sealed: `86edac4d70ef467e9a58912768b6c6c72077842a`.
