#!/usr/bin/env python3
"""Shared helpers for Unity Bundle Lua Recovery v0.3.0."""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import unity_bundle_lua_recovery as core

APP_VERSION = "0.3.0"
MAX_VARIANTS_PER_FRAGMENT = 8
BEAM_WIDTH = 8


@dataclass
class CombinedEntry:
    asset_name: str
    decoded_path: str
    decoded_sha256: str
    bytes: int
    source_kind: str
    source_path: str
    kind: str
    provenance: list[dict] = field(default_factory=list)
    group: str = ""
    fragment_index: int = 0


@dataclass
class BeamState:
    env: core.LuaTable
    returns: list
    fragments: list[dict]
    score: int = 0
    partial_reason: Optional[str] = None


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def clone_value(v, memo=None):
    if memo is None:
        memo = {}
    if not isinstance(v, core.LuaTable):
        return v
    if id(v) in memo:
        return memo[id(v)]
    out = core.LuaTable()
    memo[id(v)] = out
    for k in v.order:
        if k in v.d:
            out.set(clone_value(k, memo), clone_value(v.d[k], memo))
    return out


def table_size(v, seen=None) -> int:
    if seen is None:
        seen = set()
    if not isinstance(v, core.LuaTable):
        return 1
    if id(v) in seen:
        return 0
    seen.add(id(v))
    total = len(v.d)
    for value in v.d.values():
        if isinstance(value, core.LuaTable):
            total += table_size(value, seen)
    return total


def canonical_asset_name(path: Path) -> str:
    name = path.name
    name = re.sub(r"\.(luac|lua|bytes|bin|txt)$", "", name, flags=re.I)
    name = re.sub(r"_[0-9a-fA-F]{12,64}$", "", name)
    if name.lower().endswith(".lua"):
        return name
    m = re.search(r"(@?[^\\/]*?\.lua)$", name, flags=re.I)
    if m:
        return m.group(1)
    return name + (".lua" if path.suffix.lower() == ".luac" else "")


def group_fragment_name_v3(asset_name: str) -> tuple[str, int]:
    text = asset_name.replace("\\", "/")
    tab = re.search(
        r"(TAB_[A-Za-z0-9][A-Za-z0-9_-]*?)(?:[_-](\d{1,4}))?(?:\.lua(?:c)?)?$",
        text,
        flags=re.I,
    )
    if tab:
        return tab.group(1), int(tab.group(2) or 0)
    leaf = Path(text).name
    base = re.sub(r"\.(lua|luac|bytes|txt|bin)$", "", leaf, flags=re.I)
    m = re.match(r"^(.*?)[_-](\d{1,3})$", base)
    if m and any(token in m.group(1).lower() for token in ("data", "config", "table", "list")):
        return m.group(1), int(m.group(2))
    return base, 0


def execute_into_v3(root, env: Optional[core.LuaTable] = None):
    K, code = root["K"], root["code"]
    R = [None] * max(64, root["maxstack"] + 32)
    env = env or core.LuaTable()
    U = [env]
    pc = steps = 0
    hist = {}
    returns = []

    def rk(x):
        return K[x & 0xFF] if x & 0x100 else R[x]

    while pc < len(code):
        if steps > len(code) * core.MAX_STATIC_STEPS_FACTOR:
            raise RuntimeError("execution runaway")
        steps += 1
        op, A, B, C, Bx, Ax, sBx = core.fields(code[pc])
        if op >= len(core.OPNAMES):
            raise RuntimeError(f"opcode out of range {op} @pc={pc}")
        name = core.OPNAMES[op]
        hist[name] = hist.get(name, 0) + 1
        npc = pc + 1
        if name == "MOVE":
            R[A] = R[B]
        elif name == "LOADK":
            R[A] = K[Bx]
        elif name == "LOADKX":
            if npc >= len(code):
                raise RuntimeError(f"LOADKX missing EXTRAARG @pc={pc}")
            e = core.fields(code[npc])
            if e[0] != 46:
                raise RuntimeError(f"LOADKX without EXTRAARG @pc={pc}")
            R[A] = K[e[5]]
            npc += 1
        elif name == "LOADBOOL":
            R[A] = bool(B)
            npc += 1 if C else 0
        elif name == "LOADNIL":
            for x in range(A, A + B + 1):
                R[x] = None
        elif name == "GETUPVAL":
            R[A] = U[B]
        elif name == "GETTABUP":
            base, key = U[B], rk(C)
            if not isinstance(base, core.LuaTable):
                raise RuntimeError(f"GETTABUP non-table @pc={pc}")
            R[A] = base.get(key)
        elif name == "GETTABLE":
            base, key = R[B], rk(C)
            if not isinstance(base, core.LuaTable):
                raise RuntimeError(f"GETTABLE non-table @pc={pc}")
            R[A] = base.get(key)
        elif name == "SETTABUP":
            base, key, val = U[A], rk(B), rk(C)
            if not isinstance(base, core.LuaTable):
                raise RuntimeError(f"SETTABUP non-table @pc={pc}")
            base.set(key, val)
        elif name == "SETUPVAL":
            U[B] = R[A]
        elif name == "SETTABLE":
            base, key, val = R[A], rk(B), rk(C)
            if not isinstance(base, core.LuaTable):
                raise RuntimeError(f"SETTABLE non-table @pc={pc}")
            base.set(key, val)
        elif name == "NEWTABLE":
            R[A] = core.LuaTable()
        elif name == "JMP":
            npc = pc + 1 + sBx
        elif name == "TEST":
            if core.truth(R[A]) != bool(C):
                npc += 1
        elif name == "SETLIST":
            base = R[A]
            if not isinstance(base, core.LuaTable):
                raise RuntimeError(f"SETLIST non-table @pc={pc}")
            n, c = B, C
            if c == 0:
                if npc >= len(code):
                    raise RuntimeError(f"SETLIST C=0 missing EXTRAARG @pc={pc}")
                e = core.fields(code[npc])
                if e[0] != 46:
                    raise RuntimeError(f"SETLIST C=0 without EXTRAARG @pc={pc}")
                c = e[5]
                npc += 1
            if n == 0:
                raise RuntimeError(f"SETLIST B=0 unsupported @pc={pc}")
            start = (c - 1) * core.LFIELDS_PER_FLUSH
            for j in range(1, n + 1):
                base.set(start + j, R[A + j])
        elif name == "RETURN":
            if B == 0:
                raise RuntimeError(f"RETURN B=0 unsupported @pc={pc}")
            if B > 1:
                returns = [R[x] for x in range(A, A + B - 1)]
            break
        elif name == "EXTRAARG":
            pass
        else:
            raise RuntimeError(f"non-static opcode {name} @pc={pc}")
        pc = npc
    return env, returns, {"steps": steps, "opcode_histogram_executed": hist}


def reconstruct_table_tolerant(main: core.LuaTable):
    header = core.as_array(main.get(-1))
    if header is None or not all(isinstance(x, str) for x in header):
        raise RuntimeError("missing/invalid -1 header row")
    header_norm = [core.norm_field(x) for x in header]
    rows, malformed = [], []
    for key in main.order:
        if key == -1 or key not in main.d:
            continue
        arr = core.as_array(main.get(key))
        if arr is None:
            malformed.append({"id": key, "reason": "row-not-array", "value": core.to_json_value(main.get(key))})
            continue
        rec = {"id": key}
        width = min(len(arr), len(header_norm))
        for i in range(width):
            rec[header_norm[i]] = core.to_json_value(arr[i])
        if len(arr) < len(header_norm):
            for h in header_norm[len(arr):]:
                rec[h] = None
            malformed.append({"id": key, "reason": "short-row", "row_width": len(arr), "header_width": len(header_norm)})
        elif len(arr) > len(header_norm):
            rec["_extra"] = [core.to_json_value(x) for x in arr[len(header_norm):]]
            malformed.append({"id": key, "reason": "wide-row", "row_width": len(arr), "header_width": len(header_norm)})
        rows.append(rec)
    return header_norm, rows, malformed


def serialize_candidate(label: str, table: core.LuaTable):
    try:
        header, rows, malformed = reconstruct_table_tolerant(table)
        return {"ListConfigModel": rows}, "config-table", len(rows), malformed
    except Exception:
        payload = core.to_json_value(table)
        count = len(payload) if isinstance(payload, (dict, list)) else 1
        return payload, "generic-table", count, []


def extract_tables(env: core.LuaTable, returns: list, group: str):
    found, seen = [], set()
    for key in env.order:
        value = env.get(key)
        if not isinstance(key, str) or not isinstance(value, core.LuaTable) or not value.d:
            continue
        if id(value) in seen:
            continue
        seen.add(id(value))
        found.append((key, value, "global"))
    for idx, value in enumerate(returns):
        if isinstance(value, core.LuaTable) and value.d and id(value) not in seen:
            seen.add(id(value))
            found.append((f"RETURN_{group}_{idx + 1}", value, "return"))
    return found


def result_score(env: core.LuaTable, returns: list) -> int:
    score = 0
    for key, table, origin in extract_tables(env, returns, ""):
        _, mode, count, malformed = serialize_candidate(key, table)
        score += count * (100 if mode == "config-table" else 5)
        score += table_size(table)
        score -= len(malformed) * 2
        if key.upper().startswith("TAB_"):
            score += 100000
    return score


def self_test_common():
    assert group_fragment_name_v3("TAB_Drop_12.lua") == ("TAB_Drop", 12)
    assert group_fragment_name_v3("MiniGameItemData_1.lua") == ("MiniGameItemData", 1)
    assert group_fragment_name_v3("report_10870.lua") == ("report_10870", 0)
    t = core.LuaTable()
    h = core.LuaTable(); h.set(1, "Name"); h.set(2, "Value")
    r = core.LuaTable(); r.set(1, "A"); r.set(2, 7); r.set(3, "EXTRA")
    t.set(-1, h); t.set(1, r)
    header, rows, malformed = reconstruct_table_tolerant(t)
    assert header == ["Name", "Value"]
    assert rows[0]["_extra"] == ["EXTRA"]
    assert malformed[0]["reason"] == "wide-row"
