import base64
import binascii
import json
import os
import re
import threading
import zipfile
from dataclasses import dataclass
from pathlib import Path
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

from Crypto.Cipher import AES

APP_TITLE = "IP加解密工具 v2.0 · IPA模式"
APP_VERSION = "2.0"
BLOCK = 16
KNOWN_KEYS = ("LOGIN_HOST", "ResVersion", "PACKAGE", "FAXINGNAME", "GameFindStr")
B64_BYTES = set(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")


class ToolError(Exception):
    pass


def zero_unpad(data: bytes) -> bytes:
    return data.rstrip(b"\x00")


def zero_pad_fixed(data: bytes, size: int) -> bytes:
    if len(data) > size:
        raise ToolError(f"明文过长：{len(data)} bytes，原密文槽位只能容纳 {size} bytes")
    return data + b"\x00" * (size - len(data))


def decrypt_text_blob(text: str):
    s = "".join(text.strip().split())
    if len(s) <= 16:
        raise ToolError("密文长度不足：前16字符应为 AES Key，后面应为 Base64 密文")
    key_text = s[:16]
    b64_text = s[16:]
    key = key_text.encode("utf-8")
    if len(key) != 16:
        raise ToolError(f"AES Key 必须正好16字节，当前 {len(key)} 字节")
    try:
        cipher = base64.b64decode(b64_text, validate=True)
    except Exception as e:
        raise ToolError(f"Base64 解码失败：{e}")
    if not cipher or len(cipher) % BLOCK:
        raise ToolError(f"AES 密文长度必须为16的倍数，当前 {len(cipher)}")
    plain = zero_unpad(AES.new(key, AES.MODE_ECB).decrypt(cipher))
    try:
        decoded = plain.decode("utf-8")
    except UnicodeDecodeError as e:
        raise ToolError(f"解密成功，但 UTF-8 解码失败：{e}")
    return decoded, key_text, len(cipher)


def encrypt_text_blob(plain_text: str, key_text: str):
    key = key_text.encode("utf-8")
    if len(key) != 16:
        raise ToolError("请先解密一段数据以取得16字节 Key，或在Key框中输入16字节Key")
    plain = plain_text.encode("utf-8")
    pad_len = (-len(plain)) % BLOCK
    padded = plain + (b"\x00" * pad_len)
    cipher = AES.new(key, AES.MODE_ECB).encrypt(padded)
    return key_text + base64.b64encode(cipher).decode("ascii")


@dataclass
class IpaBlob:
    ipa_path: str
    entry_name: str
    framework_bytes: bytes
    key_offset: int
    key_text: str
    b64_offset: int
    b64_len: int
    cipher_len: int
    plain_len: int
    plain_text: str
    json_obj: dict

    @property
    def blob_offset(self):
        return self.key_offset


def _iter_b64_runs(data: bytes, min_len=96):
    i = 0
    n = len(data)
    while i < n:
        if data[i] not in B64_BYTES:
            i += 1
            continue
        start = i
        while i < n and data[i] in B64_BYTES:
            i += 1
        if i - start >= min_len:
            yield start, i


def _score_json(obj):
    if not isinstance(obj, dict):
        return 0
    return sum(1 for k in KNOWN_KEYS if k in obj)


def find_startup_blob(framework: bytes, progress=None):
    runs = list(_iter_b64_runs(framework))
    if progress:
        progress(f"发现 {len(runs)} 个 Base64 候选区，开始验证 AES/JSON…")
    best = None

    for run_start, run_end in runs:
        run_len = run_end - run_start
        max_shift = min(96, max(0, run_len - 80))
        for shift in range(max_shift + 1):
            key_start = run_start + shift
            b64_start = key_start + 16
            if b64_start >= run_end:
                break
            key = framework[key_start:b64_start]
            if len(key) != 16 or any(c < 0x21 or c > 0x7E for c in key):
                continue

            available = run_end - b64_start
            lengths = []
            full4 = available - (available % 4)
            if full4 >= 64:
                lengths.append(full4)
            for cut in range(4, min(4096, full4 - 60) + 1, 4):
                L = full4 - cut
                if L < 64:
                    break
                if framework[b64_start + L - 1:b64_start + L] == b"=":
                    lengths.append(L)
                    if len(lengths) >= 12:
                        break

            seen = set()
            for b64_len in lengths:
                if b64_len in seen:
                    continue
                seen.add(b64_len)
                b64_bytes = framework[b64_start:b64_start + b64_len]
                try:
                    cipher = base64.b64decode(b64_bytes, validate=True)
                except (binascii.Error, ValueError):
                    continue
                if not cipher or len(cipher) % 16 or len(cipher) > 65536:
                    continue
                try:
                    plain = AES.new(key, AES.MODE_ECB).decrypt(cipher)
                    plain0 = zero_unpad(plain)
                    text = plain0.decode("utf-8")
                    obj = json.loads(text)
                except Exception:
                    continue
                score = _score_json(obj)
                if score >= 2:
                    cand = (score, key_start, b64_start, b64_len, cipher, plain0, text, obj, key)
                    if best is None or cand[0] > best[0]:
                        best = cand
                    if score >= 4:
                        break
        if best and best[0] >= 4:
            break

    if not best:
        raise ToolError("未自动识别到 Startup AES 配置块。未修改 IPA。")

    score, key_start, b64_start, b64_len, cipher, plain0, text, obj, key = best
    try:
        key_text = key.decode("ascii")
    except Exception:
        key_text = key.decode("latin1")
    if progress:
        progress(f"配置块识别成功：score={score} offset=0x{key_start:X}")
    return {
        "key_offset": key_start,
        "key_text": key_text,
        "b64_offset": b64_start,
        "b64_len": b64_len,
        "cipher_len": len(cipher),
        "plain_len": len(plain0),
        "plain_text": text,
        "json_obj": obj,
    }


def find_unityframework_entry(zf: zipfile.ZipFile):
    candidates = []
    for name in zf.namelist():
        norm = name.replace("\\", "/")
        if re.match(r"^Payload/[^/]+\.app/Frameworks/UnityFramework\.framework/UnityFramework$", norm):
            candidates.append(name)
    if not candidates:
        for name in zf.namelist():
            if name.replace("\\", "/").endswith("/Frameworks/UnityFramework.framework/UnityFramework"):
                candidates.append(name)
    if not candidates:
        raise ToolError("IPA 中没有找到 UnityFramework.framework/UnityFramework")
    return candidates[0]


def load_ipa_blob(path: str, progress=None):
    if progress:
        progress("打开 IPA…")
    try:
        with zipfile.ZipFile(path, "r") as zf:
            entry = find_unityframework_entry(zf)
            info = zf.getinfo(entry)
            if progress:
                progress(f"读取 {entry} ({info.file_size / 1024 / 1024:.1f} MiB)…")
            framework = zf.read(entry)
    except zipfile.BadZipFile:
        raise ToolError("文件不是有效的 IPA/ZIP")
    meta = find_startup_blob(framework, progress)
    return IpaBlob(path, entry, framework, **meta)


def serialize_json_for_slot(text: str, cipher_len: int):
    try:
        obj = json.loads(text)
    except Exception as e:
        raise ToolError(f"JSON 无效：{e}")
    if not isinstance(obj, dict):
        raise ToolError("Startup 配置顶层必须是 JSON object")

    current = text.encode("utf-8")
    if len(current) <= cipher_len:
        return obj, current, "原编辑文本"

    compact_text = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    compact = compact_text.encode("utf-8")
    if len(compact) <= cipher_len:
        return obj, compact, "自动紧凑 JSON"

    raise ToolError(
        f"修改后的完整 JSON 仍然过长：{len(compact)} bytes > 固定槽位 {cipher_len} bytes。\n"
        "为避免删除 GameFindStr/未知字段，已停止写入。"
    )


def patch_ipa(blob: IpaBlob, edited_json: str, out_path: str, progress=None):
    obj, plain, serialization_mode = serialize_json_for_slot(edited_json, blob.cipher_len)
    key = blob.key_text.encode("ascii")
    padded = zero_pad_fixed(plain, blob.cipher_len)
    cipher = AES.new(key, AES.MODE_ECB).encrypt(padded)
    b64 = base64.b64encode(cipher)
    if len(b64) != blob.b64_len:
        raise ToolError(f"Base64 槽位长度变化：{len(b64)} != 原始 {blob.b64_len}，停止写入")

    fw = bytearray(blob.framework_bytes)
    fw[blob.b64_offset:blob.b64_offset + blob.b64_len] = b64

    verify_cipher = base64.b64decode(bytes(fw[blob.b64_offset:blob.b64_offset + blob.b64_len]), validate=True)
    verify_plain = zero_unpad(AES.new(key, AES.MODE_ECB).decrypt(verify_cipher))
    try:
        verify_obj = json.loads(verify_plain.decode("utf-8"))
    except Exception as e:
        raise ToolError(f"写回前自验证失败：{e}")
    if verify_obj != obj:
        raise ToolError("写回前自验证失败：JSON 语义不一致")

    out_path = str(out_path)
    tmp_out = out_path + ".tmp"
    if os.path.exists(tmp_out):
        os.remove(tmp_out)
    if progress:
        progress("重新打包 IPA…")

    try:
        with zipfile.ZipFile(blob.ipa_path, "r") as zin, zipfile.ZipFile(tmp_out, "w", allowZip64=True) as zout:
            infos = zin.infolist()
            for idx, info in enumerate(infos, 1):
                data = bytes(fw) if info.filename == blob.entry_name else zin.read(info.filename)
                zout.writestr(info, data)
                if progress and idx % 100 == 0:
                    progress(f"重新打包 IPA… {idx}/{len(infos)}")
        os.replace(tmp_out, out_path)
    except Exception:
        try:
            if os.path.exists(tmp_out):
                os.remove(tmp_out)
        except Exception:
            pass
        raise

    report = {
        "tool": f"IP加解密工具 v{APP_VERSION}",
        "source_ipa": os.path.abspath(blob.ipa_path),
        "output_ipa": os.path.abspath(out_path),
        "entry": blob.entry_name,
        "blob_offset": f"0x{blob.blob_offset:X}",
        "key": blob.key_text,
        "plain_length_before": blob.plain_len,
        "plain_length_after": len(plain),
        "cipher_length": blob.cipher_len,
        "base64_length": blob.b64_len,
        "serialization": serialization_mode,
        "gamefindstr_count": len(obj.get("GameFindStr", [])) if isinstance(obj.get("GameFindStr"), list) else None,
        "verified": True,
        "resign_required": True,
    }
    report_path = out_path + ".report.json"
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    with open(out_path + ".after.decrypted.json", "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    return report, report_path


class App:
    def __init__(self, root):
        self.root = root
        self.root.title(APP_TITLE)
        self.root.geometry("980x720")
        self.root.minsize(820, 600)
        self.last_key = ""
        self.ipa_blob = None
        self.mode = "text"
        self.busy = False
        self._build_ui()
        self._set_mode("text")

    def _build_ui(self):
        top = ttk.Frame(self.root, padding=(10, 8))
        top.pack(fill="x")
        ttk.Label(top, text="www.lyzwlkj.vip", font=("Microsoft YaHei UI", 11, "bold")).pack(side="left")
        self.mode_label = ttk.Label(top, text="文本模式")
        self.mode_label.pack(side="left", padx=(16, 0))

        self.btn_ipa = ttk.Button(top, text="加载 IPA", command=self.load_ipa)
        self.btn_ipa.pack(side="right", padx=(6, 0))
        ttk.Button(top, text="保存文本", command=self.save_text_file).pack(side="right", padx=(6, 0))
        ttk.Button(top, text="加载文本", command=self.load_text_file).pack(side="right", padx=(6, 0))

        keybar = ttk.Frame(self.root, padding=(10, 0, 10, 6))
        keybar.pack(fill="x")
        ttk.Label(keybar, text="AES Key：").pack(side="left")
        self.key_var = tk.StringVar()
        ttk.Entry(keybar, textvariable=self.key_var, width=28).pack(side="left")
        self.path_var = tk.StringVar(value="未加载 IPA")
        ttk.Label(keybar, textvariable=self.path_var).pack(side="left", padx=(16, 0), fill="x", expand=True)

        paned = ttk.Panedwindow(self.root, orient="vertical")
        paned.pack(fill="both", expand=True, padx=10, pady=(0, 8))

        editor_frame = ttk.Frame(paned)
        paned.add(editor_frame, weight=4)
        ttk.Label(editor_frame, text="内容 / 解密后的 JSON").pack(anchor="w")
        self.text = tk.Text(editor_frame, wrap="none", font=("Consolas", 10), undo=True)
        sy = ttk.Scrollbar(editor_frame, orient="vertical", command=self.text.yview)
        sx = ttk.Scrollbar(editor_frame, orient="horizontal", command=self.text.xview)
        self.text.configure(yscrollcommand=sy.set, xscrollcommand=sx.set)
        self.text.pack(side="left", fill="both", expand=True)
        sy.pack(side="right", fill="y")
        sx.pack(side="bottom", fill="x")

        status_frame = ttk.Frame(paned)
        paned.add(status_frame, weight=1)
        ttk.Label(status_frame, text="IPA 动态处理结果").pack(anchor="w")
        self.status = tk.Text(status_frame, height=9, wrap="word", font=("Consolas", 9), state="disabled")
        self.status.pack(fill="both", expand=True)

        buttons = ttk.Frame(self.root, padding=(10, 0, 10, 10))
        buttons.pack(fill="x")
        self.btn_decrypt = ttk.Button(buttons, text="解密", command=self.decrypt_action)
        self.btn_decrypt.pack(side="left")
        self.btn_encrypt = ttk.Button(buttons, text="加密", command=self.encrypt_action)
        self.btn_encrypt.pack(side="left", padx=(8, 0))
        ttk.Button(buttons, text="复制结果", command=self.copy_result).pack(side="left", padx=(8, 0))
        self.progress = ttk.Progressbar(buttons, mode="indeterminate", length=180)
        self.progress.pack(side="right")

    def log(self, msg):
        def _do():
            self.status.configure(state="normal")
            self.status.insert("end", msg + "\n")
            self.status.see("end")
            self.status.configure(state="disabled")
        self.root.after(0, _do)

    def clear_log(self):
        self.status.configure(state="normal")
        self.status.delete("1.0", "end")
        self.status.configure(state="disabled")

    def set_busy(self, busy):
        self.busy = busy
        if busy:
            self.progress.start(10)
            self.btn_ipa.configure(state="disabled")
            self.btn_decrypt.configure(state="disabled")
            self.btn_encrypt.configure(state="disabled")
        else:
            self.progress.stop()
            self.btn_ipa.configure(state="normal")
            self.btn_decrypt.configure(state="normal")
            self.btn_encrypt.configure(state="normal")

    def run_worker(self, fn):
        if self.busy:
            return
        self.set_busy(True)
        def worker():
            try:
                fn()
            except ToolError as e:
                self.root.after(0, lambda: messagebox.showerror("处理失败", str(e)))
                self.log("[失败] " + str(e))
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror("处理失败", repr(e)))
                self.log("[异常] " + repr(e))
            finally:
                self.root.after(0, lambda: self.set_busy(False))
        threading.Thread(target=worker, daemon=True).start()

    def _set_mode(self, mode):
        self.mode = mode
        if mode == "ipa":
            self.mode_label.configure(text="IPA模式")
            self.btn_decrypt.configure(text="重新解密 IPA")
            self.btn_encrypt.configure(text="加密并生成 IPA")
        else:
            self.mode_label.configure(text="文本模式")
            self.btn_decrypt.configure(text="解密")
            self.btn_encrypt.configure(text="加密")
            self.path_var.set("未加载 IPA")

    def load_text_file(self):
        path = filedialog.askopenfilename(title="加载文本文件", filetypes=[("文本文件", "*.txt;*.json"), ("所有文件", "*.*")])
        if not path:
            return
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            messagebox.showerror("加载失败", str(e))
            return
        self._set_mode("text")
        self.text.delete("1.0", "end")
        self.text.insert("1.0", content)
        self.clear_log()
        self.log(f"已加载文本：{path}")

    def save_text_file(self):
        path = filedialog.asksaveasfilename(title="保存文本", defaultextension=".txt", filetypes=[("文本文件", "*.txt"), ("JSON", "*.json"), ("所有文件", "*.*")])
        if not path:
            return
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(self.text.get("1.0", "end-1c"))
            messagebox.showinfo("完成", "已保存")
        except Exception as e:
            messagebox.showerror("保存失败", str(e))

    def load_ipa(self):
        path = filedialog.askopenfilename(title="加载 IPA", filetypes=[("iOS IPA", "*.ipa"), ("ZIP", "*.zip"), ("所有文件", "*.*")])
        if not path:
            return
        self.clear_log()
        self.log(f"文件：{path}")
        self.path_var.set(os.path.basename(path))
        def task():
            blob = load_ipa_blob(path, self.log)
            self.ipa_blob = blob
            self.last_key = blob.key_text
            def update_ui():
                self._set_mode("ipa")
                self.key_var.set(blob.key_text)
                self.text.delete("1.0", "end")
                self.text.insert("1.0", json.dumps(blob.json_obj, ensure_ascii=False, indent=2))
                self.log(f"entry        : {blob.entry_name}")
                self.log(f"blob offset  : 0x{blob.blob_offset:X}")
                self.log(f"AES key      : {blob.key_text}")
                self.log(f"plain length : {blob.plain_len}")
                self.log(f"cipher length: {blob.cipher_len}")
                self.log(f"base64 length: {blob.b64_len}")
                self.log(f"JSON keys    : {len(blob.json_obj)}")
                gf = blob.json_obj.get("GameFindStr")
                self.log(f"GameFindStr  : {len(gf) if isinstance(gf, list) else 'N/A'}")
                self.log("状态          : 解密成功，可编辑 JSON 后点击“加密并生成 IPA”")
            self.root.after(0, update_ui)
        self.run_worker(task)

    def decrypt_action(self):
        if self.mode == "ipa":
            if not self.ipa_blob:
                return self.load_ipa()
            path = self.ipa_blob.ipa_path
            self.clear_log()
            self.log(f"重新读取：{path}")
            def task():
                blob = load_ipa_blob(path, self.log)
                self.ipa_blob = blob
                self.last_key = blob.key_text
                def ui():
                    self.key_var.set(blob.key_text)
                    self.text.delete("1.0", "end")
                    self.text.insert("1.0", json.dumps(blob.json_obj, ensure_ascii=False, indent=2))
                    self.log(f"重新解密成功：offset=0x{blob.blob_offset:X}, plain={blob.plain_len}, cipher={blob.cipher_len}")
                self.root.after(0, ui)
            return self.run_worker(task)

        src = self.text.get("1.0", "end-1c")
        try:
            plain, key, cipher_len = decrypt_text_blob(src)
        except ToolError as e:
            return messagebox.showerror("解密失败", str(e))
        self.last_key = key
        self.key_var.set(key)
        self.text.delete("1.0", "end")
        self.text.insert("1.0", plain)
        self.clear_log()
        self.log(f"文本解密成功：AES-128-ECB / ZeroPadding / cipher={cipher_len} bytes")

    def encrypt_action(self):
        if self.mode == "ipa":
            blob = self.ipa_blob
            if not blob:
                return messagebox.showwarning("提示", "请先加载 IPA")
            edited = self.text.get("1.0", "end-1c")
            src = Path(blob.ipa_path)
            default_name = src.stem + "_IPAPatch_v2" + src.suffix
            out = filedialog.asksaveasfilename(title="生成修改后的 IPA", initialdir=str(src.parent), initialfile=default_name, defaultextension=".ipa", filetypes=[("iOS IPA", "*.ipa")])
            if not out:
                return
            self.clear_log()
            self.log("开始加密并写回 IPA…")
            def task():
                report, report_path = patch_ipa(blob, edited, out, self.log)
                self.log(f"输出 IPA      : {out}")
                self.log(f"plain length  : {report['plain_length_before']} -> {report['plain_length_after']}")
                self.log(f"cipher length : {report['cipher_length']} (fixed)")
                self.log(f"base64 length : {report['base64_length']} (fixed)")
                self.log(f"serialization : {report['serialization']}")
                self.log(f"GameFindStr   : {report['gamefindstr_count']}")
                self.log("验证           : PASS")
                self.log("注意           : 输出 IPA 必须重新签名")
                self.root.after(0, lambda: messagebox.showinfo("完成", f"IPA 已生成并通过回读验证。\n\n{out}\n\n请重新签名后安装。"))
            return self.run_worker(task)

        plain = self.text.get("1.0", "end-1c")
        key = self.key_var.get().strip() or self.last_key
        try:
            result = encrypt_text_blob(plain, key)
        except ToolError as e:
            return messagebox.showerror("加密失败", str(e))
        self.last_key = key
        self.text.delete("1.0", "end")
        self.text.insert("1.0", result)
        self.clear_log()
        self.log("文本加密成功：Key(16字节) + Base64(AES-128-ECB/ZeroPadding)")

    def copy_result(self):
        content = self.text.get("1.0", "end-1c")
        self.root.clipboard_clear()
        self.root.clipboard_append(content)
        messagebox.showinfo("完成", "已复制到剪贴板")


def main():
    root = tk.Tk()
    try:
        style = ttk.Style(root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
    except Exception:
        pass
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
