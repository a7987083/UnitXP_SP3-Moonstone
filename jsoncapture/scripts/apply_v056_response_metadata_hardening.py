#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_RESPONSE_METADATA_V056_HARDENED"
if MARKER in s:
    print("v0.5.6 metadata hardening already applied")
    raise SystemExit(0)
if "JCG5_RESPONSE_METADATA_V056" not in s:
    raise SystemExit("v0.5.6 response metadata patch must be applied first")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"hardening anchor missing: {label}")
    s = s.replace(old, new, 1)

rep(
    "static unsigned long long gJCG56NoticeDetected = 0;\n",
    "static unsigned long long gJCG56NoticeDetected = 0;\n"
    "// JCG5_RESPONSE_METADATA_V056_HARDENED\n"
    "static NSDictionary *JCG56ClassifyJSONObject(id obj);\n",
    "classification forward declaration",
)

rep(
    "        record[@\"duplicate\"] = @(duplicate);\n"
    "        record[@\"saved\"] = @(!duplicate);\n"
    "        JCG55AppendJSONLine(gJCG56RequestTracePath, record);\n\n"
    "        if (duplicate) {\n",
    "        record[@\"duplicate\"] = @(duplicate);\n\n"
    "        if (duplicate) {\n"
    "            record[@\"saved\"] = @NO;\n"
    "            JCG55AppendJSONLine(gJCG56RequestTracePath, record);\n",
    "duplicate trace semantics",
)

rep(
    "        BOOL wrote = [snapshot writeToFile:path atomically:YES];\n"
    "        if (wrote) {\n",
    "        BOOL wrote = [snapshot writeToFile:path atomically:YES];\n"
    "        if (wrote) {\n"
    "            record[@\"saved\"] = @YES;\n"
    "            JCG55AppendJSONLine(gJCG56RequestTracePath, record);\n",
    "successful write trace",
)

rep(
    "        } else {\n"
    "            pthread_mutex_lock(&gJCG5StateLock);\n"
    "            gJCG55ResponseInvalid++;\n",
    "        } else {\n"
    "            record[@\"saved\"] = @NO;\n"
    "            JCG55AppendJSONLine(gJCG56RequestTracePath, record);\n"
    "            pthread_mutex_lock(&gJCG5StateLock);\n"
    "            gJCG55ResponseInvalid++;\n",
    "failed write trace",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.6 metadata hardening")
