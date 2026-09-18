#!/usr/bin/env python3
from pathlib import Path

p = Path(__file__).resolve().parents[1] / "src" / "OnDeviceLuaRecovery.m"
s = p.read_text(encoding="utf-8")

MARKER = "ODLR_RECOVERY_MEMORY_V083"
if MARKER in s:
    print("v0.8.3 recovery memory patch already applied")
    raise SystemExit(0)

start = s.find("static NSDictionary *ODLRRecoverGroup(NSString *group, NSArray *entries, NSString *completeDir, NSString *partialDir, BOOL *didWrite) {")
end = s.find("\nNSDictionary *ODLRRecoverDecodedDirectory(", start)
if start < 0 or end < 0:
    raise SystemExit("ODLRRecoverGroup anchors missing")

new_func = r'''// ODLR_RECOVERY_MEMORY_V083
// Exact beam semantics are preserved, but variants are parsed once and the
// running candidate union is pruned to the same top-K after every variant.
// Since candidate scores are immutable within a fragment, incremental top-K is
// identical to pruning the full union at the end, while retaining at most
// ODLR_BEAM_WIDTH candidate environments instead of states*variants.
static NSDictionary *ODLRRecoverGroup(NSString *group, NSArray *entries, NSString *completeDir, NSString *partialDir, BOOL *didWrite) {
    NSMutableDictionary *byIndex=[NSMutableDictionary dictionary];
    for(NSDictionary *e in entries){
        NSNumber *k=e[@"fragment"];
        NSMutableArray *a=byIndex[k];
        if(!a){a=[NSMutableArray array];byIndex[k]=a;}
        [a addObject:e];
    }
    NSArray *indices=[[byIndex allKeys] sortedArrayUsingSelector:@selector(compare:)];
    ODLRState *initial=[[[ODLRState alloc]init]autorelease];
    initial.env=[[[ODLRLuaTable alloc]init]autorelease];
    initial.returns=@[];
    initial.fragments=[NSMutableArray array];
    initial.score=0;
    NSArray *states=@[initial];
    BOOL fully=YES;
    NSString *stop=nil;
    NSUInteger peakCandidateStates=states.count;
    NSUInteger parsedVariantCount=0;

    for(NSNumber *idx in indices){
        @autoreleasepool {
            NSArray *variants=[byIndex[idx] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){return [b[@"bytes"] compare:a[@"bytes"]];}];
            if(variants.count>ODLR_MAX_VARIANTS_PER_FRAGMENT)
                variants=[variants subarrayWithRange:NSMakeRange(0,ODLR_MAX_VARIANTS_PER_FRAGMENT)];

            NSMutableArray *next=[NSMutableArray arrayWithCapacity:ODLR_BEAM_WIDTH];
            NSMutableArray *errors=[NSMutableArray array];

            // Parse each variant once, then apply it to every incoming beam state.
            // The old code parsed the same bytecode once per state.
            for(NSDictionary *e in variants){
                @autoreleasepool {
                    NSData *data=[NSData dataWithContentsOfFile:e[@"path"] options:NSDataReadingMappedIfSafe error:nil];
                    NSString *parseError=nil;
                    NSDictionary *chunk=ODLRParseChunk(data,&parseError);
                    parsedVariantCount++;
                    if(!chunk){
                        [errors addObject:@{ @"asset":e[@"asset"]?:@"", @"sha":e[@"sha"]?:@"", @"status":@"parse-failed", @"error":parseError?:@"parse failed" }];
                        continue;
                    }

                    for(ODLRState *state in states){
                        @autoreleasepool {
                            ODLRLuaTable *env=ODLRDeepClone(state.env);
                            NSArray *ret=nil;
                            NSString *execError=nil;
                            NSDictionary *exec=ODLRExecute(chunk[@"root"],env,&ret,&execError);
                            if(!exec){
                                [errors addObject:@{ @"asset":e[@"asset"]?:@"", @"sha":e[@"sha"]?:@"", @"status":@"dynamic-or-failed", @"error":execError?:@"execute failed" }];
                            } else {
                                ODLRState *candidate=[[[ODLRState alloc]init]autorelease];
                                candidate.env=env;
                                candidate.returns=ret?:state.returns;
                                candidate.fragments=[NSMutableArray arrayWithArray:state.fragments];
                                [candidate.fragments addObject:@{
                                    @"asset":e[@"asset"]?:@"",
                                    @"sha":e[@"sha"]?:@"",
                                    @"fragment":idx,
                                    @"status":@"ok",
                                    @"execution":@{ @"steps":exec[@"steps"]?:@0, @"opcodes":exec[@"opcodes"]?:@{} }
                                }];
                                candidate.score=ODLRResultScore(candidate.env,candidate.returns);
                                [next addObject:candidate];
                            }
                        }
                    }

                    // Incremental top-K over immutable scores is exactly the same
                    // as sorting the complete candidate union after all variants.
                    [next sortUsingComparator:^NSComparisonResult(ODLRState*a,ODLRState*b){
                        return a.score>b.score?NSOrderedAscending:(a.score<b.score?NSOrderedDescending:NSOrderedSame);
                    }];
                    if(next.count>ODLR_BEAM_WIDTH)
                        [next removeObjectsInRange:NSMakeRange(ODLR_BEAM_WIDTH,next.count-ODLR_BEAM_WIDTH)];
                    peakCandidateStates=MAX(peakCandidateStates,next.count);
                }
            }

            if(!next.count){
                fully=NO;
                stop=errors.count?errors[0][@"error"]:[NSString stringWithFormat:@"no usable variant at fragment %@",idx];
                ODLRState *best=[states sortedArrayUsingComparator:^NSComparisonResult(ODLRState*a,ODLRState*b){return a.score>b.score?NSOrderedAscending:(a.score<b.score?NSOrderedDescending:NSOrderedSame);}].firstObject;
                best.stopReason=stop;
                if(errors.count)[best.fragments addObject:errors[0]];
                states=@[best];
                break;
            }

            // Materialize a small retained beam before this fragment's pool drains.
            states=[NSArray arrayWithArray:next];
        }
    }

    ODLRState *best=[states sortedArrayUsingComparator:^NSComparisonResult(ODLRState*a,ODLRState*b){return a.score>b.score?NSOrderedAscending:(a.score<b.score?NSOrderedDescending:NSOrderedSame);}].firstObject;
    NSArray *tables=ODLRExtractTables(best.env,best.returns,group);
    NSMutableArray *tableReport=[NSMutableArray array];
    BOOL malformedAny=NO;
    NSUInteger completeCount=0,partialCount=0,recordCount=0;
    for(NSDictionary *item in tables){
        @autoreleasepool {
            NSString *label=item[@"label"];
            ODLRLuaTable *table=item[@"table"];
            NSDictionary *ser=ODLRSerializeTable(label,table);
            id payload=ser[@"payload"];
            if(!payload)continue;
            NSArray *malformed=ser[@"malformed"];
            BOOL partial=!fully||malformed.count>0;
            malformedAny|=malformed.count>0;
            NSString *stem=label;
            if([[stem uppercaseString] hasPrefix:@"TAB_"])stem=[stem substringFromIndex:4];
            if([stem hasPrefix:@"RETURN_"])stem=group;
            stem=ODLRSafeName(stem,120);
            NSString *dir=partial?partialDir:completeDir;
            NSString *out=[dir stringByAppendingPathComponent:[stem stringByAppendingPathExtension:@"json"]];
            if(ODLRWriteJSON(payload,out)){
                if(didWrite)*didWrite=YES;
                if(partial)partialCount++;else completeCount++;
                recordCount+=[ser[@"records"] unsignedIntegerValue];
                [tableReport addObject:@{
                    @"label":label?:@"",
                    @"origin":item[@"origin"]?:@"",
                    @"mode":ser[@"mode"]?:@"",
                    @"records":ser[@"records"]?:@0,
                    @"partial":@(partial),
                    @"malformed_rows":malformed?:@[],
                    @"file":out?:@""
                }];
            }
        }
    }

    NSString *status;
    if(tableReport.count)status=(!fully||malformedAny)?@"partial":@"complete";
    else{
        BOOL hasError=NO;
        for(NSDictionary *f in best.fragments)if(![f[@"status"] isEqualToString:@"ok"]){hasError=YES;break;}
        status=hasError?@"dynamic":@"static-no-table";
    }

    return @{
        @"group":group?:@"",
        @"status":status,
        @"fully_processed":@(fully),
        @"stop_reason":stop?:[NSNull null],
        @"fragments":best.fragments?:@[],
        @"tables":tableReport,
        @"tables_complete":@(completeCount),
        @"tables_partial":@(partialCount),
        @"records":@(recordCount),
        @"variants_seen":@(entries.count),
        @"memory_model":@{
            @"version":@"v0.8.3-bounded-beam",
            @"beam_width":@(ODLR_BEAM_WIDTH),
            @"max_variants_per_fragment":@(ODLR_MAX_VARIANTS_PER_FRAGMENT),
            @"peak_retained_candidate_states":@(peakCandidateStates),
            @"parsed_variants":@(parsedVariantCount),
            @"parse_once_per_variant":@YES,
            @"incremental_exact_top_k":@YES
        }
    };
}
'''

s = s[:start] + new_func + s[end:]
p.write_text(s, encoding="utf-8")
print("applied v0.8.3 recovery memory: parse-once + exact bounded top-K beam")
