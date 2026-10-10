#import <Foundation/Foundation.h>
#import "ZNIL2CPPABIMetadata.h"

static void Expect(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.Void") == ZNIL2CPPABIValueKindVoid, @"void");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.Boolean") == ZNIL2CPPABIValueKindBool, @"bool");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.Int32") == ZNIL2CPPABIValueKindSigned32, @"int32");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.UInt32") == ZNIL2CPPABIValueKindUnsigned32, @"uint32");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.Int64") == ZNIL2CPPABIValueKindSigned64, @"int64");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.UInt64") == ZNIL2CPPABIValueKindUnsigned64, @"uint64");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.Single") == ZNIL2CPPABIValueKindFloat32, @"float");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.Double") == ZNIL2CPPABIValueKindFloat64, @"double");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"System.IntPtr") == ZNIL2CPPABIValueKindPointer, @"intptr");
        Expect(ZNIL2CPPABIKindForManagedTypeName(@"com.game.CustomStruct") == ZNIL2CPPABIValueKindUnknown, @"custom type stays runtime-classified");

        // The matrix exercises the production allocation-plan function,
        // not a duplicated test-only algorithm.
        NSDictionary *gpr=@{@"kind":@(ZNIL2CPPABIValueKindSigned64)};
        NSDictionary *fpr=@{@"kind":@(ZNIL2CPPABIValueKindFloat64)};
        NSDictionary *(^aggregate)(NSUInteger, NSUInteger, BOOL, NSUInteger)=
          ^NSDictionary *(NSUInteger size, NSUInteger alignment, BOOL hfa, NSUInteger elements) {
            NSMutableArray *members=[NSMutableArray array];
            for(NSUInteger i=0;i<elements;i++)
                [members addObject:@{@"kind":@(ZNIL2CPPABIValueKindFloat32)}];
            return @{@"kind":@(ZNIL2CPPABIValueKindComplexValueType),
                     @"layoutKnown":@YES,@"valueSize":@(size),@"alignment":@(alignment),
                     @"hfaShapeConsistent":@(hfa),@"hfaCandidate":@(hfa),
                     @"members":members};
          };
        NSArray *(^plan)(NSArray *,BOOL)=^NSArray *(NSArray *args, BOOL instance) {
            return ZNIL2CPPABIDescribeAllocationPlan(
              @{@"available":@YES,@"instanceKnown":@YES,
                @"genericStatusKnown":@YES,@"generic":@NO,@"inflated":@NO,
                @"instance":@(instance),@"parameters":args});
        };
        NSDictionary *a8=aggregate(8,8,NO,0);
        NSDictionary *a16=aggregate(16,8,NO,0);
        NSDictionary *a24=aggregate(24,8,NO,0);
        NSDictionary *hfa4=aggregate(16,4,YES,4);
        NSArray *result=plan(@[a8,a16,a24],NO);
        Expect(result.count==3,@"aggregate plan returns all args");
        Expect([result[0][@"storage"] isEqual:@"gpr"] &&
               [result[0][@"registerSlots"] integerValue]==1,@"8-byte aggregate one GPR");
        Expect([result[1][@"index"] integerValue]==1 &&
               [result[1][@"registerSlots"] integerValue]==2,@"16-byte aggregate two GPR");
        Expect([result[2][@"index"] integerValue]==3 &&
               [result[2][@"stackBytes"] integerValue]==8,@"large aggregate indirect pointer");
        Expect(![result[2][@"verified"] boolValue],@"aggregate never marked verified");
        result=plan(@[hfa4,fpr],NO);
        Expect([result[0][@"storage"] isEqual:@"fpr"] &&
               [result[0][@"registerSlots"] integerValue]==4,@"HFA four FPRs");
        Expect([result[1][@"index"] integerValue]==4,@"scalar follows HFA FPR");
        result=plan(@[fpr,fpr,fpr,fpr,fpr,fpr,hfa4,fpr],NO);
        Expect([result[6][@"storage"] isEqual:@"stack"],@"HFA spills on FPR exhaustion");
        Expect([result[7][@"storage"] isEqual:@"stack"],@"FP slots not reused after HFA spill");
        result=plan(@[gpr,gpr,gpr,gpr,gpr,gpr,gpr,a16,gpr],NO);
        Expect([result[7][@"storage"] isEqual:@"stack"] &&
               [result[7][@"stackBytes"] integerValue]==16,@"two-GPR aggregate spills whole");
        Expect([result[8][@"storage"] isEqual:@"stack"] &&
               [result[8][@"index"] integerValue]==2,@"GPR exhaustion advances stack");
        result=plan(@[gpr,gpr,gpr,gpr,gpr,gpr,gpr,gpr,a16,aggregate(16,16,NO,0)],NO);
        Expect([result[9][@"storage"] isEqual:@"stack"] &&
               [result[9][@"index"] integerValue]==2,@"16-byte stack alignment");
        result=plan(@[gpr,a24],YES);
        Expect([result[0][@"index"] integerValue]==1 &&
               [result[1][@"index"] integerValue]==2,@"instance consumes x0");
        Expect(plan(@[aggregate(0,8,NO,0)],NO)==nil,@"invalid aggregate rejected");
        Expect(plan(@[a8],NO)[0][@"verified"]==@NO ||
               ![plan(@[a8],NO)[0][@"verified"] boolValue],@"unverified aggregate stays diagnostic");
        NSLog(@"il2cpp_abi_classifier_test: PASS");
    }
    return 0;
}
