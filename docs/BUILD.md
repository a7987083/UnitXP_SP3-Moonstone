# zonoe / HFASign v3 构建说明

## 权威构建基线

- 仓库：`https://github.com/a7987083/UnitXP_SP3-Moonstone.git`
- 分支：`work/hfapatchipa-ksign-v3`
- Ksign 上游：`https://github.com/Nyasami/Ksign.git`
- 固定上游 commit：`03a3a9c86897d79f9faf8106037b9971841d56a0`
- Workflow：`.github/workflows/hfasign-build.yml`
- Runner：`macos-26`
- Scheme：`Ksign`
- Configuration：`Release`
- SDK/destination：`iphoneos` / `generic/platform=iOS`
- 签名：Xcode build 禁用 code signing，打包阶段使用 `ldid`

## 推荐方式：GitHub Actions

不要修改功能时仅为重跑而制造无意义代码差异。可以在 GitHub Actions 页面手工 `workflow_dispatch`。

成功产物：

```text
Artifact: zonoe-v3.0.0-alpha12
HFASign/dist/zonoe_v3.0.0-alpha12_TrollStore.ipa
HFASign/dist/SHA256SUMS.txt
```

最近成功运行：<https://github.com/a7987083/UnitXP_SP3-Moonstone/actions/runs/33810234557>

## 本地重建补丁树

在 macOS 上：

```bash
git clone https://github.com/a7987083/UnitXP_SP3-Moonstone.git
cd UnitXP_SP3-Moonstone
git switch work/hfapatchipa-ksign-v3

git clone https://github.com/Nyasami/Ksign.git HFASignBuild
git -C HFASignBuild checkout 03a3a9c86897d79f9faf8106037b9971841d56a0

git -C HFASignBuild apply ../HFASign/patches/0001-Rebrand-Ksign-baseline-as-HFASign-alpha1.patch
git -C HFASignBuild apply ../HFASign/patches/0003-HFASign-alpha3-detailed-signing-and-import-fixes.patch
git -C HFASignBuild apply ../HFASign/patches/0004-zonoe-alpha4-incremental.patch
git -C HFASignBuild apply ../HFASign/patches/0005-zonoe-alpha5-import-resources-signing-ui.patch
git -C HFASignBuild apply ../HFASign/patches/0006-zonoe-alpha6-resource-actions-signing-fix.patch
git -C HFASignBuild apply ../HFASign/patches/0007-zonoe-alpha7-import-zip-library.patch
git -C HFASignBuild apply ../HFASign/patches/0008-zonoe-alpha8-udid-schemes-encrypted-sources.patch
git -C HFASignBuild apply ../HFASign/patches/0009-zonoe-alpha9-udid-zip-sources.patch
git -C HFASignBuild apply ../HFASign/patches/0010-zonoe-alpha9-compile-pending-validation.patch
git -C HFASignBuild apply ../HFASign/patches/0011-zonoe-alpha10-source-zip-udid-fixes.patch
git -C HFASignBuild apply ../HFASign/patches/0012-zonoe-alpha11-source-identity-advanced-signing.patch
git -C HFASignBuild apply ../HFASign/patches/0013-zonoe-alpha12-signing-paging-unlock.patch

git -C HFASignBuild submodule update --init --recursive
```

注意：不要应用 `0002`；当前 workflow 明确跳过它。

先验证 patch：

```bash
git -C HFASignBuild status --short
git -C HFASignBuild diff --check
```

## 依赖与构建

```bash
brew install ldid
cd HFASignBuild
make deps
cd ..

xcodebuild -resolvePackageDependencies \
  -project HFASignBuild/Ksign.xcodeproj \
  -scheme Ksign

xcodebuild \
  -project HFASignBuild/Ksign.xcodeproj \
  -scheme Ksign \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath HFASignBuild/build \
  -skipPackagePluginValidation \
  SWIFT_VERSION=5 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

依赖由 Ksign 的 git submodules、Swift Package resolution 和 `make deps` 共同提供。关键组件包括 AltSourceKit、IDeviceKit、NimbleKit、Zsign、ZIPFoundation、Vapor/本地 server 所需依赖。不要只复制 `Ksign/` Swift 文件而遗漏 submodule 和 installer assets。

## 图标步骤

Workflow 构建时从以下地址下载图标：

```text
https://app.zonoeios.xyz/uploads/20220704/d042be36ab9f4c73f0c721bccc6ba6c9.png
```

经 `sips` 裁剪/缩放到 1024×1024，再覆盖 AppIcon asset。此构建依赖外部 URL；若该地址失效，应把合规图标资源提交到仓库并修改 workflow，而不是让构建静默使用上游 Ksign 图标。

## 打包 TrollStore IPA

Workflow 做法：

1. 定位 `build/Build/Products/Release-iphoneos/Ksign.app`；
2. 拷贝 `make deps` 产物；
3. 对 Frameworks 内 Mach-O 和主二进制运行 `ldid -S`；
4. 拷贝为 `Payload/HFASign.app`；
5. 用 `ditto -c -k --sequesterRsrc --keepParent Payload` 生成 IPA；
6. `shasum -a 256`；
7. 校验 Info.plist 元数据；
8. 提交 IPA 和 SHA 文件并上传 Actions Artifact。

## 修改后如何生成下一补丁

推荐在干净的、已应用 0001～0012 的 Ksign 工作树上开发下一阶段，并把一个逻辑阶段集中成 `0014-...patch`，不要直接改旧 patch，除非是修复 alpha12 本身且能证明不会破坏可追踪性。

示例：

```bash
git status --short
git diff --check
git add Ksign Ksign.xcodeproj
git commit -m 'Describe the next zonoe change'
git format-patch -1 --stdout > ../HFASign/patches/0014-description.patch
```

随后把 `0014` 加到 workflow 的 `git apply` 列表，并先在全新 clone 上逐个 `git apply --check`。

## 发布前检查

```bash
shasum -a 256 HFASign/dist/zonoe_v3.0.0-alpha12_TrollStore.ipa
git status --short
git log -5 --oneline
```

预期 alpha12 SHA-256：

```text
1542128d46df495652c4dd93a9318c42754f746f607e756a49af3ec36dd93559
```

不要仅看 `HFASign/BUILD_ERROR.txt` 判断成败；应查看最新 GitHub Actions run 的 `conclusion`。

