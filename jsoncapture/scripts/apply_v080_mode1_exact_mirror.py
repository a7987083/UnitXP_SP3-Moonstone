#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "ManualTaskEngineV05.m"
s = p.read_text(encoding="utf-8")

MARKER = "JCG5_MODE1_EXACT_MIRROR_V080A1"
if MARKER in s:
    print("v0.8.0-alpha1 Mode1 exact mirror already applied")
    raise SystemExit(0)

for required in (
    "JCG5_PAGE_SNAPSHOT_V070",
    "JCG5_SNAPSHOT_COMPLETENESS_V071",
):
    if required not in s:
        raise SystemExit(f"required v0.7.1 baseline marker missing: {required}")


def rep(old: str, new: str, label: str, count: int = 1) -> None:
    global s
    if old not in s:
        raise SystemExit(f"v0.8.0-alpha1 anchor missing: {label}")
    s = s.replace(old, new, count)


# ---------------------------------------------------------------------------
# Mode1 is intentionally NOT a reducer. It mirrors the exact NSData already
# serialized by the proven v0.7.1 runtime_page_snapshot writer. Therefore the
# Mode1 JSON and canonical snapshot are byte-identical for every mirrored write.
# ---------------------------------------------------------------------------
core = r'''
// JCG5_MODE1_EXACT_MIRROR_V080A1
// Mode1 = manual navigation + exact byte mirror of canonical runtime_page_snapshot.
// No second JSON/protobuf reducer, no second serialization, no page heuristics.
static BOOL gJCG80Mode1Active = NO;
static NSString *gJCG80Mode1Dir = nil;
static NSString *gJCG80Mode1LastFile = nil;
static NSString *gJCG80Mode1LastSHA256 = nil;
static unsigned long long gJCG80Mode1MirrorWrites = 0;

static void JCG80Mode1EnsurePath(void) {
    JCG5SetupPaths();
    if (!gJCG80Mode1Dir) {
        gJCG80Mode1Dir = [[gJCG5Root stringByAppendingPathComponent:@"mode1_manual"] retain];
    }
    JCG5EnsureDir(gJCG80Mode1Dir);
}

static void JCG80Mode1SetActive(BOOL active) {
    JCG80Mode1EnsurePath();
    if (active) {
        // A Mode1 run represents only snapshots written while Mode1 is enabled.
        JCG5ResetDirectory(gJCG80Mode1Dir);
    }
    pthread_mutex_lock(&gJCG5StateLock);
    gJCG80Mode1Active = active;
    if (active) {
        gJCG80Mode1MirrorWrites = 0;
        [gJCG80Mode1LastFile release]; gJCG80Mode1LastFile = nil;
        [gJCG80Mode1LastSHA256 release]; gJCG80Mode1LastSHA256 = nil;
    }
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG5SetEvent(active
        ? @"Mode1 ✅ 手动模式已开启｜运行时 snapshot 写什么就原样镜像什么"
        : @"Mode1 已停止｜不再镜像新的 runtime_page_snapshot");
    JCG5Log(active
        ? @"MODE1 v0.8.0-alpha1 start authority=runtime_page_snapshot mirror=exact-bytes"
        : @"MODE1 v0.8.0-alpha1 stop");
}

static void JCG80ToggleMode1(void) {
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL next = !gJCG80Mode1Active;
    pthread_mutex_unlock(&gJCG5StateLock);
    JCG80Mode1SetActive(next);
}

static void JCG80Mode1MirrorSnapshot(NSString *file, NSData *canonicalData, NSString *sessionKey) {
    if (!file.length || !canonicalData.length) return;
    pthread_mutex_lock(&gJCG5StateLock);
    BOOL active = gJCG80Mode1Active;
    pthread_mutex_unlock(&gJCG5StateLock);
    if (!active) return;

    JCG80Mode1EnsurePath();
    NSString *dest = [gJCG80Mode1Dir stringByAppendingPathComponent:file.lastPathComponent];
    NSError *err = nil;
    BOOL wrote = [canonicalData writeToFile:dest options:NSDataWritingAtomic error:&err];
    NSData *mirrorData = wrote ? [NSData dataWithContentsOfFile:dest options:NSDataReadingMappedIfSafe error:&err] : nil;
    BOOL exact = wrote && mirrorData.length == canonicalData.length && [mirrorData isEqualToData:canonicalData];
    NSString *sha = exact ? JCG5SHA256(canonicalData) : @"";

    if (exact) {
        pthread_mutex_lock(&gJCG5StateLock);
        gJCG80Mode1MirrorWrites++;
        unsigned long long writes = gJCG80Mode1MirrorWrites;
        [gJCG80Mode1LastFile release]; gJCG80Mode1LastFile = [file.lastPathComponent copy];
        [gJCG80Mode1LastSHA256 release]; gJCG80Mode1LastSHA256 = [sha copy];
        pthread_mutex_unlock(&gJCG5StateLock);
        JCG5SetEvent([NSString stringWithFormat:@"Mode1 ✅ #%llu %@｜SHA256 %@",
                      writes, file.lastPathComponent, sha]);
        JCG5Log([NSString stringWithFormat:@"MODE1 exact-mirror page=%@ file=%@ bytes=%lu sha256=%@ exact=1",
                 sessionKey ?: @"", file.lastPathComponent, (unsigned long)canonicalData.length, sha]);
    } else {
        JCG5SetEvent([NSString stringWithFormat:@"Mode1 ❌ 镜像失败 %@｜%@",
                      file.lastPathComponent, err ?: @"byte-compare-failed"]);
        JCG5Log([NSString stringWithFormat:@"MODE1 exact-mirror failed page=%@ file=%@ wrote=%d error=%@",
                 sessionKey ?: @"", file.lastPathComponent, wrote, err ?: @"byte-compare-failed"]);
    }
}

'''

rep(
    "static void JCG70WriteSnapshotNow(NSString *sessionKey) {",
    core + "static void JCG70WriteSnapshotNow(NSString *sessionKey) {",
    "insert Mode1 core before canonical writer",
)

saved_log = '''        JCG5Log([NSString stringWithFormat:@"PAGE-SNAPSHOT saved page=%@ events=%lu file=%@ bytes=%lu",
                 sessionKey, (unsigned long)[[entry objectForKey:@"events"] count], file, (unsigned long)d.length]);
'''
rep(
    saved_log,
    saved_log + "        JCG80Mode1MirrorSnapshot(file, d, sessionKey);\n",
    "mirror exact canonical bytes after successful snapshot write",
)

# UI: one explicit Mode1 toggle. No whitelist/session/page-data UI is introduced.
rep(
    '#define JCG5_VERSION @"JSONCapture v0.5 Manual Task Engine"',
    '#define JCG5_VERSION @"JSONCapture v0.8.0-alpha1 Mode1 Exact Mirror"',
    "version string",
)
rep(
    't.text=@"JSONCapture v0.5 手动任务";',
    't.text=@"JSONCapture v0.8｜Mode1 手动";',
    "panel title",
)
rep(
    'CGFloat pw=MIN(306.0,s.width-20),ph=MIN(520.0,s.height-40);',
    'CGFloat pw=MIN(306.0,s.width-20),ph=MIN(570.0,s.height-40);',
    "panel height for Mode1 control",
)
old_buttons = 'NSArray*buttons=@[@[@"抓取：开",NSStringFromSelector(@selector(toggleCapture))],@[@"停止当前任务",NSStringFromSelector(@selector(stopTask))],@[@"开始本地扫描",NSStringFromSelector(@selector(startScan))],@[@"重试扫描失败",NSStringFromSelector(@selector(retryScan))],@[@"开始解密",NSStringFromSelector(@selector(startDecrypt))],@[@"重试解密失败",NSStringFromSelector(@selector(retryDecrypt))],@[@"开始JSON恢复",NSStringFromSelector(@selector(startRecover))],@[@"重试恢复失败",NSStringFromSelector(@selector(retryRecover))]];'
new_buttons = 'NSArray*buttons=@[@[@"抓取：开",NSStringFromSelector(@selector(toggleCapture))],@[@"停止当前任务",NSStringFromSelector(@selector(stopTask))],@[@"开始本地扫描",NSStringFromSelector(@selector(startScan))],@[@"重试扫描失败",NSStringFromSelector(@selector(retryScan))],@[@"开始解密",NSStringFromSelector(@selector(startDecrypt))],@[@"重试解密失败",NSStringFromSelector(@selector(retryDecrypt))],@[@"开始JSON恢复",NSStringFromSelector(@selector(startRecover))],@[@"重试恢复失败",NSStringFromSelector(@selector(retryRecover))],@[@"Mode1 手动 开/关",NSStringFromSelector(@selector(toggleMode1))]];'
rep(old_buttons, new_buttons, "Mode1 toggle button")
rep(
    '- (void)retryRecover { JCG5RequestTask(JCG5TaskRecover,YES); }\n@end',
    '- (void)retryRecover { JCG5RequestTask(JCG5TaskRecover,YES); }\n'
    '- (void)toggleMode1 { JCG80ToggleMode1(); }\n@end',
    "Mode1 controller action",
)

# Marker visible in strings(1) so CI can prove the effective generated source
# reached the binary rather than only existing as a Python comment.
rep(
    'JCG5Log([NSString stringWithFormat:@"%@ loaded; no bundle watcher, no disk watcher, no auto decrypt, no auto recovery",JCG5_VERSION]);',
    'JCG5Log([NSString stringWithFormat:@"%@ loaded; no bundle watcher, no disk watcher, no auto decrypt, no auto recovery; MODE1 exact-byte-mirror canonical=runtime_page_snapshot",JCG5_VERSION]);',
    "runtime binary marker",
)

s += "\n// JCG5_MODE1_EXACT_MIRROR_V080A1 authority=runtime_page_snapshot bytes=identical\n"
p.write_text(s, encoding="utf-8")
print("applied v0.8.0-alpha1 Mode1 exact runtime_page_snapshot mirror")
