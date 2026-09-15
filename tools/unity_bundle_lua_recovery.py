#!/usr/bin/env python3
"""Offline Unity AssetBundle -> TextAsset -> ENCM/Lua5.3 -> static TAB JSON recovery.

The tool never executes Lua bytecode. It parses Lua 5.3 chunks and interprets only a
small data-construction opcode allow-list. Inputs are never modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import struct
import sys
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

try:
    import UnityPy
except Exception:
    UnityPy = None

APP_VERSION = "0.2.0"
ENCM_XOR_KEY = 0x4D
MAX_STATIC_STEPS_FACTOR = 4
LFIELDS_PER_FLUSH = 50
UNITY_MAGIC = (b"UnityFS", b"UnityRaw", b"UnityWeb")
BUNDLE_EXTS = {".bundle", ".unity3d", ".assetbundle", ".ab", ".unityfs"}
PATH_HINTS = {"bundle", "asset", "cache", "caches", "res", "resource", "resources", "download", "patch", "update", "hot"}

OPNAMES = [
    "MOVE","LOADK","LOADKX","LOADBOOL","LOADNIL","GETUPVAL","GETTABUP","GETTABLE",
    "SETTABUP","SETUPVAL","SETTABLE","NEWTABLE","SELF","ADD","SUB","MUL","MOD","POW",
    "DIV","IDIV","BAND","BOR","BXOR","SHL","SHR","UNM","BNOT","NOT","LEN","CONCAT",
    "JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN","FORLOOP","FORPREP",
    "TFORCALL","TFORLOOP","SETLIST","CLOSURE","VARARG","EXTRAARG",
]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_name(text: str, limit: int = 150) -> str:
    s = re.sub(r"[^0-9A-Za-z._@+-]+", "_", text or "unnamed").strip("._")
    return (s or "unnamed")[:limit]


def looks_text(data: bytes) -> bool:
    if not data:
        return False
    sample = data[:32768]
    if b"\x00" in sample:
        return False
    bad = sum(1 for c in sample if c < 0x09 or (0x0D < c < 0x20))
    if bad * 50 > len(sample):
        return False
    try:
        sample.decode("utf-8")
        return True
    except UnicodeDecodeError:
        return False


def looks_json(data: bytes) -> bool:
    if not looks_text(data):
        return False
    try:
        json.loads(data.decode("utf-8-sig"))
        return True
    except Exception:
        return False


def has_lua53_signature(data: bytes) -> bool:
    return len(data) >= 6 and data[:5] == b"\x1bLua\x53"


def looks_lua_source(data: bytes, name: str = "") -> bool:
    if not looks_text(data):
        return False
    lower_name = (name or "").lower()
    if lower_name.endswith(".lua") or "/lua/" in lower_name or "\\lua\\" in lower_name:
        return True
    s = data[:32768].decode("utf-8", "ignore").lower()
    tokens = ("function ", "local ", "require(", "require ", "return ", " end", " then", "tab_", "setmetatable", "pairs(", "ipairs(")
    score = sum(1 for t in tokens if t in s)
    return score >= 2 or ("tab_" in s and "=" in s)


def decode_lua_candidate(raw: bytes, name: str = "") -> tuple[Optional[bytes], str]:
    if has_lua53_signature(raw):
        return raw, "plain-luac53"
    if len(raw) > 4 and raw[:4] == b"ENCM":
        decoded = bytes(b ^ ENCM_XOR_KEY for b in raw[4:])
        if has_lua53_signature(decoded) or looks_lua_source(decoded, name):
            return decoded, "encm-xor4d"
        return None, "encm-unknown"
    off = raw.find(b"\x1bLua\x53", 1, min(len(raw), 4097))
    if off > 0:
        return raw[off:], f"wrapped-luac53+{off}"
    if looks_lua_source(raw, name):
        return raw, "plain-lua-text"
    return None, "none"


class LuaTable:
    __slots__ = ("d", "order")
    def __init__(self):
        self.d = {}
        self.order = []
    def set(self, k, v):
        if k not in self.d:
            self.order.append(k)
        if v is None:
            self.d.pop(k, None)
        else:
            self.d[k] = v
    def get(self, k):
        return self.d.get(k)


class Parser:
    def __init__(self, data: bytes):
        self.b = data
        self.p = 0
        self.endian = "<"
        self.intsz = self.sizetsz = self.inssz = 4
        self.isz = self.nsz = 8
    def take(self, n: int) -> bytes:
        if self.p + n > len(self.b):
            raise EOFError(f"truncated @0x{self.p:x}, need {n}")
        out = self.b[self.p:self.p+n]
        self.p += n
        return out
    def u8(self): return self.take(1)[0]
    def uint(self, n): return int.from_bytes(self.take(n), "little" if self.endian == "<" else "big")
    def sint(self, n): return int.from_bytes(self.take(n), "little" if self.endian == "<" else "big", signed=True)
    def count(self):
        n = self.sint(self.intsz)
        if n < 0 or n > 100_000_000:
            raise ValueError(f"invalid count {n} @0x{self.p:x}")
        return n
    def string(self):
        n = self.u8()
        if n == 0:
            return None
        if n == 0xFF:
            n = self.uint(self.sizetsz)
        if n < 1:
            raise ValueError("invalid string size")
        return self.take(n - 1).decode("utf-8", "surrogateescape")


def fields(i: int):
    op = i & 0x3F
    A = (i >> 6) & 0xFF
    C = (i >> 14) & 0x1FF
    B = (i >> 23) & 0x1FF
    Bx = (i >> 14) & 0x3FFFF
    Ax = (i >> 6) & 0x3FFFFFF
    sBx = Bx - 131071
    return op, A, B, C, Bx, Ax, sBx


def parse_chunk_bytes(data: bytes):
    p = Parser(data)
    if p.take(4) != b"\x1bLua":
        raise ValueError("missing Lua signature")
    ver, fmt = p.u8(), p.u8()
    if ver != 0x53:
        raise ValueError(f"unsupported Lua version {ver:#x}")
    if p.take(6) != b"\x19\x93\r\n\x1a\n":
        raise ValueError("LUAC_DATA mismatch")
    p.intsz, p.sizetsz, p.inssz, p.isz, p.nsz = [p.u8() for _ in range(5)]
    raw_int = p.take(p.isz)
    if int.from_bytes(raw_int, "little") == 0x5678:
        p.endian = "<"
    elif int.from_bytes(raw_int, "big") == 0x5678:
        p.endian = ">"
    else:
        raise ValueError("LUAC_INT mismatch")
    num = struct.unpack(p.endian + "d", p.take(p.nsz))[0]
    if abs(num - 370.5) > 1e-12:
        raise ValueError("LUAC_NUM mismatch")
    root_up = p.u8()
    header_end = p.p

    def fn(depth=0):
        source = p.string()
        linedefined = p.sint(p.intsz)
        lastlinedefined = p.sint(p.intsz)
        numparams = p.u8(); isvararg = p.u8(); maxstack = p.u8()
        code = [p.uint(p.inssz) for _ in range(p.count())]
        K = []
        for _ in range(p.count()):
            t = p.u8()
            if t == 0: v = None
            elif t == 1: v = bool(p.u8())
            elif t == 3: v = struct.unpack(p.endian + "d", p.take(p.nsz))[0]
            elif t == 19: v = p.sint(p.isz)
            elif t in (4, 20): v = p.string()
            else: raise ValueError(f"unknown constant tag {t} @0x{p.p-1:x}")
            K.append(v)
        up = [(p.u8(), p.u8()) for _ in range(p.count())]
        protos = [fn(depth + 1) for _ in range(p.count())]
        lines = [p.sint(p.intsz) for _ in range(p.count())]
        loc = [(p.string(), p.sint(p.intsz), p.sint(p.intsz)) for _ in range(p.count())]
        upnames = [p.string() for _ in range(p.count())]
        return {"source": source, "linedefined": linedefined, "lastlinedefined": lastlinedefined,
                "numparams": numparams, "isvararg": isvararg, "maxstack": maxstack,
                "code": code, "K": K, "up": up, "protos": protos, "lines": lines,
                "loc": loc, "upnames": upnames}

    root = fn()
    meta = {
        "sha256": sha256_bytes(data), "bytes": len(data), "version_byte": ver, "format": fmt,
        "sizeof_int": p.intsz, "sizeof_size_t": p.sizetsz, "sizeof_instruction": p.inssz,
        "sizeof_lua_integer": p.isz, "sizeof_lua_number": p.nsz,
        "endianness": "little" if p.endian == "<" else "big", "luac_num": num,
        "root_upvalues": root_up, "header_bytes": header_end, "parsed_bytes": p.p,
        "trailing_bytes": len(data) - p.p,
    }
    return meta, root


def truth(v):
    return not (v is None or v is False)


def execute_into(root, env: Optional[LuaTable] = None):
    K, code = root["K"], root["code"]
    R = [None] * max(64, root["maxstack"] + 16)
    env = env or LuaTable()
    U = [env]
    pc = steps = 0
    hist = {}

    def rk(x):
        return K[x & 0xFF] if x & 0x100 else R[x]

    while pc < len(code):
        if steps > len(code) * MAX_STATIC_STEPS_FACTOR:
            raise RuntimeError("execution runaway")
        steps += 1
        op, A, B, C, Bx, Ax, sBx = fields(code[pc])
        if op >= len(OPNAMES):
            raise RuntimeError(f"opcode out of range {op} @pc={pc}")
        name = OPNAMES[op]
        hist[name] = hist.get(name, 0) + 1
        npc = pc + 1
        if name == "MOVE": R[A] = R[B]
        elif name == "LOADK": R[A] = K[Bx]
        elif name == "LOADKX":
            e = fields(code[npc])
            if e[0] != 46: raise RuntimeError(f"LOADKX without EXTRAARG @pc={pc}")
            R[A] = K[e[5]]; npc += 1
        elif name == "LOADBOOL": R[A] = bool(B); npc += 1 if C else 0
        elif name == "LOADNIL":
            for x in range(A, A + B + 1): R[x] = None
        elif name == "GETUPVAL": R[A] = U[B]
        elif name == "GETTABUP":
            base, key = U[B], rk(C)
            if not isinstance(base, LuaTable): raise RuntimeError(f"GETTABUP non-table @pc={pc}")
            R[A] = base.get(key)
        elif name == "GETTABLE":
            base, key = R[B], rk(C)
            if not isinstance(base, LuaTable): raise RuntimeError(f"GETTABLE non-table @pc={pc}")
            R[A] = base.get(key)
        elif name == "SETTABUP":
            base, key, val = U[A], rk(B), rk(C)
            if not isinstance(base, LuaTable): raise RuntimeError(f"SETTABUP non-table @pc={pc}")
            base.set(key, val)
        elif name == "SETUPVAL": U[B] = R[A]
        elif name == "SETTABLE":
            base, key, val = R[A], rk(B), rk(C)
            if not isinstance(base, LuaTable): raise RuntimeError(f"SETTABLE non-table @pc={pc}")
            base.set(key, val)
        elif name == "NEWTABLE": R[A] = LuaTable()
        elif name == "JMP": npc = pc + 1 + sBx
        elif name == "TEST":
            if truth(R[A]) != bool(C): npc += 1
        elif name == "SETLIST":
            base = R[A]
            if not isinstance(base, LuaTable): raise RuntimeError(f"SETLIST non-table @pc={pc}")
            n, c = B, C
            if c == 0:
                e = fields(code[npc])
                if e[0] != 46: raise RuntimeError(f"SETLIST C=0 without EXTRAARG @pc={pc}")
                c = e[5]; npc += 1
            if n == 0: raise RuntimeError(f"SETLIST B=0 unsupported @pc={pc}")
            start = (c - 1) * LFIELDS_PER_FLUSH
            for j in range(1, n + 1): base.set(start + j, R[A + j])
        elif name == "RETURN": break
        elif name == "EXTRAARG": pass
        else:
            raise RuntimeError(f"non-static opcode {name} @pc={pc}")
        pc = npc
    return env, {"steps": steps, "opcode_histogram_executed": hist}


def as_array(t):
    if not isinstance(t, LuaTable): return None
    keys = list(t.d)
    if not keys: return []
    if not all(isinstance(k, int) and k >= 1 for k in keys): return None
    m = max(keys)
    if set(keys) != set(range(1, m + 1)): return None
    return [t.d[i] for i in range(1, m + 1)]


def to_json_value(v):
    if isinstance(v, LuaTable):
        a = as_array(v)
        if a is not None: return [to_json_value(x) for x in a]
        return {str(k): to_json_value(v.d[k]) for k in v.order if k in v.d}
    return v


def norm_field(name):
    return name[2:] if isinstance(name, str) and len(name) > 2 and name[:2] in ("s_", "u_") else name


def reconstruct_table(global_name: str, main: LuaTable):
    header = as_array(main.get(-1))
    if header is None or not all(isinstance(x, str) for x in header):
        raise RuntimeError("missing/invalid -1 header row")
    rows = []
    for key in main.order:
        if key == -1 or key not in main.d:
            continue
        arr = as_array(main.get(key))
        if arr is None:
            raise RuntimeError(f"main row {key!r} is not an array")
        if len(arr) != len(header):
            raise RuntimeError(f"row {key!r} width={len(arr)} header={len(header)}")
        rec = {"id": key}
        for h, v in zip(header, arr):
            rec[norm_field(h)] = to_json_value(v)
        rows.append(rec)
    return header, rows


@dataclass
class LuaEntry:
    asset_name: str
    bundle_path: str
    raw_sha256: str
    kind: str
    decoded_path: str
    decoded_sha256: str
    bytes: int
    fragment_index: int = 0
    group: str = ""


def group_fragment_name(asset_name: str) -> tuple[str, int]:
    leaf = Path(asset_name.replace("\\", "/")).name
    base = re.sub(r"\.(lua|luac|bytes|txt|bin)$", "", leaf, flags=re.I)
    m = re.match(r"^(.*?)(?:[_-](\d+))$", base)
    if m and m.group(1).upper().startswith("TAB_"):
        return m.group(1), int(m.group(2))
    return base, 0


def candidate_file(path: Path, deep: bool = True) -> tuple[bool, str]:
    try:
        if not path.is_file() or path.stat().st_size < 8:
            return False, "small"
        with path.open("rb") as f:
            head = f.read(16)
        if any(head.startswith(m) for m in UNITY_MAGIC):
            return True, "magic"
        if path.suffix.lower() in BUNDLE_EXTS or path.name.endswith("__data"):
            return True, "name"
        if deep:
            parts = {p.lower() for p in path.parts[-5:]}
            if any(any(h in part for h in PATH_HINTS) for part in parts):
                return True, "deep-path"
    except Exception:
        pass
    return False, "skip"


def textasset_bytes(data_obj) -> bytes:
    script = getattr(data_obj, "m_Script", None)
    if script is None:
        script = getattr(data_obj, "script", None)
    if isinstance(script, str):
        return script.encode("utf-8", "surrogateescape")
    if isinstance(script, (bytes, bytearray, memoryview)):
        return bytes(script)
    raise TypeError("TextAsset has no supported m_Script/script payload")


def textasset_name(data_obj, fallback: str) -> str:
    name = getattr(data_obj, "m_Name", None)
    if name is None:
        name = getattr(data_obj, "name", None)
    return str(name or fallback or "unnamed")


def parse_textasset_object(obj):
    if hasattr(obj, "parse_as_object"):
        return obj.parse_as_object()
    if hasattr(obj, "read"):
        return obj.read()
    raise TypeError("unsupported UnityPy ObjectReader API")


def append_jsonl(path: Path, obj: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def emit(callback: Optional[Callable[[dict], None]], **event):
    if callback:
        callback(event)


def recover_groups(lua_entries: list[LuaEntry], out_root: Path, callback=None) -> dict:
    recovered_dir = out_root / "recovered_json"
    recovered_dir.mkdir(parents=True, exist_ok=True)
    grouped: dict[str, list[LuaEntry]] = {}
    for e in lua_entries:
        group, idx = group_fragment_name(e.asset_name)
        e.group, e.fragment_index = group, idx
        grouped.setdefault(group, []).append(e)

    summary = {"groups_total": len(grouped), "groups_recovered": 0, "groups_dynamic_or_failed": 0,
               "tables_recovered": 0, "records_recovered": 0}
    report = []
    for gi, (group, entries) in enumerate(sorted(grouped.items()), 1):
        entries.sort(key=lambda x: (x.fragment_index, x.asset_name.lower(), x.decoded_sha256))
        env = LuaTable()
        fragments_report = []
        failed = None
        for e in entries:
            if not e.decoded_path.lower().endswith(".luac"):
                failed = "plain Lua source is not statically bytecode-interpreted"
                fragments_report.append({"asset": e.asset_name, "status": "source-only"})
                continue
            try:
                data = Path(e.decoded_path).read_bytes()
                meta, root = parse_chunk_bytes(data)
                env, execution = execute_into(root, env)
                fragments_report.append({"asset": e.asset_name, "status": "ok", "chunk": meta, "execution": execution})
            except Exception as exc:
                failed = str(exc)
                fragments_report.append({"asset": e.asset_name, "status": "dynamic-or-failed", "error": str(exc)})
                break

        globals_ = [k for k in env.order if isinstance(k, str) and k.startswith("TAB_") and isinstance(env.get(k), LuaTable)]
        tables = []
        if not failed and globals_:
            for global_name in globals_:
                try:
                    header, rows = reconstruct_table(global_name, env.get(global_name))
                    stem = global_name.removeprefix("TAB_")
                    out_path = recovered_dir / f"{safe_name(stem)}.json"
                    out_path.write_text(json.dumps({"ListConfigModel": rows}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                    tables.append({"global": global_name, "records": len(rows), "header": [norm_field(x) for x in header], "file": str(out_path)})
                    summary["tables_recovered"] += 1
                    summary["records_recovered"] += len(rows)
                except Exception as exc:
                    failed = str(exc)
                    break

        if tables and not failed:
            summary["groups_recovered"] += 1
            status = "recovered"
        else:
            summary["groups_dynamic_or_failed"] += 1
            status = "dynamic-or-failed"
        item = {"group": group, "status": status, "error": failed, "fragments": fragments_report, "tables": tables}
        report.append(item)
        emit(callback, stage="recover", current=gi, total=len(grouped), group=group, status=status)

    (out_root / "recovery_report.json").write_text(json.dumps({"summary": summary, "groups": report}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary


def scan_game_root(input_root: str | Path, output_root: str | Path, callback=None, deep: bool = True) -> dict:
    if UnityPy is None:
        raise RuntimeError("UnityPy is not installed. Install with: pip install UnityPy")
    input_root = Path(input_root).expanduser().resolve()
    out_root = Path(output_root).expanduser().resolve()
    out_root.mkdir(parents=True, exist_ok=True)
    raw_dir = out_root / "raw_textasset"; raw_dir.mkdir(exist_ok=True)
    decoded_dir = out_root / "decoded_lua"; decoded_dir.mkdir(exist_ok=True)
    direct_json_dir = out_root / "direct_json"; direct_json_dir.mkdir(exist_ok=True)

    all_files = [p for p in input_root.rglob("*") if p.is_file() and out_root not in p.parents]
    candidates = []
    for p in all_files:
        ok, reason = candidate_file(p, deep=deep)
        if ok:
            candidates.append((p, reason))
    emit(callback, stage="inventory", files=len(all_files), candidates=len(candidates))

    stats = {
        "version": APP_VERSION, "input_root": str(input_root), "output_root": str(out_root),
        "files_seen": len(all_files), "bundle_candidates": len(candidates), "bundles_opened": 0,
        "bundle_failures": 0, "textassets": 0, "unique_textassets": 0, "direct_json": 0,
        "lua_candidates": 0, "encm_decoded": 0, "lua53_bytecode": 0, "lua_source": 0,
        "unknown_textassets": 0,
    }
    seen_text_hashes = set()
    lua_entries: list[LuaEntry] = []
    errors_path = out_root / "bundle_errors.jsonl"
    manifest_path = out_root / "textassets.jsonl"
    for idx, (bundle_path, reason) in enumerate(candidates, 1):
        emit(callback, stage="bundle", current=idx, total=len(candidates), path=str(bundle_path), reason=reason)
        try:
            env = UnityPy.load(str(bundle_path))
            stats["bundles_opened"] += 1
            objects = list(getattr(env, "objects", []))
            for oi, obj in enumerate(objects):
                try:
                    if getattr(getattr(obj, "type", None), "name", "") != "TextAsset":
                        continue
                    data_obj = parse_textasset_object(obj)
                    raw = textasset_bytes(data_obj)
                    name = textasset_name(data_obj, f"TextAsset_{oi}")
                    stats["textassets"] += 1
                    raw_sha = sha256_bytes(raw)
                    unique = raw_sha not in seen_text_hashes
                    if unique:
                        seen_text_hashes.add(raw_sha)
                        stats["unique_textassets"] += 1
                    raw_file = raw_dir / f"{raw_sha[:16]}_{safe_name(name)}.bin"
                    if unique and not raw_file.exists():
                        raw_file.write_bytes(raw)

                    direct_json = None
                    if looks_json(raw):
                        stats["direct_json"] += 1
                        direct_json = direct_json_dir / f"{safe_name(name)}_{raw_sha[:12]}.json"
                        if not direct_json.exists(): direct_json.write_bytes(raw)

                    decoded, kind = decode_lua_candidate(raw, name)
                    decoded_file = None
                    if decoded is not None:
                        stats["lua_candidates"] += 1
                        if kind == "encm-xor4d": stats["encm_decoded"] += 1
                        ext = ".luac" if has_lua53_signature(decoded) else ".lua"
                        if ext == ".luac": stats["lua53_bytecode"] += 1
                        else: stats["lua_source"] += 1
                        dec_sha = sha256_bytes(decoded)
                        decoded_file = decoded_dir / f"{safe_name(name)}_{dec_sha[:12]}{ext}"
                        if not decoded_file.exists(): decoded_file.write_bytes(decoded)
                        lua_entries.append(LuaEntry(name, str(bundle_path), raw_sha, kind, str(decoded_file), dec_sha, len(decoded)))
                    elif direct_json is None:
                        stats["unknown_textassets"] += 1

                    append_jsonl(manifest_path, {
                        "bundle": str(bundle_path), "asset": name, "bytes": len(raw), "sha256": raw_sha,
                        "unique": unique, "decode": kind, "raw_file": str(raw_file),
                        "decoded_file": str(decoded_file) if decoded_file else "",
                        "json_file": str(direct_json) if direct_json else "",
                    })
                except Exception as exc:
                    append_jsonl(errors_path, {"bundle": str(bundle_path), "object_index": oi, "stage": "textasset", "error": str(exc)})
        except Exception as exc:
            stats["bundle_failures"] += 1
            append_jsonl(errors_path, {"bundle": str(bundle_path), "stage": "bundle-open", "error": str(exc)})

    recovery = recover_groups(lua_entries, out_root, callback=callback)
    stats.update(recovery)
    (out_root / "summary.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    emit(callback, stage="done", stats=stats)
    return stats


def self_test() -> None:
    raw = bytes.fromhex("454e434d5601382c1e4c54de40475747")
    decoded, kind = decode_lua_candidate(raw, "TAB_Test_1.lua")
    assert kind == "encm-xor4d"
    assert decoded == bytes.fromhex("1b4c7561530119930d0a1a0a")
    assert group_fragment_name("src/data/TAB_Drop_12.lua") == ("TAB_Drop", 12)
    assert group_fragment_name("TAB_Recharge.lua") == ("TAB_Recharge", 0)
    print("self-test passed")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Unity Bundle Lua/JSON Recovery")
    ap.add_argument("input", nargs="?")
    ap.add_argument("-o", "--output")
    ap.add_argument("--shallow", action="store_true", help="only scan obvious UnityFS/bundle candidates")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        self_test(); return 0
    if not args.input or not args.output:
        ap.error("input and --output are required unless --self-test is used")
    def cb(e):
        stage = e.get("stage")
        if stage == "bundle": print(f"[{e['current']}/{e['total']}] {e['path']}")
        elif stage == "recover": print(f"[recover {e['current']}/{e['total']}] {e['group']} {e['status']}")
    stats = scan_game_root(args.input, args.output, callback=cb, deep=not args.shallow)
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
