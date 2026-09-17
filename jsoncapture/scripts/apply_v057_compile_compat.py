#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_UNITY_ALL_JSON_V057_COMPILE_COMPAT"
if MARKER in s:
    print("v0.5.7 compile compatibility patch already applied")
    raise SystemExit(0)
if "JCG5_UNITY_ALL_JSON_V057" not in s:
    raise SystemExit("v0.5.7 Unity backend JSON patch must be applied first")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.5.7 compat anchor missing: {label}")
    s = s.replace(old, new, 1)

rep(
    "// JCG5_UNITY_ALL_JSON_V057: NSURLSession delegate body capture for all UnityWebRequest handlers.\n",
    "// JCG5_UNITY_ALL_JSON_V057: NSURLSession delegate body capture for all UnityWebRequest handlers.\n"
    "// JCG5_UNITY_ALL_JSON_V057_COMPILE_COMPAT\n",
    "compat marker",
)

# JCG5CompileCompat.h intentionally types NSMutableDictionary keyed-subscripting
# as UILabel * for the legacy menu code. Use objectForKey: for non-UI dictionaries
# so -Werror does not misinfer our response metadata/body objects as UILabel.
rep(
    "            BOOL backendAlreadyTraced = [record[@\"source\"] isEqualToString:@\"UnityWebRequest.DownloadHandlerBuffer.GetData\"] &&\n"
    "                                        [gJCG57BackendMD5s containsObject:md5];\n",
    "            NSString *recordSource = (NSString *)[record objectForKey:@\"source\"];\n"
    "            BOOL backendAlreadyTraced = [recordSource isEqualToString:@\"UnityWebRequest.DownloadHandlerBuffer.GetData\"] &&\n"
    "                                        [gJCG57BackendMD5s containsObject:md5];\n",
    "record source type",
)

rep(
    "            NSMutableData *body = state[@\"body\"];\n",
    "            NSMutableData *body = (NSMutableData *)[state objectForKey:@\"body\"];\n",
    "backend body mutable type",
)

rep(
    "        if ([state[@\"body\"] length] == chunk.length) {\n",
    "        if ([(NSData *)[state objectForKey:@\"body\"] length] == chunk.length) {\n",
    "backend body length type",
)

rep(
    "        NSData *body = [state[@\"body\"] retain];\n",
    "        NSData *body = [[state objectForKey:@\"body\"] retain];\n",
    "backend body retained type",
)

p.write_text(s, encoding="utf-8")
print("applied v0.5.7 NSMutableDictionary compile compatibility")
