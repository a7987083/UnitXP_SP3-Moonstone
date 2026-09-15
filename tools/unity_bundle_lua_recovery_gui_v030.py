#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
import traceback
from pathlib import Path

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    DND_AVAILABLE = True
except Exception:
    DND_FILES = None
    TkinterDnD = None
    DND_AVAILABLE = False

from unity_bundle_lua_recovery_v030 import APP_VERSION, scan_combined, self_test

APP_NAME = "Unity Bundle Lua Recovery Combined"


def default_output() -> Path:
    desktop = Path.home() / "Desktop"
    base = desktop if desktop.exists() else Path.home()
    return base / "UnityBundleLuaRecovery_v030_Output"


class App:
    def __init__(self, root):
        self.root = root
        self.input_dir = tk.StringVar()
        self.capture_dir = tk.StringVar()
        self.output_dir = tk.StringVar(value=str(default_output()))
        self.deep_scan = tk.BooleanVar(value=True)
        self.status = tk.StringVar(value="就绪")
        self.progress = tk.DoubleVar(value=0)
        self.events: queue.Queue = queue.Queue()
        self.worker = None
        self._build()
        self.root.after(100, self._drain)

    def _build(self):
        self.root.title(f"{APP_NAME} v{APP_VERSION}")
        self.root.geometry("1040x800")
        self.root.minsize(880, 680)
        outer = ttk.Frame(self.root, padding=16)
        outer.pack(fill="both", expand=True)

        ttk.Label(outer, text=f"{APP_NAME} v{APP_VERSION}", font=("Segoe UI", 19, "bold")).pack(anchor="w")
        ttk.Label(
            outer,
            text="Bundle + 手机 FullSweep 双源合并 / SHA256 去重 / 完整+部分静态恢复 / 不执行 Lua",
            font=("Segoe UI", 9),
        ).pack(anchor="w", pady=(2, 10))

        tk.Label(
            outer,
            text="重要：第一个目录请选“爱思导出的整个游戏数据根目录”，不要只选 Bundles 子目录。",
            anchor="w", bg="#fff7ed", fg="#9a3412", padx=8, pady=6,
        ).pack(fill="x", pady=(0, 10))

        inp = ttk.LabelFrame(outer, text="① 游戏数据根目录（必选）", padding=10)
        inp.pack(fill="x")
        ttk.Entry(inp, textvariable=self.input_dir).pack(side="left", fill="x", expand=True)
        ttk.Button(inp, text="选择目录", command=self.choose_input).pack(side="left", padx=(8, 0))

        cap = ttk.LabelFrame(outer, text="② 手机 JSONCapture/FullSweep 目录（可选，推荐）", padding=10)
        cap.pack(fill="x", pady=(8, 0))
        ttk.Entry(cap, textvariable=self.capture_dir).pack(side="left", fill="x", expand=True)
        ttk.Button(cap, text="选择目录", command=self.choose_capture).pack(side="left", padx=(8, 0))
        ttk.Button(cap, text="清空", command=lambda: self.capture_dir.set("")).pack(side="left", padx=(8, 0))

        drop = tk.Label(
            outer,
            text="拖入目录：第一次拖入=游戏数据根目录；第二次拖入=手机 FullSweep",
            relief="groove", bd=1, height=3, bg="#f5f7fa", fg="#334155", font=("Segoe UI", 10),
        )
        drop.pack(fill="x", pady=8)
        if DND_AVAILABLE:
            drop.drop_target_register(DND_FILES)
            drop.dnd_bind("<<Drop>>", self.on_drop)
        else:
            drop.configure(text=drop.cget("text") + "\n（当前环境无拖放组件）")

        out = ttk.LabelFrame(outer, text="③ 输出目录", padding=10)
        out.pack(fill="x")
        ttk.Entry(out, textvariable=self.output_dir).pack(side="left", fill="x", expand=True)
        ttk.Button(out, text="选择目录", command=self.choose_output).pack(side="left", padx=(8, 0))
        ttk.Button(out, text="打开输出", command=self.open_output).pack(side="left", padx=(8, 0))

        opts = ttk.Frame(outer)
        opts.pack(fill="x", pady=(10, 6))
        ttk.Checkbutton(
            opts, variable=self.deep_scan,
            text="深度扫描（推荐：不仅按 UnityFS 魔数，也尝试缓存/资源/热更新目录候选）",
        ).pack(side="left")
        self.start_btn = ttk.Button(opts, text="开始 Combined Recovery", command=self.start)
        self.start_btn.pack(side="right")

        prog = ttk.Frame(outer)
        prog.pack(fill="x", pady=(4, 8))
        ttk.Progressbar(prog, variable=self.progress, maximum=100).pack(side="left", fill="x", expand=True, padx=(0, 10))
        ttk.Label(prog, textvariable=self.status, width=42).pack(side="right")

        logf = ttk.LabelFrame(outer, text="日志", padding=6)
        logf.pack(fill="both", expand=True)
        self.log = tk.Text(logf, wrap="word", font=("Consolas", 9), state="disabled")
        ys = ttk.Scrollbar(logf, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=ys.set)
        self.log.pack(side="left", fill="both", expand=True)
        ys.pack(side="right", fill="y")
        self._log("v0.3.0：读取原始文件，不修改；不会执行 Lua。")
        self._log("输出：recovered_complete / recovered_partial / dynamic_lua / combined_recovery_report.json / summary.json。")

    def _log(self, text):
        self.log.configure(state="normal")
        self.log.insert("end", str(text).rstrip() + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def choose_input(self):
        p = filedialog.askdirectory(title="选择爱思导出的整个游戏数据根目录")
        if p:
            self.input_dir.set(p)

    def choose_capture(self):
        p = filedialog.askdirectory(title="选择 Documents/JSONCapture/FullSweep 目录")
        if p:
            self.capture_dir.set(p)

    def choose_output(self):
        p = filedialog.askdirectory(title="选择输出目录", initialdir=self.output_dir.get())
        if p:
            self.output_dir.set(p)

    def open_output(self):
        p = Path(self.output_dir.get()).expanduser()
        p.mkdir(parents=True, exist_ok=True)
        try:
            if sys.platform == "win32":
                os.startfile(str(p))
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(p)])
            else:
                subprocess.Popen(["xdg-open", str(p)])
        except Exception as exc:
            messagebox.showerror("无法打开目录", str(exc))

    def on_drop(self, event):
        try:
            parts = list(self.root.tk.splitlist(event.data))
        except Exception:
            parts = [event.data]
        for raw in parts:
            p = Path(raw.strip().strip('"'))
            if not p.is_dir():
                continue
            if not self.input_dir.get():
                self.input_dir.set(str(p))
            elif not self.capture_dir.get():
                self.capture_dir.set(str(p))
            else:
                self.input_dir.set(str(p))
            return

    def start(self):
        if self.worker and self.worker.is_alive():
            return
        inp = Path(self.input_dir.get()).expanduser()
        cap_text = self.capture_dir.get().strip()
        cap = Path(cap_text).expanduser() if cap_text else None
        out = Path(self.output_dir.get()).expanduser()
        if not inp.is_dir():
            messagebox.showwarning("输入无效", "请选择有效的游戏数据根目录。")
            return
        if cap and not cap.is_dir():
            messagebox.showwarning("手机目录无效", "手机 FullSweep 目录不存在；请重新选择或清空。")
            return
        if inp.name.lower() in {"bundle", "bundles", "cache", "caches"}:
            ok = messagebox.askyesno(
                "可能漏资源",
                f"你选择的是子目录：{inp.name}\n\n"
                "v0.3 建议选择它的上一级“整个爱思导出数据根目录”，否则其它 Bundle 可能不会进入电脑扫描。\n\n"
                "仍然继续吗？",
            )
            if not ok:
                return
        out.mkdir(parents=True, exist_ok=True)
        self.start_btn.configure(state="disabled")
        self.progress.set(0)
        self.status.set("扫描游戏数据…")
        self.worker = threading.Thread(
            target=self._work, args=(inp, out, cap, self.deep_scan.get()), daemon=True,
        )
        self.worker.start()

    def _work(self, inp: Path, out: Path, cap: Path | None, deep: bool):
        try:
            stats = scan_combined(
                inp, out, capture_root=cap,
                callback=lambda e: self.events.put(("event", e)), deep=deep,
            )
            self.events.put(("done", stats))
        except Exception:
            self.events.put(("error", traceback.format_exc()))

    def _drain(self):
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "event":
                    e = payload
                    stage = e.get("stage")
                    if stage == "inventory":
                        self._log(f"游戏数据：发现文件 {e['files']}，Bundle 候选 {e['candidates']}")
                        self.status.set(f"Bundle 候选 {e['candidates']}")
                    elif stage == "bundle":
                        cur, total = e["current"], e["total"]
                        self.progress.set((cur / total * 65) if total else 0)
                        self.status.set(f"解析 Bundle {cur}/{total}")
                        if cur <= 20 or cur % 100 == 0 or cur == total:
                            self._log(f"[Bundle {cur}/{total}] {e['path']} ({e['reason']})")
                    elif stage == "phone_inventory":
                        self._log(f"手机 FullSweep：文件 {e['files']}，Lua/Raw 候选 {e['interesting']}")
                        self.status.set(f"导入手机抓取 {e['interesting']} 个文件")
                    elif stage == "phone":
                        cur, total = e["current"], e["total"]
                        self.progress.set(65 + (cur / total * 10 if total else 10))
                        self.status.set(f"导入手机抓取 {cur}/{total}")
                    elif stage == "recover":
                        cur, total = e["current"], e["total"]
                        self.progress.set(75 + (cur / total * 25 if total else 25))
                        self.status.set(f"恢复 Lua 表 {cur}/{total}")
                        if e.get("status") != "dynamic" or cur % 100 == 0:
                            self._log(f"[恢复] {e['group']} -> {e['status']}")
                elif kind == "done":
                    self.progress.set(100)
                    self.status.set("完成")
                    self._log("完成：\n" + json.dumps(payload, ensure_ascii=False, indent=2))
                    self.start_btn.configure(state="normal")
                    tables = payload.get("tables_complete", 0) + payload.get("tables_partial", 0)
                    records = payload.get("records_complete", 0) + payload.get("records_partial", 0)
                    messagebox.showinfo(
                        "完成",
                        "Combined Recovery 完成。\n"
                        f"唯一 Lua：{payload.get('combined_unique_lua', 0)}\n"
                        f"完整表：{payload.get('tables_complete', 0)}\n"
                        f"部分表：{payload.get('tables_partial', 0)}\n"
                        f"总输出表：{tables}\n"
                        f"总记录：{records}\n"
                        f"动态业务组：{payload.get('groups_dynamic', 0)}",
                    )
                elif kind == "error":
                    self.status.set("失败")
                    self._log(payload)
                    self.start_btn.configure(state="normal")
                    messagebox.showerror("处理失败", payload[-2200:])
        except queue.Empty:
            pass
        self.root.after(100, self._drain)


def main():
    if "--self-test" in sys.argv:
        self_test()
        return
    Root = TkinterDnD.Tk if DND_AVAILABLE else tk.Tk
    root = Root()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
