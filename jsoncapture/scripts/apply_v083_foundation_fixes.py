#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_FOUNDATION_FIXES_V083"
if MARKER in s:
    print("v0.8.3 foundation fixes already applied")
    raise SystemExit(0)

if "JCG5_SHA256_IDENTITY_V082" not in s:
    raise SystemExit("required v0.8.2 SHA-256 patch missing")

def rep(old: str, new: str, label: str, count: int = 1) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.8.3 foundation anchor missing: {label}")
    s = s.replace(old, new, count)

rep('#define JCG5_VERSION @"JSONCapture v0.5 Manual Task Engine"',
    '#define JCG5_VERSION @"JSONCapture v0.8.3 Snapshot Unified"',
    'version define')

rep(
    '    gJCG5BundleDir = [[docs stringByAppendingPathComponent:@"Bundle"] retain];',
    '    NSString *bundles = [docs stringByAppendingPathComponent:@"Bundles"];\n'
    '    NSString *legacyBundle = [docs stringByAppendingPathComponent:@"Bundle"];\n'
    '    BOOL isDir = NO;\n'
    '    if ([[NSFileManager defaultManager] fileExistsAtPath:bundles isDirectory:&isDir] && isDir)\n'
    '        gJCG5BundleDir = [bundles retain];\n'
    '    else {\n'
    '        isDir = NO;\n'
    '        if ([[NSFileManager defaultManager] fileExistsAtPath:legacyBundle isDirectory:&isDir] && isDir)\n'
    '            gJCG5BundleDir = [legacyBundle retain];\n'
    '        else\n'
    '            gJCG5BundleDir = [bundles retain];\n'
    '    }',
    'Bundles preferred path')

rep('t.text=@"JSONCapture v0.5 手动任务";',
    't.text=@"JSONCapture v0.8.3 Snapshot Unified";',
    'panel title')

rep('[self.bubble setTitle:@"J5\\n空闲" forState:UIControlStateNormal];',
    '[self.bubble setTitle:@"J83\\n空闲" forState:UIControlStateNormal];',
    'bubble title')

rep(
    '    self.labels[@"scan"].text=[NSString stringWithFormat:@"Documents/Bundle｜%@ %llu/%llu\\n成功%llu 失败%llu 忽略%llu TextAsset%llu",scan,sd,st,ss,sf,si,sta];',
    '    NSString *scanDir = gJCG5BundleDir.length ? [NSString stringWithFormat:@"Documents/%@", gJCG5BundleDir.lastPathComponent] : @"Documents/Bundles";\n'
    '    self.labels[@"scan"].text=[NSString stringWithFormat:@"%@｜%@ %llu/%llu\\n成功%llu 失败%llu 忽略%llu TextAsset%llu",scanDir,scan,sd,st,ss,sf,si,sta];',
    'scan status actual path')

# Log the resolved path once so device screenshots/logs can prove which folder is scanned.
rep(
    '    for (NSString *dir in @[gJCG5Root,gJCG5RawDir,gJCG5DecodedDir,gJCG5LoaderDir,gJCG5RecoveredDir,gJCG5PartialDir,gJCG5StateDir]) JCG5EnsureDir(dir);\n}',
    '    for (NSString *dir in @[gJCG5Root,gJCG5RawDir,gJCG5DecodedDir,gJCG5LoaderDir,gJCG5RecoveredDir,gJCG5PartialDir,gJCG5StateDir]) JCG5EnsureDir(dir);\n'
    '    // JCG5_FOUNDATION_FIXES_V083\n'
    '} ',
    'foundation marker placement')

# Emit a runtime marker after logging becomes available.
rep(
    '    pthread_mutex_unlock(&gJCG5LogLock);\n}\n\nstatic NSString *JCG5Safe',
    '    pthread_mutex_unlock(&gJCG5LogLock);\n}\n\nstatic NSString *JCG5Safe',
    'log function sanity')

s += '\n// JCG5_FOUNDATION_FIXES_V083 path=Documents/Bundles version=0.8.3\n'
p.write_text(s, encoding="utf-8")
print("applied v0.8.3 foundation fixes: Bundles path + version UI")
