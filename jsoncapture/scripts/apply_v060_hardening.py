#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_PAGE_PROTOBUF_V060_HARDENED"
if MARKER in s:
    print("v0.6.0 hardening already applied")
    raise SystemExit(0)
if "JCG5_PAGE_PROTOBUF_V060" not in s:
    raise SystemExit("v0.6.0 page/protobuf patch missing")


def rep(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.6.0 hardening anchor missing: {label}")
    s = s.replace(old, new, 1)

rep(
    "            JCG60Pop(L, 1); // pop value; keep key for lua_next\n"
    "            if (*budget >= JCG60_LUA_SNAPSHOT_MAX_NODES) break;\n",
    "            JCG60Pop(L, 1); // pop value; keep key for lua_next\n"
    "            if (*budget >= JCG60_LUA_SNAPSHOT_MAX_NODES) { JCG60Pop(L, 1); break; }\n",
    "balanced lua_next break",
)

rep(
    "static NSString *JCG60MsgName(void *L, long long msgid) {\n"
    "    if (!gJCG60MsgNamesReady) JCG60BuildMsgNames(L);\n"
    "    NSString *name = [gJCG60MsgNames objectForKey:@(msgid)];\n"
    "    return name ?: [NSString stringWithFormat:@\"MSGID_%lld\", msgid];\n"
    "}\n",
    "static NSString *JCG60MsgName(void *L, long long msgid) {\n"
    "    if (!gJCG60MsgNamesReady) JCG60BuildMsgNames(L);\n"
    "    NSString *name = [gJCG60MsgNames objectForKey:@(msgid)];\n"
    "    return name ?: [NSString stringWithFormat:@\"MSGID_%lld\", msgid];\n"
    "}\n"
    "// JCG5_PAGE_PROTOBUF_V060_HARDENED\n"
    "static BOOL JCG60IsNoiseMessage(NSString *name) {\n"
    "    return [name rangeOfString:@\"KEEPALIVE\" options:NSCaseInsensitiveSearch].location != NSNotFound;\n"
    "}\n",
    "noise helper",
)

rep(
    "        if (ok) {\n"
    "            unsigned long long seq = 0;\n",
    "        if (ok && !JCG60IsNoiseMessage(JCG60MsgName(L, msgid))) {\n"
    "            unsigned long long seq = 0;\n",
    "request keepalive filter",
)

rep(
    "    if (enabled && ok) {\n"
    "        unsigned long long seq = 0;\n",
    "    if (enabled && ok && !JCG60IsNoiseMessage(JCG60MsgName(L, msgid))) {\n"
    "        unsigned long long seq = 0;\n",
    "response keepalive filter",
)

p.write_text(s, encoding="utf-8")
print("applied v0.6.0 stack/noise hardening")
