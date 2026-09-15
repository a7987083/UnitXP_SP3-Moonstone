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

from unity_bundle_lua_recovery import APP_VERSION, scan_game_root, self_test

APP_NAME = "Unity Bundle Lua Recovery"


def default_output() -> Path:
    desktop = Path.home() / "Desktop"
    base = desktop if desktop.exists() else Path.home()
    return base / "UnityBundleLuaRecovery_Output"


class App:
    def __init__(self, root):
        self.root = root
        self.input_dir = tk.StringVar()
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
        self.root.geometry("980x720")
        self.root.minsize(820, 600)
        outer = ttk.Frame(self.root, padding=16)
        outer.pack(fill="both", expand=True)

        ttk.Label(outer, text=APP_NAME, font=("Segoe UI", 20, "bold")).pack(anchor="w")
        ttk.Label(outer, text="游戏数据目录 → Unity Bundle → TextAsset → ENCM/XOR4D → Lua 5.3 → TAB JSON；不执行 Lua", font=("Segoe UI", 9)).pack(anchor="w", pady=(2, 12))

        inp = ttk.LabelFrame(outer, text="游戏数据目录", padding=10)
        inp.pack(fill="x")
        ttk.Entry(inp, textvariable=self.input_dir).pack(side="left", fill="x", expand=True)
        ttk.Button(inp, text="选择目录", command=self.choose_input).pack(side="left", padx=(8, 0))

        drop = tk.Label(outer, text="把从手机导出的游戏数据根目录拖到这里", relief="groove", bd=1, height=4, bg="#f5f7fa", fg="#334155", font=("Segoe UI", 11))
        drop.pack(fill="x", pady=10)
        if DND_AVAILABLE:
            drop.drop_target_register(DND_FILES)
            drop.dnd_bind("<<Drop>>", self.on_drop)
        else:
            drop.configure(text=drop.cget("text") + "\n（当前环境无拖放组件，仍可用“选择目录”）")

        out = ttk.LabelFrame(outer, text="输出目录", padding=10)
        out.pack(fill="x")
        ttk.Entry(out, textvariable=self.output_dir).pack(side="left", fill="x", expand=True)
        ttk.Button(out, text="选择目录", command=self.choose_output).pack(side="left", padx=(8, 0))
        ttk.Button(out, text="打开输出", command=self.open_output).pack(side="left", padx=(8, 0))

        opts = ttk.Frame(outer)
        opts.pack(fill="x", pady=(10, 6))
        ttk.Checkbutton(opts, variable=self.deep_scan, text="深度扫描（推荐：除 UnityFS 魔数外，也尝试缓存/Bundle/资源目录中的候选文件）").pack(side="left")
        self.start_btn = ttk.Button(opts, text="开始全量处理", command=self.start)
        self.start_btn.pack(side="right")

        prog = ttk.Frame(outer)
        prog.pack(fill="x", pady=(4, 8))
        ttk.Progressbar(prog, variable=self.progress, maximum=100).pack(side="left", fill="x", expand=True, padx=(0, 10))
        ttk.Label(prog, textvariable=self.status, width=36).pack(side="right")

        logf = ttk.LabelFrame(outer, text="日志", padding=6)
        logf.pack(fill="both", expand=True)
        self.log = tk.Text(logf, wrap="word", font=("Consolas", 9), state="disabled")
        ys = ttk.Scrollbar(logf, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=ys.set)
        self.log.pack(side="left", fill="both", expand=True)
        ys.pack(side="right", fill="y")
        self._log("原始游戏文件只读，不会修改。")
        self._log("输出包含 raw_textasset / decoded_lua / direct_json / recovered_json / summary.json。")

    def _log(self, text):
        self.log.configure(state="normal")
        self.log.insert("end", str(text).rstrip() + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def choose_input(self):
        p = filedialog.askdirectory(title="选择从手机导出的游戏数据根目录")
        if p: self.input_dir.set(p)

    def choose_output(self):
        p = filedialog.askdirectory(title="选择输出目录", initialdir=self.output_dir.get())
        if p: self.output_dir.set(p)

    def open_output(self):
        p = Path(self.output_dir.get()).expanduser()
        p.mkdir(parents=True, exist_ok=True)
        try:
            if sys.platform == "win32": os.startfile(str(p))
            elif sys.platform == "darwin": subprocess.Popen(["open", str(p)])
            else: subprocess.Popen(["xdg-open", str(p)])
        except Exception as exc:
            messagebox.showerror("无法打开目录", str(exc))

    def on_drop(self, event):
        try:
            parts = list(self.root.tk.splitlist(event.data))
        except Exception:
            parts = [event.data]
        for raw in parts:
            p = Path(raw.strip().strip('"'))
            if p.is_dir():
                self.input_dir.set(str(p))
                return

    def start(self):
        if self.worker and self.worker.is_alive(): return
        inp = Path(self.input_dir.get()).expanduser()
        out = Path(self.output_dir.get()).expanduser()
        if not inp.is_dir():
            messagebox.showwarning("输入无效", "请选择有效的游戏数据目录。")
            return
        out.mkdir(parents=True, exist_ok=True)
        self.start_btn.configure(state="disabled")
        self.progress.set(0)
        self.status.set("扫描中…")
        self.worker = threading.Thread(target=self._work, args=(inp, out, self.deep_scan.get()), daemon=True)
        self.worker.start()

    def _work(self, inp: Path, out: Path, deep: bool):
        try:
            stats = scan_game_root(inp, out, callback=lambda e: self.events.put(("event", e)), deep=deep)
            self.events.put(("done", stats))
        except Exception:
            self.events.put(("error", traceback.format_exc()))

    def _drain(self):
        try:
            while True:
                kind, payload = self.events.get_nowait()
                if kind == "event":
                    e = payload; stage = e.get("stage")
                    if stage == "inventory":
                        self._log(f"发现文件 {e['files']}，Bundle 候选 {e['candidates']}")
                        self.status.set(f"Bundle 候选 {e['candidates']}")
                    elif stage == "bundle":
                        cur, total = e["current"], e["total"]
                        self.progress.set((cur / total * 80) if total else 0)
                        self.status.set(f"解析 Bundle {cur}/{total}")
                        self._log(f"[{cur}/{total}] {e['path']} ({e['reason']})")
                    elif stage == "recover":
                        cur, total = e["current"], e["total"]
                        self.progress.set(80 + (cur / total * 20 if total else 20))
                        self.status.set(f"恢复 Lua 表 {cur}/{total}")
                        self._log(f"[恢复] {e['group']} -> {e['status']}")
                elif kind == "done":
                    self.progress.set(100)
                    self.status.set("完成")
                    self._log("完成：\n" + json.dumps(payload, ensure_ascii=False, indent=2))
                    self.start_btn.configure(state="normal")
                    messagebox.showinfo("完成", f"处理完成。\n恢复表：{payload.get('tables_recovered', 0)}\n恢复记录：{payload.get('records_recovered', 0)}")
                elif kind == "error":
                    self.status.set("失败")
                    self._log(payload)
                    self.start_btn.configure(state="normal")
                    messagebox.showerror("处理失败", payload[-1800:])
        except queue.Empty:
            pass
        self.root.after(100, self._drain)


def main():
    if "--self-test" in sys.argv:
        self_test(); return
    Root = TkinterDnD.Tk if DND_AVAILABLE else tk.Tk
    root = Root()
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
