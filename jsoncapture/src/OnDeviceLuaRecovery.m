#import "OnDeviceLuaRecovery.h"
#import <CommonCrypto/CommonDigest.h>

#include <stdint.h>
#include <string.h>
#include <math.h>

#define ODLR_VERSION @"OnDeviceLuaRecovery 0.4.2-g4"
#define ODLR_ENCM_XOR_KEY 0x4D
#define ODLR_LFIELDS_PER_FLUSH 50
#define ODLR_MAX_COUNT 100000000
#define ODLR_MAX_STATIC_STEPS_FACTOR 4
#define ODLR_MAX_VARIANTS_PER_FRAGMENT 4
#define ODLR_BEAM_WIDTH 4
#define ODLR_MAX_DEPTH 128

static NSString * const kODLRDecryptIndexName = @"MobileDecrypt.index.json";
static NSString * const kODLRRecoveryIndexName = @"MobileRecovery.index.json";
static NSString * const kODLRRecoveryReportName = @"MobileRecovery.report.json";
static NSString * const kODLRRecoveryStatusName = @"MobileRecovery.status.json";

static NSArray *ODLROpNames(void) {
    static NSArray *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = [@[@"MOVE",@"LOADK",@"LOADKX",@"LOADBOOL",@"LOADNIL",@"GETUPVAL",@"GETTABUP",@"GETTABLE",
                   @"SETTABUP",@"SETUPVAL",@"SETTABLE",@"NEWTABLE",@"SELF",@"ADD",@"SUB",@"MUL",@"MOD",@"POW",
                   @"DIV",@"IDIV",@"BAND",@"BOR",@"BXOR",@"SHL",@"SHR",@"UNM",@"BNOT",@"NOT",@"LEN",@"CONCAT",
                   @"JMP",@"EQ",@"LT",@"LE",@"TEST",@"TESTSET",@"CALL",@"TAILCALL",@"RETURN",@"FORLOOP",@"FORPREP",
                   @"TFORCALL",@"TFORLOOP",@"SETLIST",@"CLOSURE",@"VARARG",@"EXTRAARG"] retain];
    });
    return names;
}

static NSString *ODLRSHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static BOOL ODLRFileMatchesSHA256(NSString *path, NSString *expected) {
    if (!path.length || expected.length != 64) return NO;
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data.length) return NO;
    NSString *actual = ODLRSHA256(data).lowercaseString;
    return [actual isEqualToString:expected.lowercaseString];
}

static BOOL ODLRHasLua53Signature(NSData *data) {
    if (data.length < 5) return NO;
    const uint8_t *p = data.bytes;
    return p[0] == 0x1B && p[1] == 'L' && p[2] == 'u' && p[3] == 'a' && p[4] == 0x53;
}

static NSInteger ODLRFindLua53Offset(NSData *data) {
    if (data.length < 5) return NSNotFound;
    const uint8_t *p = data.bytes;
    NSUInteger max = MIN((NSUInteger)4096, data.length - 5);
    for (NSUInteger i = 0; i <= max; i++) {
        if (p[i] == 0x1B && p[i+1] == 'L' && p[i+2] == 'u' && p[i+3] == 'a' && p[i+4] == 0x53) return (NSInteger)i;
    }
    return NSNotFound;
}

static NSData *ODLRDecodeRaw(NSData *raw, NSString **kindOut) {
    if (kindOut) *kindOut = @"none";
    if (!raw.length) return nil;
    if (ODLRHasLua53Signature(raw)) {
        if (kindOut) *kindOut = @"plain-luac53";
        return raw;
    }
    const uint8_t *p = raw.bytes;
    if (raw.length > 4 && memcmp(p, "ENCM", 4) == 0) {
        NSMutableData *out = [NSMutableData dataWithLength:raw.length - 4];
        uint8_t *dst = out.mutableBytes;
        for (NSUInteger i = 0; i < out.length; i++) dst[i] = p[i + 4] ^ ODLR_ENCM_XOR_KEY;
        if (ODLRHasLua53Signature(out)) {
            if (kindOut) *kindOut = @"encm-xor4d";
            return out;
        }
        if (kindOut) *kindOut = @"encm-unknown";
        return nil;
    }
    NSInteger off = ODLRFindLua53Offset(raw);
    if (off > 0 && (NSUInteger)off < raw.length) {
        if (kindOut) *kindOut = [NSString stringWithFormat:@"wrapped-luac53+%ld", (long)off];
        return [raw subdataWithRange:NSMakeRange((NSUInteger)off, raw.length - (NSUInteger)off)];
    }
    return nil;
}

static NSString *ODLRSafeName(NSString *text, NSUInteger limit) {
    if (!text.length) return @"unnamed";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN(text.length, limit)];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@+"];
    for (NSUInteger i = 0; i < text.length && out.length < limit; i++) {
        unichar c = [text characterAtIndex:i];
        if ([ok characterIsMember:c]) [out appendFormat:@"%C", c];
        else [out appendString:@"_"];
    }
    return out.length ? out : @"unnamed";
}

static NSDictionary *ODLRReadJSONDictionary(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static BOOL ODLRWriteJSON(id obj, NSString *path) {
    if (!obj || !path.length) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:nil];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static NSArray *ODLRFilesInDirectory(NSString *dir) {
    if (!dir.length) return @[];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = [fm contentsOfDirectoryAtPath:dir error:nil];
    if (!names.count) return @[];
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *name in names) {
        NSString *path = [dir stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && !isDir) [out addObject:path];
    }
    return out;
}

static NSString *ODLRCanonicalAssetName(NSString *path) {
    NSString *name = path.lastPathComponent ?: @"unnamed";
    NSRegularExpression *hashRe = [NSRegularExpression regularExpressionWithPattern:@"_[0-9a-fA-F]{12,64}\\.(luac|lua|bin)$" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *m = [hashRe firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
    if (m) {
        NSString *ext = [name.pathExtension lowercaseString];
        name = [name substringToIndex:m.range.location];
        if ([ext isEqualToString:@"luac"] && ![[name lowercaseString] hasSuffix:@".lua"]) name = [name stringByAppendingString:@".lua"];
        return name;
    }
    NSString *lower = name.lowercaseString;
    if ([lower hasSuffix:@".luac"]) name = [name stringByDeletingPathExtension];
    return name;
}

static void ODLRGroupAndFragment(NSString *assetName, NSString **groupOut, NSInteger *fragmentOut) {
    NSString *text = [assetName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSString *leaf = text.lastPathComponent ?: text;
    NSString *base = leaf;
    NSString *lower = base.lowercaseString;
    for (NSString *ext in @[@".luac", @".lua", @".bytes", @".txt", @".bin"]) {
        if ([lower hasSuffix:ext]) { base = [base substringToIndex:base.length - ext.length]; break; }
    }
    NSString *group = base;
    NSInteger idx = 0;
    NSRegularExpression *tabRe = [NSRegularExpression regularExpressionWithPattern:@"^(TAB_[A-Za-z0-9][A-Za-z0-9_-]*?)(?:[_-](\\d{1,4}))?$" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *tm = [tabRe firstMatchInString:base options:0 range:NSMakeRange(0, base.length)];
    if (tm) {
        group = [base substringWithRange:[tm rangeAtIndex:1]];
        if ([tm rangeAtIndex:2].location != NSNotFound) idx = [[base substringWithRange:[tm rangeAtIndex:2]] integerValue];
    } else {
        NSRegularExpression *generic = [NSRegularExpression regularExpressionWithPattern:@"^(.*?)[_-](\\d{1,3})$" options:0 error:nil];
        NSTextCheckingResult *gm = [generic firstMatchInString:base options:0 range:NSMakeRange(0, base.length)];
        if (gm) {
            NSString *prefix = [base substringWithRange:[gm rangeAtIndex:1]];
            NSString *pl = prefix.lowercaseString;
            if ([pl containsString:@"data"] || [pl containsString:@"config"] || [pl containsString:@"table"] || [pl containsString:@"list"]) {
                group = prefix;
                idx = [[base substringWithRange:[gm rangeAtIndex:2]] integerValue];
            }
        }
    }
    if (groupOut) *groupOut = group ?: @"unnamed";
    if (fragmentOut) *fragmentOut = idx;
}

@interface ODLRLuaTable : NSObject
@property(nonatomic, retain) NSMutableDictionary *dict;
@property(nonatomic, retain) NSMutableArray *order;
- (void)setKey:(id)key value:(id)value;
- (id)getKey:(id)key;
@end

@implementation ODLRLuaTable
- (instancetype)init { if ((self = [super init])) { _dict = [[NSMutableDictionary alloc] init]; _order = [[NSMutableArray alloc] init]; } return self; }
- (void)dealloc { [_dict release]; [_order release]; [super dealloc]; }
- (void)setKey:(id)key value:(id)value {
    if (!key || key == [NSNull null]) return;
    if (![_dict objectForKey:key]) [_order addObject:key];
    if (!value || value == [NSNull null]) [_dict removeObjectForKey:key];
    else [_dict setObject:value forKey:key];
}
- (id)getKey:(id)key { return key ? [_dict objectForKey:key] : nil; }
@end

static ODLRLuaTable *ODLRCloneTable(ODLRLuaTable *src, NSMapTable *memo) {
    if (![src isKindOfClass:[ODLRLuaTable class]]) return nil;
    ODLRLuaTable *cached = [memo objectForKey:src];
    if (cached) return cached;
    ODLRLuaTable *out = [[[ODLRLuaTable alloc] init] autorelease];
    [memo setObject:out forKey:src];
    for (id key in src.order) {
        id value = [src.dict objectForKey:key];
        if (!value) continue;
        id ck = [key isKindOfClass:[ODLRLuaTable class]] ? ODLRCloneTable(key, memo) : key;
        id cv = [value isKindOfClass:[ODLRLuaTable class]] ? ODLRCloneTable(value, memo) : value;
        [out setKey:ck value:cv];
    }
    return out;
}

static ODLRLuaTable *ODLRDeepClone(ODLRLuaTable *src) {
    NSMapTable *memo = [NSMapTable strongToStrongObjectsMapTable];
    return ODLRCloneTable(src, memo);
}

static NSArray *ODLRAsArray(ODLRLuaTable *table) {
    if (![table isKindOfClass:[ODLRLuaTable class]]) return nil;
    if (!table.dict.count) return @[];
    NSUInteger max = 0;
    for (id key in table.dict) {
        if (![key isKindOfClass:[NSNumber class]]) return nil;
        NSInteger v = [key integerValue];
        if (v < 1) return nil;
        if ((NSUInteger)v > max) max = (NSUInteger)v;
    }
    if (max != table.dict.count) return nil;
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:max];
    for (NSUInteger i = 1; i <= max; i++) {
        id v = [table.dict objectForKey:@(i)];
        if (!v) return nil;
        [arr addObject:v];
    }
    return arr;
}

static id ODLRJSONValueInternal(id value, NSMutableSet *seen) {
    if (!value || value == [NSNull null]) return [NSNull null];
    if (![value isKindOfClass:[ODLRLuaTable class]]) {
        if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) return value;
        return [value description] ?: @"";
    }
    NSValue *ptr = [NSValue valueWithPointer:value];
    if ([seen containsObject:ptr]) return @"<cycle>";
    [seen addObject:ptr];
    ODLRLuaTable *t = value;
    NSArray *array = ODLRAsArray(t);
    id out;
    if (array) {
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:array.count];
        for (id x in array) [a addObject:ODLRJSONValueInternal(x, seen) ?: [NSNull null]];
        out = a;
    } else {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (id key in t.order) {
            id v = [t.dict objectForKey:key];
            if (!v) continue;
            NSString *ks = [key isKindOfClass:[NSString class]] ? key : [key description];
            if (!ks.length) continue;
            d[ks] = ODLRJSONValueInternal(v, seen) ?: [NSNull null];
        }
        out = d;
    }
    [seen removeObject:ptr];
    return out;
}

static id ODLRJSONValue(id value) { return ODLRJSONValueInternal(value, [NSMutableSet set]); }

static NSString *ODLRNormField(NSString *name) {
    if (![name isKindOfClass:[NSString class]]) return [name description] ?: @"field";
    if (name.length > 2 && ([name hasPrefix:@"s_"] || [name hasPrefix:@"u_"])) return [name substringFromIndex:2];
    return name;
}

typedef struct {
    const uint8_t *bytes;
    NSUInteger length;
    NSUInteger pos;
    BOOL little;
    uint8_t intSize;
    uint8_t sizeTSize;
    uint8_t instructionSize;
    uint8_t integerSize;
    uint8_t numberSize;
    BOOL ok;
    NSString *error;
} ODLRParser;

static void ODLRParserFail(ODLRParser *p, NSString *error) {
    if (!p || !p->ok) return;
    p->ok = NO;
    p->error = [error copy];
}

static BOOL ODLRNeed(ODLRParser *p, NSUInteger n) {
    if (!p->ok || p->pos > p->length || n > p->length - p->pos) { ODLRParserFail(p, @"truncated"); return NO; }
    return YES;
}

static NSData *ODLRTake(ODLRParser *p, NSUInteger n) {
    if (!ODLRNeed(p, n)) return nil;
    NSData *d = [NSData dataWithBytes:p->bytes + p->pos length:n]; p->pos += n; return d;
}

static uint8_t ODLRU8(ODLRParser *p) { if (!ODLRNeed(p,1)) return 0; return p->bytes[p->pos++]; }

static uint64_t ODLRUInt(ODLRParser *p, NSUInteger n) {
    if (!ODLRNeed(p,n) || n == 0 || n > 8) return 0;
    uint64_t v = 0;
    if (p->little) { for (NSUInteger i=0;i<n;i++) v |= ((uint64_t)p->bytes[p->pos+i]) << (8*i); }
    else { for (NSUInteger i=0;i<n;i++) v = (v<<8) | p->bytes[p->pos+i]; }
    p->pos += n; return v;
}

static int64_t ODLRSInt(ODLRParser *p, NSUInteger n) {
    uint64_t v = ODLRUInt(p,n); if (!p->ok) return 0;
    if (n == 1) return (int8_t)v; if (n == 2) return (int16_t)v; if (n == 4) return (int32_t)v; if (n == 8) return (int64_t)v;
    if (n < 8 && (v & ((uint64_t)1 << (n*8-1)))) v |= ~((((uint64_t)1) << (n*8))-1);
    return (int64_t)v;
}

static NSInteger ODLRCount(ODLRParser *p) {
    int64_t n = ODLRSInt(p,p->intSize);
    if (!p->ok || n < 0 || n > ODLR_MAX_COUNT) { ODLRParserFail(p, @"invalid count"); return 0; }
    return (NSInteger)n;
}

static NSString *ODLRString(ODLRParser *p) {
    uint64_t n = ODLRU8(p); if (!p->ok || n == 0) return nil;
    if (n == 0xFF) n = ODLRUInt(p,p->sizeTSize);
    if (!p->ok || n < 1 || n - 1 > NSUIntegerMax || !ODLRNeed(p,(NSUInteger)n-1)) { ODLRParserFail(p,@"invalid string"); return nil; }
    NSUInteger len = (NSUInteger)n - 1;
    NSString *s = [[[NSString alloc] initWithBytes:p->bytes+p->pos length:len encoding:NSUTF8StringEncoding] autorelease];
    if (!s) s = [[[NSString alloc] initWithBytes:p->bytes+p->pos length:len encoding:NSISOLatin1StringEncoding] autorelease];
    p->pos += len; return s;
}

static double ODLRReadDouble(ODLRParser *p) {
    if (!ODLRNeed(p,8)) return 0;
    uint8_t tmp[8];
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    BOOL hostLittle = YES;
#else
    BOOL hostLittle = NO;
#endif
    if (p->little == hostLittle) memcpy(tmp,p->bytes+p->pos,8); else for(NSUInteger i=0;i<8;i++) tmp[i]=p->bytes[p->pos+7-i];
    p->pos += 8; double d=0; memcpy(&d,tmp,8); return d;
}

static NSDictionary *ODLRParseFunction(ODLRParser *p, NSUInteger depth) {
    if (depth > ODLR_MAX_DEPTH) { ODLRParserFail(p,@"prototype depth exceeded"); return nil; }
    (void)ODLRString(p);
    (void)ODLRSInt(p,p->intSize); (void)ODLRSInt(p,p->intSize);
    (void)ODLRU8(p); (void)ODLRU8(p); uint8_t maxStack=ODLRU8(p);
    NSInteger codeCount=ODLRCount(p); if(!p->ok) return nil;
    NSMutableArray *code=[NSMutableArray arrayWithCapacity:(NSUInteger)codeCount];
    for(NSInteger i=0;i<codeCount;i++) [code addObject:@(ODLRUInt(p,p->instructionSize))];
    NSInteger kCount=ODLRCount(p); NSMutableArray *K=[NSMutableArray arrayWithCapacity:(NSUInteger)kCount];
    for(NSInteger i=0;i<kCount && p->ok;i++) {
        uint8_t tag=ODLRU8(p); id v=[NSNull null];
        if(tag==0) v=[NSNull null];
        else if(tag==1) v=@(ODLRU8(p)!=0);
        else if(tag==3) v=@(ODLRReadDouble(p));
        else if(tag==19) v=@(ODLRSInt(p,p->integerSize));
        else if(tag==4 || tag==20) v=ODLRString(p) ?: @"";
        else { ODLRParserFail(p,[NSString stringWithFormat:@"unknown constant tag %u",tag]); break; }
        [K addObject:v ?: [NSNull null]];
    }
    NSInteger upCount=ODLRCount(p); for(NSInteger i=0;i<upCount && p->ok;i++){(void)ODLRU8(p);(void)ODLRU8(p);}
    NSInteger protoCount=ODLRCount(p); for(NSInteger i=0;i<protoCount && p->ok;i++) (void)ODLRParseFunction(p,depth+1);
    NSInteger lineCount=ODLRCount(p); for(NSInteger i=0;i<lineCount && p->ok;i++) (void)ODLRSInt(p,p->intSize);
    NSInteger locCount=ODLRCount(p); for(NSInteger i=0;i<locCount && p->ok;i++){(void)ODLRString(p);(void)ODLRSInt(p,p->intSize);(void)ODLRSInt(p,p->intSize);}
    NSInteger upNameCount=ODLRCount(p); for(NSInteger i=0;i<upNameCount && p->ok;i++) (void)ODLRString(p);
    if (!p->ok) return nil;
    return @{ @"code":code, @"K":K, @"maxstack":@(maxStack) };
}

static NSDictionary *ODLRParseChunk(NSData *data, NSString **errorOut) {
    if(errorOut)*errorOut=nil;
    if(data.length < 32 || !ODLRHasLua53Signature(data)){if(errorOut)*errorOut=@"missing Lua 5.3 signature";return nil;}
    ODLRParser p={0};p.bytes=data.bytes;p.length=data.length;p.pos=0;p.ok=YES;p.little=YES;
    NSData *sig=ODLRTake(&p,4); if(![sig isEqualToData:[NSData dataWithBytes:"\x1bLua" length:4]]){if(errorOut)*errorOut=@"bad signature";return nil;}
    uint8_t ver=ODLRU8(&p),fmt=ODLRU8(&p); if(ver!=0x53){if(errorOut)*errorOut=@"unsupported Lua version";return nil;}
    NSData *luac=ODLRTake(&p,6); static const uint8_t expected[6]={0x19,0x93,0x0d,0x0a,0x1a,0x0a};
    if(luac.length!=6 || memcmp(luac.bytes,expected,6)!=0){if(errorOut)*errorOut=@"LUAC_DATA mismatch";return nil;}
    p.intSize=ODLRU8(&p);p.sizeTSize=ODLRU8(&p);p.instructionSize=ODLRU8(&p);p.integerSize=ODLRU8(&p);p.numberSize=ODLRU8(&p);
    if(!p.ok || !p.intSize || !p.sizeTSize || p.instructionSize!=4 || !p.integerSize || p.numberSize!=8 || p.integerSize>8){if(errorOut)*errorOut=@"invalid header sizes";return nil;}
    NSUInteger intPos=p.pos; uint64_t le=0,be=0; if(!ODLRNeed(&p,p.integerSize)){if(errorOut)*errorOut=@"truncated LUAC_INT";return nil;}
    for(NSUInteger i=0;i<p.integerSize;i++){le|=((uint64_t)p.bytes[intPos+i])<<(8*i);be=(be<<8)|p.bytes[intPos+i];}
    if(le==0x5678)p.little=YES;else if(be==0x5678)p.little=NO;else{if(errorOut)*errorOut=@"LUAC_INT mismatch";return nil;}
    (void)ODLRUInt(&p,p.integerSize); double num=ODLRReadDouble(&p); if(fabs(num-370.5)>0.000001){if(errorOut)*errorOut=@"LUAC_NUM mismatch";return nil;}
    uint8_t rootUp=ODLRU8(&p); (void)rootUp;
    NSDictionary *root=ODLRParseFunction(&p,0);
    if(!root || !p.ok){if(errorOut)*errorOut=[p.error autorelease]?:@"parse failed";else [p.error release];return nil;}
    [p.error release];
    return @{ @"root":root, @"format":@(fmt), @"bytes":@(data.length) };
}

static void ODLRFields(uint32_t i, int *op, int *A, int *B, int *C, int *Bx, int *Ax, int *sBx) {
    if(op)*op=(int)(i&0x3F); if(A)*A=(int)((i>>6)&0xFF); if(C)*C=(int)((i>>14)&0x1FF); if(B)*B=(int)((i>>23)&0x1FF);
    int bx=(int)((i>>14)&0x3FFFF); if(Bx)*Bx=bx; if(Ax)*Ax=(int)((i>>6)&0x3FFFFFF); if(sBx)*sBx=bx-131071;
}

static id ODLRReg(NSMutableArray *R, NSInteger idx) { if(idx<0 || (NSUInteger)idx>=R.count)return [NSNull null]; id v=R[(NSUInteger)idx]; return v?:[NSNull null]; }
static void ODLRSetReg(NSMutableArray *R, NSInteger idx, id value) { if(idx<0)return; while((NSUInteger)idx>=R.count)[R addObject:[NSNull null]]; R[(NSUInteger)idx]=value?:[NSNull null]; }
static BOOL ODLRTruthy(id v){return v && v!=[NSNull null] && !([v isKindOfClass:[NSNumber class]] && strcmp([v objCType],@encode(BOOL))==0 && ![v boolValue]);}

static NSDictionary *ODLRExecute(NSDictionary *root, ODLRLuaTable *env, NSArray **returnsOut, NSString **errorOut) {
    if(returnsOut)*returnsOut=@[]; if(errorOut)*errorOut=nil;
    NSArray *K=root[@"K"],*code=root[@"code"]; NSUInteger regCount=MAX((NSUInteger)64,[root[@"maxstack"] unsignedIntegerValue]+32);
    NSMutableArray *R=[NSMutableArray arrayWithCapacity:regCount];for(NSUInteger i=0;i<regCount;i++)[R addObject:[NSNull null]];
    NSMutableDictionary *hist=[NSMutableDictionary dictionary]; NSInteger pc=0; NSUInteger steps=0; NSArray *returns=@[];
    while(pc<(NSInteger)code.count){
        if(steps++>code.count*ODLR_MAX_STATIC_STEPS_FACTOR){if(errorOut)*errorOut=@"execution runaway";return nil;}
        uint32_t inst=[code[(NSUInteger)pc] unsignedIntValue];int op,A,B,C,Bx,Ax,sBx;ODLRFields(inst,&op,&A,&B,&C,&Bx,&Ax,&sBx);
        NSArray *names=ODLROpNames(); if(op<0 || (NSUInteger)op>=names.count){if(errorOut)*errorOut=[NSString stringWithFormat:@"opcode out of range %d @pc=%ld",op,(long)pc];return nil;}
        NSString *name=names[(NSUInteger)op];hist[name]=@([hist[name] unsignedIntegerValue]+1);NSInteger npc=pc+1;
        id (^rk)(int)=^id(int x){if(x&0x100){NSUInteger ki=(NSUInteger)(x&0xFF);return ki<K.count?K[ki]:[NSNull null];}return ODLRReg(R,x);};
        if([name isEqualToString:@"MOVE"]) ODLRSetReg(R,A,ODLRReg(R,B));
        else if([name isEqualToString:@"LOADK"]){if(Bx<0||(NSUInteger)Bx>=K.count){if(errorOut)*errorOut=@"LOADK constant OOB";return nil;}ODLRSetReg(R,A,K[(NSUInteger)Bx]);}
        else if([name isEqualToString:@"LOADKX"]){if(npc>=(NSInteger)code.count){if(errorOut)*errorOut=@"LOADKX missing EXTRAARG";return nil;}int eop,eA,eB,eC,eBx,eAx,esBx;ODLRFields([code[(NSUInteger)npc] unsignedIntValue],&eop,&eA,&eB,&eC,&eBx,&eAx,&esBx);if(eop!=46||(NSUInteger)eAx>=K.count){if(errorOut)*errorOut=@"LOADKX invalid EXTRAARG";return nil;}ODLRSetReg(R,A,K[(NSUInteger)eAx]);npc++;}
        else if([name isEqualToString:@"LOADBOOL"]){ODLRSetReg(R,A,@(B!=0));if(C)npc++;}
        else if([name isEqualToString:@"LOADNIL"]){for(int x=A;x<=A+B;x++)ODLRSetReg(R,x,[NSNull null]);}
        else if([name isEqualToString:@"GETUPVAL"]){if(B!=0){if(errorOut)*errorOut=[NSString stringWithFormat:@"GETUPVAL unsupported upvalue %d @pc=%ld",B,(long)pc];return nil;}ODLRSetReg(R,A,env);}
        else if([name isEqualToString:@"GETTABUP"]){if(B!=0){if(errorOut)*errorOut=@"GETTABUP unsupported upvalue";return nil;}id key=rk(C);ODLRSetReg(R,A,[env getKey:key]?:[NSNull null]);}
        else if([name isEqualToString:@"GETTABLE"]){id base=ODLRReg(R,B),key=rk(C);if(![base isKindOfClass:[ODLRLuaTable class]]){if(errorOut)*errorOut=[NSString stringWithFormat:@"GETTABLE non-table @pc=%ld",(long)pc];return nil;}ODLRSetReg(R,A,[base getKey:key]?:[NSNull null]);}
        else if([name isEqualToString:@"SETTABUP"]){if(A!=0){if(errorOut)*errorOut=@"SETTABUP unsupported upvalue";return nil;}[env setKey:rk(B) value:rk(C)];}
        else if([name isEqualToString:@"SETUPVAL"]){if(B!=0){if(errorOut)*errorOut=@"SETUPVAL unsupported upvalue";return nil;}id v=ODLRReg(R,A);if(![v isKindOfClass:[ODLRLuaTable class]]){if(errorOut)*errorOut=@"SETUPVAL env non-table";return nil;}env=v;}
        else if([name isEqualToString:@"SETTABLE"]){id base=ODLRReg(R,A);if(![base isKindOfClass:[ODLRLuaTable class]]){if(errorOut)*errorOut=[NSString stringWithFormat:@"SETTABLE non-table @pc=%ld",(long)pc];return nil;}[base setKey:rk(B) value:rk(C)];}
        else if([name isEqualToString:@"NEWTABLE"]) ODLRSetReg(R,A,[[[ODLRLuaTable alloc]init]autorelease]);
        else if([name isEqualToString:@"JMP"]) npc=pc+1+sBx;
        else if([name isEqualToString:@"TEST"]){if(ODLRTruthy(ODLRReg(R,A))!=(C!=0))npc++;}
        else if([name isEqualToString:@"SETLIST"]){id base=ODLRReg(R,A);if(![base isKindOfClass:[ODLRLuaTable class]]){if(errorOut)*errorOut=[NSString stringWithFormat:@"SETLIST non-table @pc=%ld",(long)pc];return nil;}int n=B,c=C;if(c==0){if(npc>=(NSInteger)code.count){if(errorOut)*errorOut=@"SETLIST missing EXTRAARG";return nil;}int eop,eA,eB,eC,eBx,eAx,esBx;ODLRFields([code[(NSUInteger)npc] unsignedIntValue],&eop,&eA,&eB,&eC,&eBx,&eAx,&esBx);if(eop!=46){if(errorOut)*errorOut=@"SETLIST invalid EXTRAARG";return nil;}c=eAx;npc++;}if(n==0){if(errorOut)*errorOut=[NSString stringWithFormat:@"SETLIST B=0 unsupported @pc=%ld",(long)pc];return nil;}NSInteger start=(c-1)*ODLR_LFIELDS_PER_FLUSH;for(int j=1;j<=n;j++)[base setKey:@(start+j) value:ODLRReg(R,A+j)];}
        else if([name isEqualToString:@"RETURN"]){if(B==0){if(errorOut)*errorOut=[NSString stringWithFormat:@"RETURN B=0 unsupported @pc=%ld",(long)pc];return nil;}if(B>1){NSMutableArray *ret=[NSMutableArray array];for(int x=A;x<A+B-1;x++){id v=ODLRReg(R,x);[ret addObject:v?:[NSNull null]];}returns=ret;}break;}
        else if([name isEqualToString:@"EXTRAARG"]){}
        else {if(errorOut)*errorOut=[NSString stringWithFormat:@"non-static opcode %@ @pc=%ld",name,(long)pc];return nil;}
        pc=npc;
    }
    if(returnsOut)*returnsOut=returns;
    return @{ @"env":env, @"steps":@(steps), @"opcodes":hist };
}

static NSDictionary *ODLRSerializeTable(NSString *label, ODLRLuaTable *table) {
    NSArray *header=ODLRAsArray([table getKey:@(-1)]); NSMutableArray *malformed=[NSMutableArray array];
    if(header){BOOL valid=YES;for(id h in header)if(![h isKindOfClass:[NSString class]]){valid=NO;break;}if(valid){
        NSMutableArray *headerNorm=[NSMutableArray arrayWithCapacity:header.count];for(NSString*h in header)[headerNorm addObject:ODLRNormField(h)];
        NSMutableArray *rows=[NSMutableArray array];for(id key in table.order){if([key isEqual:@(-1)]||![table.dict objectForKey:key])continue;id rv=[table getKey:key];NSArray *arr=ODLRAsArray(rv);if(!arr){[malformed addObject:@{ @"id":[key description],@"reason":@"row-not-array" }];continue;}NSMutableDictionary *rec=[NSMutableDictionary dictionaryWithObject:key forKey:@"id"];NSUInteger width=MIN(arr.count,headerNorm.count);for(NSUInteger i=0;i<width;i++)rec[headerNorm[i]]=ODLRJSONValue(arr[i])?:[NSNull null];if(arr.count<headerNorm.count){for(NSUInteger i=arr.count;i<headerNorm.count;i++)rec[headerNorm[i]]=[NSNull null];[malformed addObject:@{ @"id":[key description],@"reason":@"short-row",@"row_width":@(arr.count),@"header_width":@(headerNorm.count) }];}else if(arr.count>headerNorm.count){NSMutableArray *extra=[NSMutableArray array];for(NSUInteger i=headerNorm.count;i<arr.count;i++)[extra addObject:ODLRJSONValue(arr[i])?:[NSNull null]];rec[@"_extra"]=extra;[malformed addObject:@{ @"id":[key description],@"reason":@"wide-row",@"row_width":@(arr.count),@"header_width":@(headerNorm.count) }];}[rows addObject:rec];}
        return @{ @"payload":@{ @"ListConfigModel":rows },@"mode":@"config-table",@"records":@(rows.count),@"malformed":malformed,@"label":label?:@"table" };
    }}
    id payload=ODLRJSONValue(table)?:@{};NSUInteger count=[payload respondsToSelector:@selector(count)]?[payload count]:1;
    return @{ @"payload":payload,@"mode":@"generic-table",@"records":@(count),@"malformed":@[],@"label":label?:@"table" };
}

static NSArray *ODLRExtractTables(ODLRLuaTable *env, NSArray *returns, NSString *group) {
    NSMutableArray *out=[NSMutableArray array];NSMutableSet *seen=[NSMutableSet set];
    for(id key in env.order){id value=[env getKey:key];if(![key isKindOfClass:[NSString class]]||![value isKindOfClass:[ODLRLuaTable class]]||![value dict].count)continue;NSValue*ptr=[NSValue valueWithPointer:value];if([seen containsObject:ptr])continue;[seen addObject:ptr];[out addObject:@{ @"label":key,@"table":value,@"origin":@"global" }];}
    NSUInteger idx=0;for(id value in returns){idx++;if(![value isKindOfClass:[ODLRLuaTable class]]||![value dict].count)continue;NSValue*ptr=[NSValue valueWithPointer:value];if([seen containsObject:ptr])continue;[seen addObject:ptr];[out addObject:@{ @"label":[NSString stringWithFormat:@"RETURN_%@_%lu",group?:@"group",(unsigned long)idx],@"table":value,@"origin":@"return" }];}
    return out;
}

static NSInteger ODLRTableSize(ODLRLuaTable *table, NSMutableSet *seen) {
    if(![table isKindOfClass:[ODLRLuaTable class]])return 1;NSValue*ptr=[NSValue valueWithPointer:table];if([seen containsObject:ptr])return 0;[seen addObject:ptr];NSInteger n=(NSInteger)table.dict.count;for(id v in table.dict.allValues)if([v isKindOfClass:[ODLRLuaTable class]])n+=ODLRTableSize(v,seen);return n;
}

static NSInteger ODLRResultScore(ODLRLuaTable *env, NSArray *returns) {
    NSInteger score=0;for(NSDictionary *item in ODLRExtractTables(env,returns,@"")){NSString*label=item[@"label"];ODLRLuaTable*table=item[@"table"];NSDictionary*ser=ODLRSerializeTable(label,table);NSInteger count=[ser[@"records"] integerValue];BOOL cfg=[ser[@"mode"] isEqualToString:@"config-table"];score+=count*(cfg?100:5);score+=ODLRTableSize(table,[NSMutableSet set]);score-=[ser[@"malformed"] count]*2;if([[label uppercaseString] hasPrefix:@"TAB_"])score+=100000;}return score;
}

@interface ODLRState : NSObject
@property(nonatomic, retain) ODLRLuaTable *env;
@property(nonatomic, retain) NSArray *returns;
@property(nonatomic, retain) NSMutableArray *fragments;
@property(nonatomic, assign) NSInteger score;
@property(nonatomic, copy) NSString *stopReason;
@end
@implementation ODLRState
- (void)dealloc{[_env release];[_returns release];[_fragments release];[_stopReason release];[super dealloc];}
@end

static NSDictionary *ODLRFileEntry(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];if(!data.length||!ODLRHasLua53Signature(data))return nil;
    NSString *asset=ODLRCanonicalAssetName(path);NSString *group=nil;NSInteger frag=0;ODLRGroupAndFragment(asset,&group,&frag);
    return @{ @"path":path,@"asset":asset?:@"unnamed",@"group":group?:@"unnamed",@"fragment":@(frag),@"sha":ODLRSHA256(data),@"bytes":@(data.length) };
}

static NSDictionary *ODLRRecoverGroup(NSString *group, NSArray *entries, NSString *completeDir, NSString *partialDir, BOOL *didWrite) {
    NSMutableDictionary *byIndex=[NSMutableDictionary dictionary];for(NSDictionary*e in entries){NSNumber*k=e[@"fragment"];NSMutableArray*a=byIndex[k];if(!a){a=[NSMutableArray array];byIndex[k]=a;}[a addObject:e];}
    NSArray *indices=[[byIndex allKeys] sortedArrayUsingSelector:@selector(compare:)];
    ODLRState *initial=[[[ODLRState alloc]init]autorelease];initial.env=[[[ODLRLuaTable alloc]init]autorelease];initial.returns=@[];initial.fragments=[NSMutableArray array];initial.score=0;NSArray *states=@[initial];BOOL fully=YES;NSString *stop=nil;
    for(NSNumber *idx in indices){NSArray *variants=[byIndex[idx] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary*a,NSDictionary*b){return [b[@"bytes"] compare:a[@"bytes"]];}];if(variants.count>ODLR_MAX_VARIANTS_PER_FRAGMENT)variants=[variants subarrayWithRange:NSMakeRange(0,ODLR_MAX_VARIANTS_PER_FRAGMENT)];NSMutableArray *next=[NSMutableArray array],*errors=[NSMutableArray array];
        for(ODLRState *state in states){for(NSDictionary *e in variants){ODLRLuaTable *env=ODLRDeepClone(state.env);NSData *data=[NSData dataWithContentsOfFile:e[@"path"] options:NSDataReadingMappedIfSafe error:nil];NSString *parseError=nil;NSDictionary *chunk=ODLRParseChunk(data,&parseError);if(!chunk){[errors addObject:@{ @"asset":e[@"asset"],@"sha":e[@"sha"],@"status":@"parse-failed",@"error":parseError?:@"parse failed" }];continue;}NSArray *ret=nil;NSString *execError=nil;NSDictionary *exec=ODLRExecute(chunk[@"root"],env,&ret,&execError);if(!exec){[errors addObject:@{ @"asset":e[@"asset"],@"sha":e[@"sha"],@"status":@"dynamic-or-failed",@"error":execError?:@"execute failed" }];continue;}ODLRState *s=[[[ODLRState alloc]init]autorelease];s.env=env;s.returns=ret?:state.returns;s.fragments=[NSMutableArray arrayWithArray:state.fragments];[s.fragments addObject:@{ @"asset":e[@"asset"],@"sha":e[@"sha"],@"fragment":idx,@"status":@"ok",@"execution":@{ @"steps":exec[@"steps"],@"opcodes":exec[@"opcodes"] } }];s.score=ODLRResultScore(s.env,s.returns);[next addObject:s];}}
        if(!next.count){fully=NO;stop=errors.count?errors[0][@"error"]:[NSString stringWithFormat:@"no usable variant at fragment %@",idx];ODLRState *best=[states sortedArrayUsingComparator:^NSComparisonResult(ODLRState*a,ODLRState*b){return a.score>b.score?NSOrderedAscending:(a.score<b.score?NSOrderedDescending:NSOrderedSame);}].firstObject;best.stopReason=stop;if(errors.count)[best.fragments addObject:errors[0]];states=@[best];break;}
        [next sortUsingComparator:^NSComparisonResult(ODLRState*a,ODLRState*b){return a.score>b.score?NSOrderedAscending:(a.score<b.score?NSOrderedDescending:NSOrderedSame);}];if(next.count>ODLR_BEAM_WIDTH)[next removeObjectsInRange:NSMakeRange(ODLR_BEAM_WIDTH,next.count-ODLR_BEAM_WIDTH)];states=next;
    }
    ODLRState *best=[states sortedArrayUsingComparator:^NSComparisonResult(ODLRState*a,ODLRState*b){return a.score>b.score?NSOrderedAscending:(a.score<b.score?NSOrderedDescending:NSOrderedSame);}].firstObject;NSArray *tables=ODLRExtractTables(best.env,best.returns,group);NSMutableArray *tableReport=[NSMutableArray array];BOOL malformedAny=NO;NSUInteger completeCount=0,partialCount=0,recordCount=0;
    for(NSDictionary *item in tables){NSString *label=item[@"label"];ODLRLuaTable *table=item[@"table"];NSDictionary *ser=ODLRSerializeTable(label,table);id payload=ser[@"payload"];if(!payload)continue;NSArray *malformed=ser[@"malformed"];BOOL partial=!fully||malformed.count>0;malformedAny|=malformed.count>0;NSString *stem=label;if([[stem uppercaseString] hasPrefix:@"TAB_"])stem=[stem substringFromIndex:4];if([stem hasPrefix:@"RETURN_"])stem=group;stem=ODLRSafeName(stem,120);NSString *dir=partial?partialDir:completeDir;NSString *out=[dir stringByAppendingPathComponent:[stem stringByAppendingPathExtension:@"json"]];if(ODLRWriteJSON(payload,out)){if(didWrite)*didWrite=YES;if(partial)partialCount++;else completeCount++;recordCount+=[ser[@"records"] unsignedIntegerValue];[tableReport addObject:@{ @"label":label,@"origin":item[@"origin"],@"mode":ser[@"mode"],@"records":ser[@"records"],@"partial":@(partial),@"malformed_rows":malformed,@"file":out }];}}
    NSString *status;if(tableReport.count)status=(!fully||malformedAny)?@"partial":@"complete";else{BOOL hasError=NO;for(NSDictionary*f in best.fragments)if(![f[@"status"] isEqualToString:@"ok"]){hasError=YES;break;}status=hasError?@"dynamic":@"static-no-table";}
    return @{ @"group":group,@"status":status,@"fully_processed":@(fully),@"stop_reason":stop?:[NSNull null],@"fragments":best.fragments?:@[],@"tables":tableReport,@"tables_complete":@(completeCount),@"tables_partial":@(partialCount),@"records":@(recordCount),@"variants_seen":@(entries.count) };
}

static NSDictionary *ODLRBuildSummary(NSDictionary *groups) {
    unsigned long long gc=0,gp=0,gd=0,gn=0,tc=0,tp=0,records=0,malformed=0;
    for(NSDictionary *r in groups.allValues){NSString*s=r[@"status"];if([s isEqualToString:@"complete"])gc++;else if([s isEqualToString:@"partial"])gp++;else if([s isEqualToString:@"dynamic"])gd++;else gn++;tc+=[r[@"tables_complete"] unsignedLongLongValue];tp+=[r[@"tables_partial"] unsignedLongLongValue];records+=[r[@"records"] unsignedLongLongValue];for(NSDictionary*t in r[@"tables"])malformed+=[t[@"malformed_rows"] count];}
    return @{ @"groups_total":@(groups.count),@"groups_complete":@(gc),@"groups_partial":@(gp),@"groups_dynamic":@(gd),@"groups_static_no_table":@(gn),@"tables_complete":@(tc),@"tables_partial":@(tp),@"records_recovered":@(records),@"malformed_rows":@(malformed) };
}

NSDictionary *ODLRDecryptRawDirectory(NSString *rawDirectory, NSString *decodedDirectory, NSString *stateRoot, BOOL forceAll, ODLRShouldYieldBlock shouldYield, ODLRProgressBlock progress) {
    NSFileManager *fm=[NSFileManager defaultManager];[fm createDirectoryAtPath:decodedDirectory withIntermediateDirectories:YES attributes:nil error:nil];[fm createDirectoryAtPath:stateRoot withIntermediateDirectories:YES attributes:nil error:nil];NSString *indexPath=[stateRoot stringByAppendingPathComponent:kODLRDecryptIndexName];NSDictionary *old=ODLRReadJSONDictionary(indexPath);NSMutableDictionary *processed=[NSMutableDictionary dictionaryWithDictionary:[old[@"processed"] isKindOfClass:[NSDictionary class]]?old[@"processed"]:@{}];NSArray *files=ODLRFilesInDirectory(rawDirectory);unsigned long long seen=0,queued=0,decoded=0,skipped=0,failed=0;BOOL yielded=NO;
    for(NSString *path in files){@autoreleasepool{if(shouldYield&&shouldYield()){yielded=YES;break;}seen++;NSData *raw=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];if(!raw.length){failed++;continue;}NSString*sha=ODLRSHA256(raw);if(!forceAll&&processed[sha]){skipped++;continue;}queued++;NSString *kind=nil;NSData *out=ODLRDecodeRaw(raw,&kind);if(out.length&&ODLRHasLua53Signature(out)){NSString *asset=ODLRCanonicalAssetName(path);NSString *dh=ODLRSHA256(out).lowercaseString;NSString *file=[NSString stringWithFormat:@"%@_%@.luac",ODLRSafeName(asset,120),dh];NSString *dest=[decodedDirectory stringByAppendingPathComponent:file];if(!ODLRFileMatchesSHA256(dest,dh))[out writeToFile:dest atomically:YES];decoded++;processed[sha]=@{ @"decoded_sha":dh,@"kind":kind?:@"lua",@"source":path,@"updated_at":@([[NSDate date] timeIntervalSince1970]) };}else{failed++;processed[sha]=@{ @"kind":kind?:@"not-lua",@"source":path,@"updated_at":@([[NSDate date] timeIntervalSince1970]) };}if(progress)progress(@{ @"stage":@"decrypt",@"seen":@(seen),@"total":@(files.count),@"decoded":@(decoded),@"failed":@(failed) });}}
    ODLRWriteJSON(@{ @"version":ODLR_VERSION,@"processed":processed,@"updated_at":@([[NSDate date] timeIntervalSince1970]) },indexPath);
    return @{ @"files_seen":@(seen),@"queued":@(queued),@"decoded":@(decoded),@"skipped":@(skipped),@"failed":@(failed),@"yielded_for_capture":@(yielded),@"index_entries":@(processed.count) };
}

NSDictionary *ODLRRecoverDecodedDirectory(NSString *decodedDirectory, NSString *outputRoot, BOOL forceAll, ODLRShouldYieldBlock shouldYield, ODLRProgressBlock progress) {
    NSFileManager *fm=[NSFileManager defaultManager];NSString *completeDir=[outputRoot stringByAppendingPathComponent:@"recovered_json"],*partialDir=[outputRoot stringByAppendingPathComponent:@"recovered_partial"],*dynamicDir=[outputRoot stringByAppendingPathComponent:@"dynamic_lua"];for(NSString*d in @[completeDir,partialDir,dynamicDir])[fm createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableDictionary *groups=[NSMutableDictionary dictionary];NSMutableDictionary *groupSHAs=[NSMutableDictionary dictionary];for(NSString *path in ODLRFilesInDirectory(decodedDirectory)){NSDictionary*e=ODLRFileEntry(path);if(!e)continue;NSString*g=e[@"group"];NSMutableArray*a=groups[g];if(!a){a=[NSMutableArray array];groups[g]=a;}[a addObject:e];NSMutableArray*hs=groupSHAs[g];if(!hs){hs=[NSMutableArray array];groupSHAs[g]=hs;}[hs addObject:e[@"sha"]];}
    NSString *indexPath=[outputRoot stringByAppendingPathComponent:kODLRRecoveryIndexName];NSDictionary *oldIndex=ODLRReadJSONDictionary(indexPath);NSMutableDictionary *processed=[NSMutableDictionary dictionaryWithDictionary:[oldIndex[@"groups"] isKindOfClass:[NSDictionary class]]?oldIndex[@"groups"]:@{}];NSString *reportPath=[outputRoot stringByAppendingPathComponent:kODLRRecoveryReportName];NSDictionary *oldReport=ODLRReadJSONDictionary(reportPath);NSMutableDictionary *reportGroups=[NSMutableDictionary dictionaryWithDictionary:[oldReport[@"groups"] isKindOfClass:[NSDictionary class]]?oldReport[@"groups"]:@{}];
    NSArray *sorted=[[groups allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];unsigned long long attempted=0,changed=0,written=0;BOOL yielded=NO;
    for(NSString *group in sorted){@autoreleasepool{if(shouldYield&&shouldYield()){yielded=YES;break;}NSArray *shas=[groupSHAs[group] sortedArrayUsingSelector:@selector(compare:)];NSString *signature=ODLRSHA256([[shas componentsJoinedByString:@"|"] dataUsingEncoding:NSUTF8StringEncoding]);if(!forceAll&&[processed[group][@"signature"] isEqualToString:signature])continue;attempted++;BOOL didWrite=NO;NSDictionary *result=ODLRRecoverGroup(group,groups[group],completeDir,partialDir,&didWrite);reportGroups[group]=result;processed[group]=@{ @"signature":signature,@"status":result[@"status"],@"updated_at":@([[NSDate date] timeIntervalSince1970]) };changed++;if(didWrite)written++;if(progress)progress(@{ @"stage":@"recover",@"group":group,@"attempted":@(attempted),@"groups_total":@(sorted.count),@"status":result[@"status"] });}}
    NSDictionary *summary=ODLRBuildSummary(reportGroups);ODLRWriteJSON(@{ @"version":ODLR_VERSION,@"groups":processed,@"updated_at":@([[NSDate date] timeIntervalSince1970]) },indexPath);ODLRWriteJSON(@{ @"version":ODLR_VERSION,@"summary":summary,@"groups":reportGroups,@"updated_at":@([[NSDate date] timeIntervalSince1970]) },reportPath);NSMutableDictionary *status=[NSMutableDictionary dictionaryWithDictionary:summary];status[@"version"]=ODLR_VERSION;status[@"attempted_this_run"]=@(attempted);status[@"groups_changed_this_run"]=@(changed);status[@"groups_written_this_run"]=@(written);status[@"yielded_for_capture"]=@(yielded);status[@"updated_at"]=@([[NSDate date] timeIntervalSince1970]);ODLRWriteJSON(status,[outputRoot stringByAppendingPathComponent:kODLRRecoveryStatusName]);return status;
}

NSDictionary *ODLRQueueSnapshot(NSString *rawDirectory, NSString *decodedDirectory, NSString *outputRoot) {
    NSUInteger raw=ODLRFilesInDirectory(rawDirectory).count,decoded=ODLRFilesInDirectory(decodedDirectory).count;NSDictionary *didx=ODLRReadJSONDictionary([outputRoot stringByAppendingPathComponent:kODLRDecryptIndexName]);NSUInteger dprocessed=[didx[@"processed"] count];NSDictionary *ridx=ODLRReadJSONDictionary([outputRoot stringByAppendingPathComponent:kODLRRecoveryIndexName]);NSUInteger rgroups=[ridx[@"groups"] count];NSDictionary *status=ODLRReadJSONDictionary([outputRoot stringByAppendingPathComponent:kODLRRecoveryStatusName])?:@{};NSString*complete=[outputRoot stringByAppendingPathComponent:@"recovered_json"],*partial=[outputRoot stringByAppendingPathComponent:@"recovered_partial"];
    return @{ @"raw_files":@(raw),@"decoded_files":@(decoded),@"decrypt_index_entries":@(dprocessed),@"recovery_index_groups":@(rgroups),@"pending_decrypt_estimate":@(raw>dprocessed?raw-dprocessed:0),@"complete_json_files":@(ODLRFilesInDirectory(complete).count),@"partial_json_files":@(ODLRFilesInDirectory(partial).count),@"recovery_status":status };
}

void ODLRResetRecoveryIndex(NSString *outputRoot){NSFileManager*fm=[NSFileManager defaultManager];for(NSString*n in @[kODLRRecoveryIndexName,kODLRRecoveryReportName,kODLRRecoveryStatusName])[fm removeItemAtPath:[outputRoot stringByAppendingPathComponent:n] error:nil];}
void ODLRResetDecryptIndex(NSString *stateRoot){[[NSFileManager defaultManager] removeItemAtPath:[stateRoot stringByAppendingPathComponent:kODLRDecryptIndexName] error:nil];}
