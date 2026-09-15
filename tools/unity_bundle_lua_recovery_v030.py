#!/usr/bin/env python3
"""Unity Bundle Lua Recovery v0.3.0 Combined Recovery."""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path
from typing import Callable, Optional

import UnityPy
import UnityPy.config

import unity_bundle_lua_recovery as core
from ublr_v030_common import (
    APP_VERSION, CombinedEntry, canonical_asset_name, self_test_common, sha256_bytes,
)
from ublr_v030_recovery import recover_combined

TARGET_UNITY_VERSION = "2019.4.33f1"
UnityPy.config.FALLBACK_UNITY_VERSION = TARGET_UNITY_VERSION
core.APP_VERSION = APP_VERSION

_original_append_jsonl = core.append_jsonl


def _fallback_log_path(path: Path) -> Path:
    root = Path(tempfile.gettempdir()) / "UnityBundleLuaRecovery" / "logs"
    root.mkdir(parents=True, exist_ok=True)
    return root / f"{core.safe_name(str(path.parent), 80)}_{path.name}.jsonl"


def safe_append_jsonl(path: Path, obj: dict):
    path = Path(path)
    try:
        if path.exists() and path.is_dir():
            path = path.with_name(path.name + ".log")
        _original_append_jsonl(path, obj)
        return
    except (PermissionError, IsADirectoryError, OSError):
        pass
    try:
        fallback = _fallback_log_path(path)
        with fallback.open("a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")
    except Exception:
        return


core.append_jsonl = safe_append_jsonl


def emit(callback: Optional[Callable[[dict], None]], **event):
    if callback:
        callback(event)


def register_entry(registry: dict[str, CombinedEntry], provenance_map: dict[str, list[dict]],
                   asset_name: str, data: bytes, source_kind: str, source_path: str,
                   kind: str, combined_dir: Path):
    if not core.has_lua53_signature(data):
        return False
    sha = sha256_bytes(data)
    prov = {"source_kind": source_kind, "source_path": source_path, "asset": asset_name}
    provenance_map.setdefault(sha, []).append(prov)
    existing = registry.get(sha)
    if existing:
        if "TAB_" not in existing.asset_name.upper() and "TAB_" in asset_name.upper():
            existing.asset_name = asset_name
        existing.provenance.append(prov)
        return False

    filename = f"{sha[:16]}_{core.safe_name(asset_name, 120)}.luac"
    path = combined_dir / filename
    if not path.exists():
        path.write_bytes(data)
    registry[sha] = CombinedEntry(
        asset_name=asset_name, decoded_path=str(path), decoded_sha256=sha,
        bytes=len(data), source_kind=source_kind, source_path=source_path,
        kind=kind, provenance=[prov],
    )
    return True


def scan_bundle_sources(input_root: Path, out_root: Path, registry, provenance_map,
                        callback=None, deep=True):
    raw_dir = out_root / "raw_textasset"
    direct_json_dir = out_root / "direct_json"
    combined_dir = out_root / "combined_lua"
    for d in (raw_dir, direct_json_dir, combined_dir):
        d.mkdir(parents=True, exist_ok=True)

    all_files = [p for p in input_root.rglob("*") if p.is_file() and out_root not in p.parents]
    candidates = []
    for p in all_files:
        ok, reason = core.candidate_file(p, deep=deep)
        if ok:
            candidates.append((p, reason))
    emit(callback, stage="inventory", files=len(all_files), candidates=len(candidates))

    stats = {
        "files_seen": len(all_files), "bundle_candidates": len(candidates),
        "bundles_opened": 0, "bundle_failures": 0, "textassets": 0,
        "unique_textassets": 0, "direct_json": 0, "bundle_lua_candidates": 0,
    }
    seen_text = set()
    errors_path = out_root / "bundle_errors.jsonl"
    manifest_path = out_root / "textassets.jsonl"

    for idx, (bundle_path, reason) in enumerate(candidates, 1):
        emit(callback, stage="bundle", current=idx, total=len(candidates),
             path=str(bundle_path), reason=reason)
        try:
            env = UnityPy.load(str(bundle_path))
            stats["bundles_opened"] += 1
            for oi, obj in enumerate(list(getattr(env, "objects", []))):
                try:
                    if getattr(getattr(obj, "type", None), "name", "") != "TextAsset":
                        continue
                    data_obj = core.parse_textasset_object(obj)
                    raw = core.textasset_bytes(data_obj)
                    name = core.textasset_name(data_obj, f"TextAsset_{oi}")
                    stats["textassets"] += 1
                    raw_sha = sha256_bytes(raw)
                    unique = raw_sha not in seen_text
                    if unique:
                        seen_text.add(raw_sha)
                        stats["unique_textassets"] += 1
                        raw_file = raw_dir / f"{raw_sha[:16]}_{core.safe_name(name)}.bin"
                        if not raw_file.exists():
                            raw_file.write_bytes(raw)

                    direct_file = ""
                    if core.looks_json(raw):
                        stats["direct_json"] += 1
                        p = direct_json_dir / f"{core.safe_name(name)}_{raw_sha[:12]}.json"
                        if not p.exists():
                            p.write_bytes(raw)
                        direct_file = str(p)

                    decoded, kind = core.decode_lua_candidate(raw, name)
                    added = False
                    if decoded is not None and core.has_lua53_signature(decoded):
                        stats["bundle_lua_candidates"] += 1
                        added = register_entry(
                            registry, provenance_map, name, decoded, "bundle",
                            str(bundle_path), kind, combined_dir,
                        )
                    core.append_jsonl(manifest_path, {
                        "bundle": str(bundle_path), "asset": name, "bytes": len(raw),
                        "sha256": raw_sha, "unique": unique, "decode": kind,
                        "registered_new_lua": added, "json_file": direct_file,
                    })
                except Exception as exc:
                    core.append_jsonl(errors_path, {
                        "bundle": str(bundle_path), "object_index": oi,
                        "stage": "textasset", "error": str(exc),
                    })
        except Exception as exc:
            stats["bundle_failures"] += 1
            core.append_jsonl(errors_path, {
                "bundle": str(bundle_path), "stage": "bundle-open", "error": str(exc),
            })
    return stats


def collect_phone_sources(capture_root: Optional[Path], out_root: Path,
                          registry, provenance_map, callback=None):
    stats = {
        "phone_files_seen": 0, "phone_lua_candidates": 0,
        "phone_unique_added": 0, "phone_decoded_files": 0,
        "phone_loader_files": 0, "phone_raw_files": 0,
    }
    if not capture_root or not capture_root.is_dir():
        return stats

    combined_dir = out_root / "combined_lua"
    combined_dir.mkdir(parents=True, exist_ok=True)
    files = [p for p in capture_root.rglob("*") if p.is_file()]
    interesting = []
    for p in files:
        lower_parts = [x.lower() for x in p.parts]
        if any(x in ("decoded_lua", "lua_loader", "raw_textasset") for x in lower_parts):
            interesting.append(p)
    emit(callback, stage="phone_inventory", files=len(files), interesting=len(interesting))

    for idx, p in enumerate(interesting, 1):
        stats["phone_files_seen"] += 1
        lower_parts = [x.lower() for x in p.parts]
        if "decoded_lua" in lower_parts:
            source_kind = "phone-decoded"
            stats["phone_decoded_files"] += 1
        elif "lua_loader" in lower_parts:
            source_kind = "phone-loader"
            stats["phone_loader_files"] += 1
        else:
            source_kind = "phone-raw"
            stats["phone_raw_files"] += 1

        try:
            raw = p.read_bytes()
            asset = canonical_asset_name(p)
            decoded, kind = core.decode_lua_candidate(raw, asset)
            if decoded is None and core.has_lua53_signature(raw):
                decoded, kind = raw, "plain-luac53"
            if decoded is None or not core.has_lua53_signature(decoded):
                continue
            stats["phone_lua_candidates"] += 1
            if register_entry(
                registry, provenance_map, asset, decoded, source_kind,
                str(p), kind, combined_dir,
            ):
                stats["phone_unique_added"] += 1
        except Exception:
            continue

        if idx % 100 == 0 or idx == len(interesting):
            emit(callback, stage="phone", current=idx, total=len(interesting))
    return stats


def scan_combined(input_root: str | Path, output_root: str | Path,
                  capture_root: str | Path | None = None, callback=None, deep=True):
    UnityPy.config.FALLBACK_UNITY_VERSION = TARGET_UNITY_VERSION
    input_root = Path(input_root).expanduser().resolve()
    out_root = Path(output_root).expanduser().resolve()
    capture = Path(capture_root).expanduser().resolve() if capture_root else None
    out_root.mkdir(parents=True, exist_ok=True)

    registry: dict[str, CombinedEntry] = {}
    provenance_map: dict[str, list[dict]] = {}
    stats = {
        "version": APP_VERSION, "unity_fallback": TARGET_UNITY_VERSION,
        "input_root": str(input_root), "capture_root": str(capture) if capture else "",
        "output_root": str(out_root),
    }

    stats.update(scan_bundle_sources(
        input_root, out_root, registry, provenance_map, callback=callback, deep=deep,
    ))
    bundle_unique_after = len(registry)
    stats.update(collect_phone_sources(
        capture, out_root, registry, provenance_map, callback=callback,
    ))
    stats["bundle_unique_lua"] = bundle_unique_after
    stats["combined_unique_lua"] = len(registry)
    stats["cross_source_duplicates"] = sum(
        max(0, len(v) - 1) for v in provenance_map.values()
    )

    prov_path = out_root / "combined_sources.jsonl"
    if prov_path.exists() and prov_path.is_file():
        try:
            prov_path.unlink()
        except Exception:
            pass
    for sha, provs in sorted(provenance_map.items()):
        core.append_jsonl(prov_path, {"sha256": sha, "provenance": provs})

    stats.update(recover_combined(list(registry.values()), out_root, callback=callback))
    (out_root / "summary.json").write_text(
        json.dumps(stats, ensure_ascii=False, indent=2) + "\n", encoding="utf-8",
    )
    emit(callback, stage="done", stats=stats)
    return stats


def self_test():
    raw = bytes.fromhex("454e434d5601382c1e4c54de40475747")
    decoded, kind = core.decode_lua_candidate(raw, "TAB_Test_1.lua")
    assert kind == "encm-xor4d"
    assert decoded == bytes.fromhex("1b4c7561530119930d0a1a0a")
    self_test_common()
    print("v0.3.0 combined self-test passed")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Unity Bundle Lua Recovery v0.3 Combined")
    ap.add_argument("input", nargs="?")
    ap.add_argument("-o", "--output")
    ap.add_argument("--capture", help="optional JSONCapture FullSweep directory")
    ap.add_argument("--shallow", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if not args.input or not args.output:
        ap.error("input and --output are required unless --self-test is used")

    def cb(e):
        stage = e.get("stage")
        if stage == "bundle":
            print(f"[bundle {e['current']}/{e['total']}] {e['path']}")
        elif stage == "phone":
            print(f"[phone {e['current']}/{e['total']}]")
        elif stage == "recover":
            print(f"[recover {e['current']}/{e['total']}] {e['group']} {e['status']}")
    stats = scan_combined(
        args.input, args.output, capture_root=args.capture,
        callback=cb, deep=not args.shallow,
    )
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
