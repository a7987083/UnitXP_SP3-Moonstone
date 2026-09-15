#!/usr/bin/env python3
"""Combined static recovery engine for v0.3.0."""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

import unity_bundle_lua_recovery as core
from ublr_v030_common import (
    BEAM_WIDTH, MAX_VARIANTS_PER_FRAGMENT, BeamState, CombinedEntry,
    clone_value, execute_into_v3, extract_tables, group_fragment_name_v3,
    result_score, serialize_candidate,
)


def _variant_groups(entries: list[CombinedEntry]):
    by_idx: dict[int, list[CombinedEntry]] = {}
    for e in entries:
        by_idx.setdefault(e.fragment_index, []).append(e)
    for idx, vals in by_idx.items():
        vals.sort(key=lambda e: (-e.bytes, e.decoded_sha256, e.asset_name.lower()))
        by_idx[idx] = vals[:MAX_VARIANTS_PER_FRAGMENT]
    return [(idx, by_idx[idx]) for idx in sorted(by_idx)]


def recover_one_group(group: str, entries: list[CombinedEntry]):
    slots = _variant_groups(entries)
    states = [BeamState(env=core.LuaTable(), returns=[], fragments=[], score=0)]
    fully_processed = True
    stop_reason = None

    for frag_idx, variants in slots:
        next_states, errors = [], []
        for state in states:
            for e in variants:
                env_try = clone_value(state.env)
                try:
                    data = Path(e.decoded_path).read_bytes()
                    meta, root = core.parse_chunk_bytes(data)
                    env_out, returns, execution = execute_into_v3(root, env_try)
                    fr = state.fragments + [{
                        "asset": e.asset_name,
                        "fragment_index": frag_idx,
                        "sha256": e.decoded_sha256,
                        "source_kind": e.source_kind,
                        "source_path": e.source_path,
                        "status": "ok",
                        "chunk": meta,
                        "execution": execution,
                    }]
                    s = BeamState(env=env_out, returns=returns or state.returns, fragments=fr)
                    s.score = result_score(s.env, s.returns)
                    next_states.append(s)
                except Exception as exc:
                    errors.append({
                        "asset": e.asset_name, "fragment_index": frag_idx,
                        "sha256": e.decoded_sha256, "source_kind": e.source_kind,
                        "source_path": e.source_path, "status": "dynamic-or-failed",
                        "error": str(exc),
                    })

        if not next_states:
            fully_processed = False
            stop_reason = errors[0]["error"] if errors else f"no usable variant at fragment {frag_idx}"
            best = max(states, key=lambda s: s.score)
            best.partial_reason = stop_reason
            if errors:
                best.fragments.extend(errors[:MAX_VARIANTS_PER_FRAGMENT])
            states = [best]
            break

        next_states.sort(key=lambda s: s.score, reverse=True)
        uniq, sigs = [], set()
        for s in next_states:
            sig = (s.score, tuple(k for k in s.env.order if isinstance(k, str))[:20])
            if sig in sigs:
                continue
            sigs.add(sig)
            uniq.append(s)
            if len(uniq) >= BEAM_WIDTH:
                break
        states = uniq

    best = max(states, key=lambda s: s.score)
    tables = extract_tables(best.env, best.returns, group)
    return best, tables, fully_processed, stop_reason


def safe_output_name(label: str, group: str, used: set[str]) -> str:
    base = label
    if base.upper().startswith("TAB_"):
        base = base[4:]
    if base.startswith("RETURN_"):
        base = group
    base = core.safe_name(base, 120)
    candidate = base or core.safe_name(group, 120)
    if candidate.lower() in used:
        candidate = f"{candidate}_{hashlib.sha256((label+'|'+group).encode()).hexdigest()[:8]}"
    used.add(candidate.lower())
    return candidate


def recover_combined(entries: list[CombinedEntry], out_root: Path, callback=None):
    complete_dir = out_root / "recovered_complete"
    partial_dir = out_root / "recovered_partial"
    dynamic_dir = out_root / "dynamic_lua"
    invalid_dir = out_root / "unrecoverable"
    for d in (complete_dir, partial_dir, dynamic_dir, invalid_dir):
        d.mkdir(parents=True, exist_ok=True)

    grouped: dict[str, list[CombinedEntry]] = {}
    for e in entries:
        e.group, e.fragment_index = group_fragment_name_v3(e.asset_name)
        grouped.setdefault(e.group, []).append(e)

    stats = {
        "groups_total": len(grouped),
        "groups_complete": 0,
        "groups_partial": 0,
        "groups_dynamic": 0,
        "groups_static_no_table": 0,
        "tables_complete": 0,
        "tables_partial": 0,
        "records_complete": 0,
        "records_partial": 0,
        "generic_tables": 0,
        "returned_tables": 0,
        "malformed_rows": 0,
    }
    report, used_names = [], set()

    for gi, (group, group_entries) in enumerate(sorted(grouped.items()), 1):
        best, tables, fully_processed, stop_reason = recover_one_group(group, group_entries)
        table_report, malformed_any = [], False

        for label, table, origin in tables:
            try:
                payload, mode, count, malformed = serialize_candidate(label, table)
                if not payload:
                    continue
                is_partial = (not fully_processed) or bool(malformed)
                target_dir = partial_dir if is_partial else complete_dir
                stem = safe_output_name(label, group, used_names)
                out_file = target_dir / f"{stem}.json"
                out_file.write_text(
                    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8",
                )
                if mode == "generic-table":
                    stats["generic_tables"] += 1
                if origin == "return":
                    stats["returned_tables"] += 1
                stats["malformed_rows"] += len(malformed)
                if is_partial:
                    stats["tables_partial"] += 1
                    stats["records_partial"] += count
                    malformed_any = malformed_any or bool(malformed)
                else:
                    stats["tables_complete"] += 1
                    stats["records_complete"] += count
                table_report.append({
                    "label": label, "origin": origin, "mode": mode, "records": count,
                    "partial": is_partial, "malformed_rows": malformed,
                    "file": str(out_file),
                })
            except Exception as exc:
                table_report.append({
                    "label": label, "origin": origin,
                    "status": "serialize-failed", "error": str(exc),
                })

        if table_report and any("file" in t for t in table_report):
            if (not fully_processed) or malformed_any:
                status = "partial"
                stats["groups_partial"] += 1
            else:
                status = "complete"
                stats["groups_complete"] += 1
        else:
            errors = [
                f.get("error") for f in best.fragments
                if f.get("status") != "ok" and f.get("error")
            ]
            if errors:
                status = "dynamic"
                stats["groups_dynamic"] += 1
                rep = group_entries[0]
                try:
                    src = Path(rep.decoded_path)
                    shutil.copy2(
                        src,
                        dynamic_dir / f"{core.safe_name(group)}_{rep.decoded_sha256[:12]}{src.suffix}",
                    )
                except Exception:
                    pass
            else:
                status = "static-no-table"
                stats["groups_static_no_table"] += 1

        report.append({
            "group": group, "status": status,
            "fully_processed": fully_processed, "stop_reason": stop_reason,
            "fragments": best.fragments, "tables": table_report,
            "variants_seen": len(group_entries),
        })
        if callback:
            callback({
                "stage": "recover", "current": gi, "total": len(grouped),
                "group": group, "status": status,
            })

    (out_root / "combined_recovery_report.json").write_text(
        json.dumps({"summary": stats, "groups": report}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return stats
