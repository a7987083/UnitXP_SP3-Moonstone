#!/usr/bin/env python3
from pathlib import Path

p = Path("src/LoginTCPFullFrame.m")
s = p.read_text(encoding="utf-8")


def repl(old: str, new: str, count: int = 1) -> None:
    global s
    found = s.count(old)
    if found != count:
        raise SystemExit(f"expected {count} occurrence(s), found {found}: {old[:100]!r}")
    s = s.replace(old, new, count)

# v9: port-only capture, any IPv4 target. No redirect or packet mutation.
repl('#define TARGET_IP "118.145.146.208"', '#define TARGET_IP "<any IPv4>"')

repl(
'''    gStatusLabel.text = [NSString stringWithFormat:@"FullFrame: %@  TX=%llu RX=%llu\\n%s :7000-7999",\n                         gHooksInstalled ? @"ACTIVE" : @"WAITING",\n                         gTxFrames, gRxFrames, TARGET_IP];''',
'''    gStatusLabel.text = [NSString stringWithFormat:@"FullFrame: %@  TX=%llu RX=%llu\\nANY IPv4 :10003 + :7000-7999",\n                         gHooksInstalled ? @"ACTIVE" : @"WAITING",\n                         gTxFrames, gRxFrames];'''
)

repl(
'''static BOOL IsTargetPort(uint16_t port) {\n    return port >= 7000 && port <= 7999;\n}''',
'''static BOOL IsTargetPort(uint16_t port) {\n    return port == 10003 || (port >= 7000 && port <= 7999);\n}'''
)

repl(
'    if (strcmp(ip, TARGET_IP) != 0 || !IsTargetPort(remotePort)) return NO;',
'    if (!IsTargetPort(remotePort)) return NO;'
)

# sendto / recvfrom explicit-address checks: keep only the port filter.
repl('            target = strcmp(ip, TARGET_IP) == 0 && IsTargetPort(remotePort);',
     '            target = IsTargetPort(remotePort);', 2)

# 10003 frames use a 6-byte header; 700x uses a 10-byte header.
repl(
'''static void WriteFrameFiles(FDState *s, int fd, BOOL tx, const unsigned char *frame, size_t frameLen,\n                            uint16_t msgId, uint32_t seq, uint32_t bodyLen) {\n    if (!s || !frame || frameLen < 10 || !gSessionDir[0]) return;''',
'''static void WriteFrameFiles(FDState *s, int fd, BOOL tx, const unsigned char *frame, size_t frameLen,\n                            uint16_t msgId, uint32_t seq, uint32_t bodyLen, size_t headerLen) {\n    if (!s || !frame || frameLen < headerLen || !gSessionDir[0]) return;'''
)
repl('    if (bodyLen) WriteBinaryFile(bodyPath, frame + 10, bodyLen, NO);',
     '    if (bodyLen) WriteBinaryFile(bodyPath, frame + headerLen, bodyLen, NO);')
repl(
'''static void ParseFrames(FDState *s, int fd, BOOL tx) {\n    StreamBuffer *b = tx ? &s->tx : &s->rx;\n    while (b->len >= 10) {''',
'''static void ParseFrames(FDState *s, int fd, BOOL tx) {\n    StreamBuffer *b = tx ? &s->tx : &s->rx;\n    size_t headerLen = (s->remotePort == 10003) ? 6U : 10U;\n    while (b->len >= headerLen) {'''
)
repl('        size_t total = 10ULL + (size_t)bodyLen;',
     '        size_t total = headerLen + (size_t)bodyLen;')
repl('        uint32_t seq = ReadBE32(b->data + 6);',
     '        uint32_t seq = (headerLen == 10U) ? ReadBE32(b->data + 6) : 0;')
repl('        WriteFrameFiles(s, fd, tx, b->data, total, msgId, seq, bodyLen);',
     '        WriteFrameFiles(s, fd, tx, b->data, total, msgId, seq, bodyLen, headerLen);')

# Metadata / UI / output directory versioning.
repl(
'''    AppendManifestFmt("HOOKS\\trc=%d\\tinstalled=%s\\ttarget=%s:7000-7999\\tmode=read-only-full-frame",\n                      rc, gHooksInstalled ? "YES" : "NO", TARGET_IP);''',
'''    AppendManifestFmt("HOOKS\\trc=%d\\tinstalled=%s\\ttarget=ANY_IPV4:10003,7000-7999\\tmode=read-only-full-frame",\n                      rc, gHooksInstalled ? "YES" : "NO");'''
)
repl('@"Documents/LoginTCPFull_v8"', '@"Documents/LoginTCPFull_v9_Universal"')
repl('@"LoginTCPFullFrame v8\\n"', '@"LoginTCPFullFrame v9 Universal\\n"')
repl('@"Target: 118.145.146.208:7000-7999\\n"', '@"Target: ANY IPv4 on port 10003 or 7000-7999\\n"')
repl(
'@"700x frame: [body_len:4 BE][msg_id:2 BE][seq:4 BE][body]\\n"',
'@"10003 frame: [body_len:4 BE][msg_id:2 BE][body]\\n"\n                            @"700x frame: [body_len:4 BE][msg_id:2 BE][seq:4 BE][body]\\n"'
)
repl(
'''        AppendManifestFmt("SESSION\\t%s\\ttarget=%s:7000-7999\\tmax_body=%u",\n                          stamp.UTF8String, TARGET_IP, (unsigned)MAX_BODY_LEN);''',
'''        AppendManifestFmt("SESSION\\t%s\\ttarget=ANY_IPV4:10003,7000-7999\\tmax_body=%u",\n                          stamp.UTF8String, (unsigned)MAX_BODY_LEN);'''
)
repl('[gFloatButton setTitle:@"FF8" forState:UIControlStateNormal];',
     '[gFloatButton setTitle:@"FF9" forState:UIControlStateNormal];')
repl(
'''    title.text = @"Login TCP FullFrame v8\\n700x full frame + raw stream / read-only";''',
'''    title.text = @"Login TCP FullFrame v9 Universal\\n10003 + 700x full frame / read-only";'''
)

# Safety checks: artifact source must no longer contain the old IP filter.
if '118.145.146.208' in s:
    raise SystemExit('old target IP still present after patch')
if 'strcmp(ip, TARGET_IP)' in s:
    raise SystemExit('IP comparison still present after patch')
if 'port == 10003' not in s:
    raise SystemExit('10003 filter missing after patch')

p.write_text(s, encoding="utf-8")
print("patched LoginTCPFullFrame.m -> v9 Universal (ANY IPv4, ports 10003 + 7000-7999)")
