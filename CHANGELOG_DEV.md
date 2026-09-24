# CHANGELOG_DEV

只记录已经实际发生的修改和验证；计划项放在 `ROADMAP.md`。

## 2026-09-24 — M5.5 Typed Control Binding V2

Branch: `feature/runtime-patch-menu-v0.5.8-m5.5-typed-control-binding-v2`

CI-validated product: `3548cbc655f4347e03947d9dba0fb501f15b137e`

### 实际修改

- 新增统一 Value Type：`Auto / I32 / U32 / I64 / U64 / F32 / F64`。
- 控件类型继续保持 `Switch / Button / Number / Slider`，不把 MOV/FMOV/ABI 暴露成客户 UI 类型。
- Runtime Auto 根据 IL2CPP 参数签名推荐数值类型。
- Runtime Builder 参数控件新增 Value Type 按钮；长按进入 `Default / Min / Max / Step` 编辑。
- Runtime Slider 在旧 M5.3 自动执行之前完成 step 量化；默认 Slider `1..10 / step 1`。
- Runtime Number 在执行前按选中/解析后的类型做 canonical validation。
- Runtime Action control JSON 现在保留 `valueType/default/min/max/step`；64-byte Entry ABI 未变化。
- Static Builder 新增独立 Value Type 选择。
- Static Value Type 存入 Entry flags bits 11..13；旧生成物 `0` 自动解释为 Auto；128-byte Static Entry ABI 未变化。
- Static Number 增加精确 `valueText` 通路，避免 U64 在进入编码器前被 double 精度截断。
- Static Slider 改为整数值 `1..10 / step 1`。
- 新增 `ZNM55StaticTypedBinding.mm`：
  - MOVZ(+MOVK) -> I32/U32/I64/U64；
  - scalar FMOV S,#imm -> F32；
  - scalar FMOV D,#imm -> F64；
  - Auto 根据已验证首指令族选择后端；
  - 类型不匹配、MOVK 槽位不足、FMOV 无法精确编码时 fail closed。
- M5.5 Static binder 安装后移除旧 M5.3 Static MOV-only observer；M5.3 Runtime Button/Switch/Number/Slider auto-execute 仍保留。
- FMOV immediate 扩展算法对当前产品常用整数区间做了独立验证；1..31 均可精确表示，当前公开 Slider 默认仍为 1..10。

### CI 历史

- Run `35995621476`: 第一轮 Build 失败，原因仅为 Objective-C++ 中 `NSData.bytes` 从 `const void *` 到 `const uint8_t *` 缺显式 cast。
- 修复 commit `c80db10b5c93c9d88aca3323abc2b48a912f3cc1` 后，基础 Typed Runtime/Builder 版本 Run `35996073916` 全绿。
- 最终加入 Static MOV/FMOV typed adapter 后，Run `35996840472` / Job `107623672455`：Source Contract、Build、Binary Verify、Artifact Upload 全部 SUCCESS。

### 最终制品

- Artifact ID: `10806284095`
- ZIP SHA256: `9ec1d6ab1a484572b16c1eff57eb90a7d54836b9717ed9748296fcc66a4b86e9`
- Dylib size: `1404656`
- Dylib SHA256: `0dacef0f731d0a6b59e1446b08977d69a6eeb732096c761a9ed321be0214375a`
- Mach-O: thin arm64 dylib
- 独立下载后 ZIP digest 与 GitHub digest 一致，dylib hash 与 Artifact `SHA256.txt` 一致。

### 验证边界

- source implemented: YES
- GitHub committed: YES
- arm64 compile/link/sign: YES
- Binary Verify: YES
- independent artifact hash: YES
- M5.5 typed controls device verification: PENDING
- Static FMOV/MOV typed backend device verification: PENDING
- full M5.4/M5.5 regression: PENDING

## 2026-09-24 — M5.4 Device Evidence

- 用户真机确认 M5.4 Unified Method Finder / 搜索历史已经可见。
- 关闭此前“History 源码存在但最终 UI 不显示”的核心 blocker。
- 历史点击、candidate binding、receiver capture、Chain 等交互仍需逐项回归。

## Historical anchors

- M5.4 Unified CI green: `8c6131b2628f1e8c980d8c71fc62ac0cdc8c5845` / Run `35964757740`.
- M5.3 Control Binding initial green: `b2e4bfa6ea66d9b64cc27149a413a01146ba0a8f`.
- M5.2 core multi-level chain: `2456f6ba4dfb659e3480db2e677452dad8516153`.
- M5.1 Silent Customer Execution: `29c33d9246fd9842107c443d3254aff23effd59e`.
