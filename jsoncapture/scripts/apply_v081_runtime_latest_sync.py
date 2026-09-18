#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_RUNTIME_LATEST_SYNC_V081"
if MARKER in s:
    print("v0.8.1 runtime latest sync already applied")
    raise SystemExit(0)

for required in (
    "JCG5_PAGE_DEPENDENCY_V080",
    "JCG5_PAGE_DEPENDENCY_V080_RUNTIME_AUTO_FIX",
):
    if required not in s:
        raise SystemExit(f"required prior patch missing: {required}")

def rep(old, new, label):
    global s
    if old not in s:
        raise SystemExit(f"v0.8.1 anchor missing: {label}")
    s = s.replace(old, new, 1)

# Make the no-session state accurately describe the permanent watcher.
rep(
    'JCG80SetStatus([NSString stringWithFormat:@"Mode1｜白名单%lu｜等待开始", (unsigned long)gJCG80Whitelist.count]);',
    'JCG80SetStatus([NSString stringWithFormat:@"Mode1 v0.8.1 ✅ 自动监听｜白名单%lu｜等待运行时最新 UI", (unsigned long)gJCG80Whitelist.count]);',
    "no-session watcher status",
)

# Make active-session status visibly identify this fixed build.
rep(
    'JCG80SetStatus([NSString stringWithFormat:@"Mode1 %@｜%@\\n白名单%lu 配置%lu Model候选%lu 协议%lu 候选%lu",',
    'JCG80SetStatus([NSString stringWithFormat:@"Mode1 v0.8.1 %@｜%@\\n白名单%lu 配置%lu Model候选%lu 协议%lu 候选%lu",',
    "active watcher status",
)

# Startup status: no manual start semantics remain.
rep(
    'JCG80SetStatus([NSString stringWithFormat:@"Mode1 ✅ 自动监听｜白名单%lu\\n等待运行时最新 UI 变化", (unsigned long)gJCG80Whitelist.count]);',
    'JCG80SetStatus([NSString stringWithFormat:@"Mode1 v0.8.1 ✅ 自动监听｜白名单%lu\\n等待运行时最新 UI 变化", (unsigned long)gJCG80Whitelist.count]);',
    "startup watcher status",
)

# Whitelist import status also preserves the explicit v0.8.1 identity.
rep(
    'JCG80SetStatus([NSString stringWithFormat:@"Mode1 ✅ 自动监听｜白名单%lu\\n白名单已导入，等待运行时 UI 变化", (unsigned long)gJCG80Whitelist.count]);',
    'JCG80SetStatus([NSString stringWithFormat:@"Mode1 v0.8.1 ✅ 自动监听｜白名单%lu\\n白名单已导入，等待运行时 UI 变化", (unsigned long)gJCG80Whitelist.count]);',
    "whitelist watcher status",
)

# The top "运行时抓取 -> 最新" row is driven by gJCG5LastCaptureChunk. Feed the
# exact same runtime-latest event into Mode1 on the same serial capture queue.
# This removes the previous reliance on a separate queued observation path.
anchor = 'pthread_mutex_lock(&gJCG5StateLock);gJCG5CaptureCount++;unsigned long long seq=gJCG5CaptureCount;[gJCG5LastCaptureChunk release];gJCG5LastCaptureChunk=[chunk copy];pthread_mutex_unlock(&gJCG5StateLock);'
replacement = anchor + '\n' + \
    '        // JCG5_RUNTIME_LATEST_SYNC_V081: Mode1 follows the exact source used by the visible runtime Latest field.\n' + \
    '        NSDictionary *runtimeLatestCtx = JCG60PageContextSnapshot();\n' + \
    '        JCG80ObserveLuaChunkOnQueue(chunk, runtimeLatestCtx);\n'
rep(anchor, replacement, "runtime latest source bridge")

# Version page-data output so device exports can be attributed unambiguously.
rep(
    '@"version": @"0.8.0-runtime-auto",',
    '@"version": @"0.8.1-runtime-latest",',
    "page-data version",
)

# Add an ASCII readiness marker for CI/binary verification.
rep(
    'JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY v0.8.0 runtime-auto ready mode1=runtime-ui-watch mode2=explicit-start whitelist=%lu quiet=%.1fs unknown=never-active",',
    'JCG5Log(@"PAGE-DEPENDENCY v0.8.1 runtime-latest-source exact-visible-latest");\n'
    '        JCG5Log([NSString stringWithFormat:@"PAGE-DEPENDENCY v0.8.0 runtime-auto ready mode1=runtime-ui-watch mode2=explicit-start whitelist=%lu quiet=%.1fs unknown=never-active",',
    "v081 readiness marker",
)

p.write_text(s, encoding="utf-8")
print("applied v0.8.1 runtime latest sync")
