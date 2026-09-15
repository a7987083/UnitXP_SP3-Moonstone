#!/usr/bin/env python3
"""Windows GUI frontend for deterministic Lua 5.3 static table recovery."""
from __future__ import annotations

import hashlib
import json
import os
import queue
import re
import subprocess
import sys
import threading
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    DND_AVAILABLE = True
except Exception:
    DND_FILES = None
    TkinterDnD = None
    DND_AVAILABLE = False

from lua53_static_recover import parse_chunk, recover

APP_NAME = "Lua 5.3 Static Recovery"
APP_VERSION = "0.1.0"
WINDOW_TITLE = f"{APP_NAME} v{APP_VERSION}"
SUPPORTED_HINT = "Lua 5.3 official-layout / observed format=1 static TAB_* chunks"


def format_size(n: int) -> str:
    value = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024.0 or unit == "GB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.2f} {unit}"
        value /= 1024.0
    return f"{n} B"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def safe_folder_name(path: Path) -> str:
    name = re.sub(r"[^0-9A-Za-z._-]+", "_", path.name).strip("._")
    return name[:96] or "recovered"


def default_output_root() -> Path:
    desktop = Path.home() / "Desktop"
    return (desktop if desktop.exists() else Path.home()) / "Lua53StaticRecovery_Output"


@dataclass
class InputItem:
    path: Path
    size: int = 0
    sha256: str = ""
    format_byte: str = "-"
    status: str = "待处理"
    records: str = "-"
    instructions: str = "-"
    output_dir: str = ""
    error: str = ""


def inspect_input(path: Path) -> InputItem:
    item = InputItem(path=path, size=path.stat().st_size)
    item.sha256 = sha256_file(path)
    try:
        _raw, meta, root = parse_chunk(path)
        item.format_byte = str(meta.get("format", "?"))
        item.instructions = str(len(root.get("code", [])))
        item.status = "已识别"
    except Exception as e:
        item.status = "无法解析"
        item.error = str(e)
    return item


def recover_one(input_path: Path, output_root: Path) -> dict:
    output_dir = output_root / safe_folder_name(input_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    report, paths = recover(str(input_path), str(output_dir))
    return {"input": str(input_path), "output_dir": str(output_dir), "report": report, "paths": paths}


def parse_dropped_files(root: tk.Misc, data: str) -> list[Path]:
    try:
        parts = list(root.tk.splitlist(data))
    except Exception:
        parts = [data]
    result: list[Path] = []
    for raw in parts:
        p = Path(raw.strip().strip('"')).expanduser()
        if p.is_file():
            result.append(p)
        elif p.is_dir():
            for child in sorted(p.iterdir()):
                if child.is_file() and child.suffix.lower() in {".luac", ".bin", ".bytes"}:
                    result.append(child)
    return result


class RecoveryApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.items: dict[str, InputItem] = {}
        self.work_queue: queue.Queue = queue.Queue()
        self.worker: threading.Thread | None = None
        self.output_root = tk.StringVar(value=str(default_output_root()))
        self.status_var = tk.StringVar(value="就绪")
        self.progress_var = tk.DoubleVar(value=0.0)
        self._configure_root()
        self._configure_style()
        self._build_ui()
        self.root.after(100, self._drain_events)

    def _configure_root(self) -> None:
        self.root.title(WINDOW_TITLE)
        self.root.geometry("1120x760")
        self.root.minsize(900, 620)
        try:
            self.root.tk.call("tk", "scaling", 1.15)
        except Exception:
            pass

    def _configure_style(self) -> None:
        style = ttk.Style(self.root)
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Title.TLabel", font=("Segoe UI", 20, "bold"))
        style.configure("Subtitle.TLabel", font=("Segoe UI", 9))
        style.configure("Primary.TButton", padding=(18, 8), font=("Segoe UI", 10, "bold"))
        style.configure("Toolbar.TButton", padding=(10, 6))
        style.configure("Treeview", rowheight=27, font=("Segoe UI", 9))
        style.configure("Treeview.Heading", font=("Segoe UI", 9, "bold"))

    def _build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=18)
        outer.pack(fill="both", expand=True)

        header = ttk.Frame(outer)
        header.pack(fill="x")
        ttk.Label(header, text=APP_NAME, style="Title.TLabel").pack(anchor="w")
        ttk.Label(header, text=f"v{APP_VERSION} · {SUPPORTED_HINT} · 静态白名单执行，不运行任意 Lua 代码", style="Subtitle.TLabel").pack(anchor="w", pady=(3, 0))

        toolbar = ttk.Frame(outer)
        toolbar.pack(fill="x", pady=(14, 10))
        ttk.Button(toolbar, text="添加文件", command=self.add_files, style="Toolbar.TButton").pack(side="left")
        ttk.Button(toolbar, text="添加目录", command=self.add_folder, style="Toolbar.TButton").pack(side="left", padx=(6, 0))
        ttk.Button(toolbar, text="移除选中", command=self.remove_selected, style="Toolbar.TButton").pack(side="left", padx=(6, 0))
        ttk.Button(toolbar, text="清空", command=self.clear_all, style="Toolbar.TButton").pack(side="left", padx=(6, 0))
        ttk.Button(toolbar, text="打开输出目录", command=self.open_output, style="Toolbar.TButton").pack(side="right")

        drop = tk.Label(outer, text="拖放 .luac / .bin / .bytes 到这里\n也可以直接拖入包含这些文件的目录", justify="center", height=3, relief="groove", bd=1, bg="#f5f7fa", fg="#334155", font=("Segoe UI", 10))
        drop.pack(fill="x", pady=(0, 10))
        if DND_AVAILABLE:
            drop.drop_target_register(DND_FILES)
            drop.dnd_bind("<<Drop>>", self._on_drop)
        else:
            drop.configure(text=drop.cget("text") + "\n（当前 Python 环境未加载拖放组件；EXE 构建版会包含）")

        table_frame = ttk.Frame(outer)
        table_frame.pack(fill="both", expand=True)
        columns = ("file", "size", "sha", "fmt", "records", "ins", "status")
        self.tree = ttk.Treeview(table_frame, columns=columns, show="headings", selectmode="extended")
        headings = {"file": "文件", "size": "大小", "sha": "SHA-256", "fmt": "Format", "records": "Records", "ins": "Instructions", "status": "状态"}
        widths = {"file": 360, "size": 90, "sha": 145, "fmt": 70, "records": 85, "ins": 100, "status": 120}
        for c in columns:
            self.tree.heading(c, text=headings[c])
            self.tree.column(c, width=widths[c], minwidth=55, anchor="w" if c in {"file", "status"} else "center")
        yscroll = ttk.Scrollbar(table_frame, orient="vertical", command=self.tree.yview)
        xscroll = ttk.Scrollbar(table_frame, orient="horizontal", command=self.tree.xview)
        self.tree.configure(yscrollcommand=yscroll.set, xscrollcommand=xscroll.set)
        self.tree.grid(row=0, column=0, sticky="nsew")
        yscroll.grid(row=0, column=1, sticky="ns")
        xscroll.grid(row=1, column=0, sticky="ew")
        table_frame.rowconfigure(0, weight=1)
        table_frame.columnconfigure(0, weight=1)

        output = ttk.LabelFrame(outer, text="输出", padding=10)
        output.pack(fill="x", pady=(10, 8))
        ttk.Entry(output, textvariable=self.output_root).pack(side="left", fill="x", expand=True)
        ttk.Button(output, text="选择目录", command=self.choose_output).pack(side="left", padx=(8, 0))

        action = ttk.Frame(outer)
        action.pack(fill="x")
        self.progress = ttk.Progressbar(action, variable=self.progress_var, maximum=100)
        self.progress.pack(side="left", fill="x", expand=True, padx=(0, 10))
        ttk.Label(action, textvariable=self.status_var, width=28).pack(side="left")
        self.start_button = ttk.Button(action, text="开始恢复", command=self.start_recovery, style="Primary.TButton")
        self.start_button.pack(side="right")

        log_frame = ttk.LabelFrame(outer, text="日志", padding=6)
        log_frame.pack(fill="both", pady=(10, 0))
        self.log = tk.Text(log_frame, height=8, wrap="word", font=("Consolas", 9), state="disabled")
        log_scroll = ttk.Scrollbar(log_frame, orient="vertical", command=self.log.yview)
        self.log.configure(yscrollcommand=log_scroll.set)
        self.log.pack(side="left", fill="both", expand=True)
        log_scroll.pack(side="right", fill="y")
        self._log("GUI 已启动。原始输入不会被修改；format=0 仅写入输出副本。")
        self._log("拖放组件：可用。" if DND_AVAILABLE else "拖放组件：当前解释器不可用，仍可用“添加文件/目录”。")

    def _log(self, text: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", text.rstrip() + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def _on_drop(self, event) -> None:
        self._add_paths(parse_dropped_files(self.root, event.data))

    def add_files(self) -> None:
        selected = filedialog.askopenfilenames(title="选择 Lua bytecode 文件", filetypes=[("Lua bytecode", "*.luac *.bin *.bytes"), ("所有文件", "*.*")])
        self._add_paths(Path(p) for p in selected)

    def add_folder(self) -> None:
        folder = filedialog.askdirectory(title="选择包含 bytecode 的目录")
        if not folder:
            return
        p = Path(folder)
        self._add_paths(x for x in sorted(p.iterdir()) if x.is_file() and x.suffix.lower() in {".luac", ".bin", ".bytes"})

    def _add_paths(self, paths: Iterable[Path]) -> None:
        added = 0
        for path in paths:
            try:
                path = path.resolve()
                if not path.is_file():
                    continue
                key = str(path).lower()
                if key in self.items:
                    continue
                item = inspect_input(path)
                self.items[key] = item
                self.tree.insert("", "end", iid=key, values=self._row_values(item))
                added += 1
                if item.error:
                    self._log(f"[预检失败] {path.name}: {item.error}")
                else:
                    self._log(f"[已添加] {path.name} | {format_size(item.size)} | SHA256={item.sha256}")
            except Exception as e:
                self._log(f"[添加失败] {path}: {e}")
        self.status_var.set(f"已添加 {len(self.items)} 个文件")
        if added == 0 and self.items:
            self._log("没有新增文件（可能已在列表中）。")

    def _row_values(self, item: InputItem):
        return (item.path.name, format_size(item.size), item.sha256[:16] + "…" if item.sha256 else "-", item.format_byte, item.records, item.instructions, item.status)

    def _refresh_item(self, key: str) -> None:
        if self.tree.exists(key):
            self.tree.item(key, values=self._row_values(self.items[key]))

    def remove_selected(self) -> None:
        if self.worker and self.worker.is_alive():
            return
        for iid in self.tree.selection():
            self.tree.delete(iid)
            self.items.pop(iid, None)
        self.status_var.set(f"剩余 {len(self.items)} 个文件")

    def clear_all(self) -> None:
        if self.worker and self.worker.is_alive():
            return
        for iid in self.tree.get_children():
            self.tree.delete(iid)
        self.items.clear()
        self.progress_var.set(0)
        self.status_var.set("就绪")

    def choose_output(self) -> None:
        folder = filedialog.askdirectory(title="选择输出根目录", initialdir=self.output_root.get())
        if folder:
            self.output_root.set(folder)

    def open_output(self) -> None:
        p = Path(self.output_root.get()).expanduser()
        p.mkdir(parents=True, exist_ok=True)
        try:
            if sys.platform == "win32":
                os.startfile(str(p))
            elif sys.platform == "darwin":
                subprocess.Popen(["open", str(p)])
            else:
                subprocess.Popen(["xdg-open", str(p)])
        except Exception as e:
            messagebox.showerror("无法打开目录", str(e))

    def start_recovery(self) -> None:
        if self.worker and self.worker.is_alive():
            return
        if not self.items:
            messagebox.showinfo("没有输入", "请先添加或拖入 .luac / .bin / .bytes 文件。")
            return
        invalid = [i.path.name for i in self.items.values() if i.status == "无法解析"]
        if invalid:
            messagebox.showwarning("存在无法解析的文件", "请先移除无法解析的文件：\n" + "\n".join(invalid[:8]))
            return
        output_root = Path(self.output_root.get()).expanduser()
        try:
            output_root.mkdir(parents=True, exist_ok=True)
        except Exception as e:
            messagebox.showerror("输出目录不可用", str(e))
            return
        self.start_button.configure(state="disabled")
        self.progress_var.set(0)
        self.status_var.set("恢复中…")
        snapshot = list(self.items.keys())
        for key in snapshot:
            self.items[key].status = "排队中"
            self.items[key].records = "-"
            self.items[key].error = ""
            self._refresh_item(key)
        self.worker = threading.Thread(target=self._worker_recover, args=(snapshot, output_root), daemon=True)
        self.worker.start()

    def _worker_recover(self, keys: list[str], output_root: Path) -> None:
        total = len(keys)
        success = 0
        for idx, key in enumerate(keys, 1):
            item = self.items.get(key)
            if item is None:
                continue
            self.work_queue.put(("status", key, "恢复中"))
            try:
                result = recover_one(item.path, output_root)
                report = result["report"]
                records = report.get("recovery", {}).get("records", "?")
                instructions = report.get("function", {}).get("instructions", "?")
                changed = report.get("format_normalization", {}).get("changed_zero_based_offsets", [])
                trailing = report.get("chunk", {}).get("trailing_bytes", "?")
                unsupported = report.get("execution", {}).get("unsupported_opcodes", [])
                self.work_queue.put(("done_one", key, result, records, instructions, changed, trailing, unsupported))
                success += 1
            except Exception as e:
                self.work_queue.put(("error_one", key, str(e), traceback.format_exc()))
            self.work_queue.put(("progress", idx * 100.0 / total, idx, total))
        self.work_queue.put(("finished", success, total, str(output_root)))

    def _drain_events(self) -> None:
        try:
            while True:
                event = self.work_queue.get_nowait()
                kind = event[0]
                if kind == "status":
                    _, key, status = event
                    if key in self.items:
                        self.items[key].status = status
                        self._refresh_item(key)
                elif kind == "done_one":
                    _, key, result, records, instructions, changed, trailing, unsupported = event
                    if key in self.items:
                        item = self.items[key]
                        item.status = "成功"
                        item.records = str(records)
                        item.instructions = str(instructions)
                        item.output_dir = result["output_dir"]
                        self._refresh_item(key)
                        self._log(f"[成功] {item.path.name} | records={records} | instructions={instructions} | trailing={trailing} | unsupported={len(unsupported)} | format-diff={changed}")
                        self._log(f"       输出: {item.output_dir}")
                elif kind == "error_one":
                    _, key, err, trace = event
                    if key in self.items:
                        item = self.items[key]
                        item.status = "失败"
                        item.error = err
                        self._refresh_item(key)
                        self._log(f"[失败] {item.path.name}: {err}")
                        self._log(trace.rstrip())
                elif kind == "progress":
                    _, percent, idx, total = event
                    self.progress_var.set(percent)
                    self.status_var.set(f"处理中 {idx}/{total}")
                elif kind == "finished":
                    _, success, total, output = event
                    self.start_button.configure(state="normal")
                    self.status_var.set(f"完成：{success}/{total} 成功")
                    self._log(f"[完成] 成功 {success}/{total}，输出根目录: {output}")
                    if success == total:
                        messagebox.showinfo("恢复完成", f"全部 {success} 个文件恢复成功。\n\n输出目录：\n{output}")
                    else:
                        messagebox.showwarning("恢复完成", f"成功 {success}/{total}。失败原因请查看日志。")
        except queue.Empty:
            pass
        self.root.after(100, self._drain_events)


def create_root() -> tk.Tk:
    return TkinterDnD.Tk() if DND_AVAILABLE else tk.Tk()


def self_test() -> int:
    payload = {"app": APP_NAME, "version": APP_VERSION, "python": sys.version.split()[0], "platform": sys.platform, "tkinterdnd2": DND_AVAILABLE, "recoverer_import": callable(recover), "parse_chunk_import": callable(parse_chunk)}
    print(json.dumps(payload, ensure_ascii=False))
    return 0 if payload["recoverer_import"] and payload["parse_chunk_import"] else 2


def main() -> None:
    if "--self-test" in sys.argv[1:]:
        raise SystemExit(self_test())
    root = create_root()
    RecoveryApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
