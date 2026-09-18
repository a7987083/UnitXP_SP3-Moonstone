#!/usr/bin/env python3
from pathlib import Path
p=Path(__file__).resolve().parents[1]/"src"/"ManualTaskEngineV05.m"
s=p.read_text(encoding="utf-8")
MARKER="JCG5_V080_ALPHA5_IDENTITY"
if MARKER in s:
    print("alpha5 identity already applied")
    raise SystemExit(0)
if "JCG5_V080_ALPHA5_ROUTER_DISCOVERY" not in s or "JCG5_V080_ALPHA5_RECOVERY_SHA256_RESUME" not in s:
    raise SystemExit("alpha5 functional markers missing")
old='#define JCG5_VERSION @"JSONCapture v0.8.0-alpha4 Mode1Follower+Mode2RawUI"'
new='#define JCG5_VERSION @"JSONCapture v0.8.0-alpha5 Router+SHA256Resume"'
if old not in s: raise SystemExit("alpha5 version anchor missing")
s=s.replace(old,new,1)
old='t.text=@"JSONCapture v0.8｜Mode1实时镜像 / Mode2全自动";'
new='t.text=@"JSONCapture v0.8 alpha5｜Mode1实时镜像 / Mode2全自动";'
if old not in s: raise SystemExit("alpha5 panel title anchor missing")
s=s.replace(old,new,1)
s+='\n// JCG5_V080_ALPHA5_IDENTITY Router+SHA256Resume\n'
p.write_text(s,encoding='utf-8')
print('applied alpha5 identity')
