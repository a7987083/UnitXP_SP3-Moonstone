#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "OnDeviceLuaRecovery.m"
s = p.read_text(encoding="utf-8")

MARKER = "ODLR_V080_MEMSAFE_G5"
if MARKER in s:
    print("v0.8 recovery memsafe already applied")
    raise SystemExit(0)

if 'OnDeviceLuaRecovery 0.4.2-g4' not in s:
    raise SystemExit('unexpected recovery baseline version')

s = s.replace('OnDeviceLuaRecovery 0.4.2-g4', 'OnDeviceLuaRecovery 0.4.3-g5-memsafe', 1)

start = s.find('static NSDictionary *ODLRRecoverGroup(')
end = s.find('\nstatic NSDictionary *ODLRBuildSummary(', start)
if start < 0 or end < 0:
    raise SystemExit('ODLRRecoverGroup exact boundaries missing')

new_group = r'''// ODLR_V080_MEMSAFE_G5
// Preserve the existing variant/score semantics, but make MRC lifetimes explicit:
// - only top ODLR_BEAM_WIDTH candidates remain retained at any time;
// - previous fragment states are released immediately after survivors are copied;
// - parse/execute/score temporaries drain per candidate instead of per whole group.
static void ODLRInsertTopState(NSMutableArray *top, ODLRState *candidate) {
    if (!top || !candidate) return;
    NSUInteger pos = top.count;
    for (NSUInteger i = 0; i < top.count; i++) {
        ODLRState *cur = [top objectAtIndex:i];
        if (candidate.score > cur.score) { pos = i; break; }
    }
    [top insertObject:candidate atIndex:pos];
    if (top.count > ODLR_BEAM_WIDTH) [top removeLastObject];
}

static NSDictionary *ODLRRecoverGroup(NSString *group, NSArray *entries, NSString *completeDir, NSString *partialDir, BOOL *didWrite) {
    NSMutableDictionary *byIndex = [NSMutableDictionary dictionary];
    for (NSDictionary *e in entries) {
        NSNumber *k = e[@"fragment"];
        NSMutableArray *a = byIndex[k];
        if (!a) { a = [NSMutableArray array]; byIndex[k] = a; }
        [a addObject:e];
    }

    NSArray *indices = [[byIndex allKeys] sortedArrayUsingSelector:@selector(compare:)];
    ODLRState *initial = [[ODLRState alloc] init];
    initial.env = [[[ODLRLuaTable alloc] init] autorelease];
    initial.returns = @[];
    initial.fragments = [NSMutableArray array];
    initial.score = 0;
    NSArray *states = [[NSArray alloc] initWithObjects:initial, nil];
    [initial release];

    BOOL fully = YES;
    NSString *stop = nil;

    for (NSNumber *idx in indices) {
        @autoreleasepool {
            NSArray *variants = [byIndex[idx] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                return [b[@"bytes"] compare:a[@"bytes"]];
            }];
            if (variants.count > ODLR_MAX_VARIANTS_PER_FRAGMENT)
                variants = [variants subarrayWithRange:NSMakeRange(0, ODLR_MAX_VARIANTS_PER_FRAGMENT)];

            NSMutableArray *top = [NSMutableArray arrayWithCapacity:ODLR_BEAM_WIDTH];
            NSDictionary *firstError = nil;

            for (ODLRState *state in states) {
                for (NSDictionary *e in variants) {
                    @autoreleasepool {
                        ODLRLuaTable *env = ODLRDeepClone(state.env);
                        NSData *data = [NSData dataWithContentsOfFile:e[@"path"] options:NSDataReadingMappedIfSafe error:nil];
                        NSString *parseError = nil;
                        NSDictionary *chunk = ODLRParseChunk(data, &parseError);
                        if (!chunk) {
                            if (!firstError) firstError = [@{ @"asset":e[@"asset"], @"sha":e[@"sha"], @"status":@"parse-failed", @"error":parseError?:@"parse failed" } retain];
                            continue;
                        }

                        NSArray *ret = nil;
                        NSString *execError = nil;
                        NSDictionary *exec = ODLRExecute(chunk[@"root"], env, &ret, &execError);
                        if (!exec) {
                            if (!firstError) firstError = [@{ @"asset":e[@"asset"], @"sha":e[@"sha"], @"status":@"dynamic-or-failed", @"error":execError?:@"execute failed" } retain];
                            continue;
                        }

                        ODLRState *candidate = [[[ODLRState alloc] init] autorelease];
                        candidate.env = env;
                        candidate.returns = ret ?: state.returns;
                        candidate.fragments = [NSMutableArray arrayWithArray:state.fragments];
                        [candidate.fragments addObject:@{
                            @"asset":e[@"asset"], @"sha":e[@"sha"], @"fragment":idx, @"status":@"ok",
                            @"execution":@{ @"steps":exec[@"steps"], @"opcodes":exec[@"opcodes"] }
                        }];
                        candidate.score = ODLRResultScore(candidate.env, candidate.returns);
                        ODLRInsertTopState(top, candidate);
                    }
                }
            }

            if (!top.count) {
                NSArray *ranked = [states sortedArrayUsingComparator:^NSComparisonResult(ODLRState *a, ODLRState *b) {
                    return a.score > b.score ? NSOrderedAscending : (a.score < b.score ? NSOrderedDescending : NSOrderedSame);
                }];
                ODLRState *best = ranked.firstObject;
                NSString *why = firstError ? firstError[@"error"] : [NSString stringWithFormat:@"no usable variant at fragment %@", idx];
                [stop release]; stop = [why copy];
                best.stopReason = stop;
                if (firstError) [best.fragments addObject:firstError];
                NSArray *survivors = [[NSArray alloc] initWithObjects:best, nil];
                [states release];
                states = survivors;
                [firstError release];
                fully = NO;
                break;
            }

            NSArray *survivors = [top copy];
            [states release];
            states = survivors;
            [firstError release];
        }
    }

    NSArray *ranked = [states sortedArrayUsingComparator:^NSComparisonResult(ODLRState *a, ODLRState *b) {
        return a.score > b.score ? NSOrderedAscending : (a.score < b.score ? NSOrderedDescending : NSOrderedSame);
    }];
    ODLRState *best = ranked.firstObject;
    NSArray *tables = ODLRExtractTables(best.env, best.returns, group);
    NSMutableArray *tableReport = [NSMutableArray array];
    BOOL malformedAny = NO;
    NSUInteger completeCount = 0, partialCount = 0, recordCount = 0;

    for (NSDictionary *item in tables) {
        @autoreleasepool {
            NSString *label = item[@"label"];
            ODLRLuaTable *table = item[@"table"];
            NSDictionary *ser = ODLRSerializeTable(label, table);
            id payload = ser[@"payload"];
            if (!payload) continue;
            NSArray *malformed = ser[@"malformed"];
            BOOL partial = !fully || malformed.count > 0;
            malformedAny |= malformed.count > 0;
            NSString *stem = label;
            if ([[stem uppercaseString] hasPrefix:@"TAB_"]) stem = [stem substringFromIndex:4];
            if ([stem hasPrefix:@"RETURN_"]) stem = group;
            stem = ODLRSafeName(stem, 120);
            NSString *dir = partial ? partialDir : completeDir;
            NSString *out = [dir stringByAppendingPathComponent:[stem stringByAppendingPathExtension:@"json"]];
            if (ODLRWriteJSON(payload, out)) {
                if (didWrite) *didWrite = YES;
                if (partial) partialCount++; else completeCount++;
                recordCount += [ser[@"records"] unsignedIntegerValue];
                [tableReport addObject:@{
                    @"label":label, @"origin":item[@"origin"], @"mode":ser[@"mode"], @"records":ser[@"records"],
                    @"partial":@(partial), @"malformed_rows":malformed, @"file":out
                }];
            }
        }
    }

    NSString *status;
    if (tableReport.count) status = (!fully || malformedAny) ? @"partial" : @"complete";
    else {
        BOOL hasError = NO;
        for (NSDictionary *f in best.fragments) if (![f[@"status"] isEqualToString:@"ok"]) { hasError = YES; break; }
        status = hasError ? @"dynamic" : @"static-no-table";
    }

    NSDictionary *result = @{
        @"group":group,
        @"status":status,
        @"fully_processed":@(fully),
        @"stop_reason":stop ?: [NSNull null],
        @"fragments":best.fragments ?: @[],
        @"tables":tableReport,
        @"tables_complete":@(completeCount),
        @"tables_partial":@(partialCount),
        @"records":@(recordCount),
        @"variants_seen":@(entries.count)
    };
    [states release];
    [stop release];
    return result;
}
'''

s = s[:start] + new_group + s[end:]

# Emit progress BEFORE expensive group work as well as after it. This makes a
# hang/crash log identify the exact group that was entered.
old_loop = '''    for(NSString *group in sorted){@autoreleasepool{if(shouldYield&&shouldYield()){yielded=YES;break;}NSArray *shas=[groupSHAs[group] sortedArrayUsingSelector:@selector(compare:)];NSString *signature=ODLRSHA256([[shas componentsJoinedByString:@"|"] dataUsingEncoding:NSUTF8StringEncoding]);if(!forceAll&&[processed[group][@"signature"] isEqualToString:signature])continue;attempted++;BOOL didWrite=NO;NSDictionary *result=ODLRRecoverGroup(group,groups[group],completeDir,partialDir,&didWrite);reportGroups[group]=result;processed[group]=@{ @"signature":signature,@"status":result[@"status"],@"updated_at":@([[NSDate date] timeIntervalSince1970]) };changed++;if(didWrite)written++;if(progress)progress(@{ @"stage":@"recover",@"group":group,@"attempted":@(attempted),@"groups_total":@(sorted.count),@"status":result[@"status"] });}}
'''
new_loop = '''    for(NSString *group in sorted){@autoreleasepool{if(shouldYield&&shouldYield()){yielded=YES;break;}NSArray *shas=[groupSHAs[group] sortedArrayUsingSelector:@selector(compare:)];NSString *signature=ODLRSHA256([[shas componentsJoinedByString:@"|"] dataUsingEncoding:NSUTF8StringEncoding]);if(!forceAll&&[processed[group][@"signature"] isEqualToString:signature])continue;attempted++;if(progress)progress(@{ @"stage":@"recover_begin",@"group":group,@"attempted":@(attempted),@"groups_total":@(sorted.count),@"variants":@([groups[group] count]) });BOOL didWrite=NO;NSDictionary *result=ODLRRecoverGroup(group,groups[group],completeDir,partialDir,&didWrite);reportGroups[group]=result;processed[group]=@{ @"signature":signature,@"status":result[@"status"],@"updated_at":@([[NSDate date] timeIntervalSince1970]) };changed++;if(didWrite)written++;if(progress)progress(@{ @"stage":@"recover_end",@"group":group,@"attempted":@(attempted),@"groups_total":@(sorted.count),@"status":result[@"status"],@"written":@(didWrite),@"records":result[@"records"]?:@0 });}}
'''
if old_loop not in s:
    raise SystemExit('recovery loop anchor missing')
s = s.replace(old_loop, new_loop, 1)

p.write_text(s, encoding='utf-8')
print('applied v0.8 recovery MRC-safe bounded-beam lifetime fix')
