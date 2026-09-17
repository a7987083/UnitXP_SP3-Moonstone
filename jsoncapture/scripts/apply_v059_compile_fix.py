#!/usr/bin/env python3
from pathlib import Path
p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")
if "JCG5_NETWORK_COVERAGE_V059_COMPILE_FIX" in s:
    raise SystemExit(0)
if "JCG5_NETWORK_COVERAGE_V059" not in s:
    raise SystemExit("v0.5.9 coverage patch missing")
old = "static int JCG58RequestWrapper(void *L) {\n"
new = "// JCG5_NETWORK_COVERAGE_V059_COMPILE_FIX\nstatic void JCG59RecordRequest(NSDictionary *meta);\nstatic void JCG59RecordResponse(NSDictionary *meta, NSInteger kind, NSUInteger bytes);\nstatic int JCG58RequestWrapper(void *L) {\n"
if old not in s:
    raise SystemExit("request wrapper anchor missing")
s = s.replace(old, new, 1)
old2 = "        JCG59RecordResponse(covMeta, rejected ? 0 : -1, covBytes);\n"
new2 = "        NSInteger covKind = (rejected && covBytes <= JCG57_BACKEND_JSON_MAX_BYTES) ? 0 : -1;\n        JCG59RecordResponse(covMeta, covKind, covBytes);\n"
if old2 not in s:
    raise SystemExit("coverage classification anchor missing")
s = s.replace(old2, new2, 1)
p.write_text(s, encoding="utf-8")
print("applied v0.5.9 compile fix")
