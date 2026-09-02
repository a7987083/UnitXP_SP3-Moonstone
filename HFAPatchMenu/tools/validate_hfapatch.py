#!/usr/bin/env python3
"""Dependency-free structural validator for HFAPatch v1 data packages."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


UUID_RE = re.compile(r"^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$")
HEX_RE = re.compile(r"^(?:0[xX])?(?:[0-9a-fA-F]{2})+$")
OFFSET_RE = re.compile(r"^(?:0[xX][0-9a-fA-F]+|[0-9]+)$")


class ValidationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def require_string(value: object, path: str) -> str:
    require(isinstance(value, str) and bool(value), f"{path} must be a non-empty string")
    return value


def byte_length(value: str) -> int:
    clean = value[2:] if value.lower().startswith("0x") else value
    return len(clean) // 2


def validate(document: object) -> None:
    require(isinstance(document, dict), "root must be an object")
    require(document.get("schema") == "com.hfa.patch/v1", "unsupported schema")
    require_string(document.get("name"), "name")

    package = document.get("package")
    require(isinstance(package, dict), "package must be an object")
    for key in ("bundleIdentifier", "shortVersion", "buildVersion"):
        require_string(package.get(key), f"package.{key}")
    architectures = package.get("architectures")
    require(isinstance(architectures, list) and architectures, "package.architectures must be non-empty")
    require(all(item in ("arm64", "arm64e") for item in architectures), "unsupported architecture")
    require(len(architectures) == len(set(architectures)), "duplicate architecture")

    targets = document.get("targets")
    require(isinstance(targets, dict) and targets, "targets must be a non-empty object")
    for target_id, target in targets.items():
        require_string(target_id, "target id")
        require(isinstance(target, dict), f"targets.{target_id} must be an object")
        require_string(target.get("image"), f"targets.{target_id}.image")
        uuid = require_string(target.get("uuid"), f"targets.{target_id}.uuid")
        require(bool(UUID_RE.fullmatch(uuid)), f"targets.{target_id}.uuid is invalid")

    features = document.get("features")
    require(isinstance(features, list) and features, "features must be a non-empty array")
    feature_ids: set[str] = set()
    occupied: dict[str, list[tuple[int, int, str]]] = {}
    for feature_index, feature in enumerate(features):
        path = f"features[{feature_index}]"
        require(isinstance(feature, dict), f"{path} must be an object")
        feature_id = require_string(feature.get("id"), f"{path}.id")
        require(feature_id not in feature_ids, f"duplicate feature id: {feature_id}")
        feature_ids.add(feature_id)
        require_string(feature.get("title"), f"{path}.title")
        require_string(feature.get("group"), f"{path}.group")
        if "defaultEnabled" in feature:
            require(isinstance(feature["defaultEnabled"], bool), f"{path}.defaultEnabled must be boolean")
        patches = feature.get("patches")
        require(isinstance(patches, list) and patches, f"{path}.patches must be non-empty")
        for patch_index, patch in enumerate(patches):
            patch_path = f"{path}.patches[{patch_index}]"
            require(isinstance(patch, dict), f"{patch_path} must be an object")
            target = require_string(patch.get("target"), f"{patch_path}.target")
            require(target in targets, f"{patch_path} references unknown target {target}")
            offset_raw = patch.get("offset")
            require(
                (isinstance(offset_raw, int) and not isinstance(offset_raw, bool) and offset_raw >= 0)
                or (isinstance(offset_raw, str) and bool(OFFSET_RE.fullmatch(offset_raw))),
                f"{patch_path}.offset is invalid",
            )
            offset = offset_raw if isinstance(offset_raw, int) else int(offset_raw, 0)
            original = require_string(patch.get("original"), f"{patch_path}.original")
            enabled = require_string(patch.get("enabled"), f"{patch_path}.enabled")
            require(bool(HEX_RE.fullmatch(original)), f"{patch_path}.original is invalid hex")
            require(bool(HEX_RE.fullmatch(enabled)), f"{patch_path}.enabled is invalid hex")
            size = byte_length(original)
            require(size == byte_length(enabled), f"{patch_path} original/enabled lengths differ")
            candidate = (offset, offset + size, feature_id)
            for start, end, other_feature in occupied.setdefault(target, []):
                require(candidate[1] <= start or candidate[0] >= end,
                        f"{patch_path} overlaps feature {other_feature} at {target}+0x{offset:X}")
            occupied[target].append(candidate)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()
    failed = False
    for path in args.files:
        try:
            validate(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError, ValidationError) as exc:
            failed = True
            print(f"FAIL {path}: {exc}", file=sys.stderr)
        else:
            print(f"OK   {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
