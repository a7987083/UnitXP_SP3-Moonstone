# IP加解密工具 v2.0 · IPA模式

Windows x64 便携版，双击 EXE 即可运行，不需要安装 Python、PyCryptodome 或 PyInstaller。

## 两种模式

### 文本模式
- 保留原工具逻辑。
- 格式：前 16 字节为 AES Key，后续为 Base64(AES-128-ECB) 密文。
- Padding：Zero Padding（0x00），不是 PKCS#7。
- 支持加载/保存文本、解密、加密、复制结果。

### IPA模式
- 右上角点击“加载 IPA”。
- 自动查找 `Payload/*.app/Frameworks/UnityFramework.framework/UnityFramework`。
- 动态扫描并验证 Startup AES 配置块，不依赖固定 `0x3B1EE8D` 偏移。
- 识别依据包括 `LOGIN_HOST`、`ResVersion`、`PACKAGE`、`FAXINGNAME`、`GameFindStr` 等 JSON 字段。
- 自动解密后把完整 JSON 显示在编辑框中。
- 编辑 JSON 后点击“加密并生成 IPA”。
- 保留原 AES Key、原 cipher slot 长度、原 Base64 slot 长度。
- 如果编辑后的格式化 JSON 超长，会尝试完整 JSON 紧凑化；仍超长则停止，不删除 `GameFindStr` 或未知字段。
- 写回前执行 AES 解密 + JSON 语义回读验证。
- 输出同目录 `.report.json` 与 `.after.decrypted.json`。

## IPA动态状态显示

加载/处理时会显示：
- UnityFramework entry
- blob offset
- AES Key
- plain / cipher / Base64 长度
- JSON key 数量
- GameFindStr 数量
- 打包进度
- 回读验证结果

## 注意

生成的新 IPA 已修改二进制内容，必须重新签名后安装。
