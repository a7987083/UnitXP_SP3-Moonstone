#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "OnDeviceLuaRecovery.m"
s = p.read_text(encoding="utf-8")
MARKER = "ODLR_V080_ALPHA6_RECOVERED_JSON_HASHCHECK"
if MARKER in s:
    print("alpha6 recovered_json hashcheck already applied")
    raise SystemExit(0)
if "ODLR_V080_ALPHA6_FAST_RESUME" not in s:
    raise SystemExit("alpha6 fast-resume marker missing")

start = s.find('static BOOL ODLRValidateManifestEntry(NSDictionary *entry, NSString *outputRoot) {')
end = s.find('\nstatic NSArray *ODLROutputRecordsForResult(', start)
if start < 0 or end < 0:
    raise SystemExit('manifest validator boundaries missing')

validator = r'''// ODLR_V080_ALPHA6_RECOVERED_JSON_HASHCHECK
// Resume policy:
//   complete/output groups -> verify the actual recovered_json (or recorded output)
//                             bytes against Recovery.SHA256.txt before skipping.
//   zero-output dynamic/static groups -> no JSON exists to hash; committed source
//                                        signature is sufficient for skip.
// This preserves full output integrity without rerunning recovery.
static BOOL ODLRValidateManifestEntry(NSDictionary *entry, NSString *outputRoot) {
    if (![entry[@"committed"] boolValue]) return NO;
    NSArray *records=ODLRManifestRecords(entry);
    NSInteger expected=[entry[@"expected"] integerValue];
    if ((NSInteger)records.count!=expected) return NO;

    NSString *status=[entry[@"status"] isKindOfClass:[NSString class]]?entry[@"status"]:@"unknown";
    if (expected==0) {
        return [status isEqualToString:@"dynamic"] || [status isEqualToString:@"static-no-table"];
    }

    for (NSDictionary *rec in records) {
        NSString *expectedSHA=[rec[@"sha256"] isKindOfClass:[NSString class]]?rec[@"sha256"]:@"";
        NSString *stored=[rec[@"path"] isKindOfClass:[NSString class]]?rec[@"path"]:@"";
        if (expectedSHA.length!=64 || !stored.length) return NO;

        // Recovery FILE records are expected to point at recovered_json/*.json
        // for complete output.  Keep recorded relative-path support so partial
        // output remains verifiable too.
        NSString *path=ODLRStoredOutputPath(stored,outputRoot);
        NSString *actual=ODLRFileSHA256(path);
        if (actual.length!=64 || ![actual isEqualToString:expectedSHA]) return NO;
    }
    return YES;
}
'''

s = s[:start] + validator + s[end:]
s += '\n// ODLR_V080_ALPHA6_RECOVERED_JSON_HASHCHECK output=actual-SHA256 manifest=Recovery.SHA256.txt\n'
p.write_text(s, encoding='utf-8')
print('applied alpha6 recovered_json actual SHA256 validation')
