#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "OnDeviceLuaRecovery.m"
s = p.read_text(encoding="utf-8")
marker = "ODLR_RECOVERY_SUMMARY_RESTORE_V083"
if marker in s:
    print("v0.8.3 recovery summary restore already applied")
    raise SystemExit(0)

if "static NSDictionary *ODLRBuildSummary(NSDictionary *groups)" not in s:
    anchor = "\nNSDictionary *ODLRRecoverDecodedDirectory("
    pos = s.find(anchor)
    if pos < 0:
        raise SystemExit("ODLRRecoverDecodedDirectory anchor missing")
    helper = r'''

// ODLR_RECOVERY_SUMMARY_RESTORE_V083
static NSDictionary *ODLRBuildSummary(NSDictionary *groups) {
    unsigned long long gc=0,gp=0,gd=0,gn=0,tc=0,tp=0,records=0,malformed=0;
    for(NSDictionary *r in groups.allValues){
        NSString *st=r[@"status"];
        if([st isEqualToString:@"complete"])gc++;
        else if([st isEqualToString:@"partial"])gp++;
        else if([st isEqualToString:@"dynamic"])gd++;
        else gn++;
        tc+=[r[@"tables_complete"] unsignedLongLongValue];
        tp+=[r[@"tables_partial"] unsignedLongLongValue];
        records+=[r[@"records"] unsignedLongLongValue];
        for(NSDictionary *t in r[@"tables"])malformed+=[t[@"malformed_rows"] count];
    }
    return @{
        @"groups_total":@(groups.count),
        @"groups_complete":@(gc),
        @"groups_partial":@(gp),
        @"groups_dynamic":@(gd),
        @"groups_static_no_table":@(gn),
        @"tables_complete":@(tc),
        @"tables_partial":@(tp),
        @"records_recovered":@(records),
        @"malformed_rows":@(malformed)
    };
}
'''
    s = s[:pos] + helper + s[pos:]
else:
    s += "\n// ODLR_RECOVERY_SUMMARY_RESTORE_V083 existing-summary-preserved\n"

p.write_text(s, encoding="utf-8")
print("applied v0.8.3 recovery summary preservation")
