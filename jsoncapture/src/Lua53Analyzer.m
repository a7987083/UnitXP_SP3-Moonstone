#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <string.h>

#import "Lua53Analyzer.h"

#define JC4_ANALYZER_VERSION @"Lua53Analyzer v0.4"
#define JC4_MAX_SCAN_OFFSET 32
#define JC4_MAX_DEPTH 128
#define JC4_MAX_COUNT 100000000ULL
#define JC4_MAX_OPCODE 46

typedef struct {
    const uint8_t *data;
    NSUInteger length;
    NSUInteger pos;
    BOOL ok;
    BOOL littleEndian;
    BOOL officialLayout;
    BOOL compatibleLayout;
    uint8_t version;
    uint8_t format;
    uint8_t intSize;
    uint8_t sizeTSize;
    uint8_t instructionSize;
    uint8_t integerSize;
    uint8_t numberSize;
    NSUInteger headerSize;
    uint8_t rootUpvalues;
    uint64_t functions;
    uint64_t instructions;
    uint64_t constants;
    uint64_t stringsSeen;
    uint64_t opcodeOutOfRange;
    uint8_t maxOpcode;
    uint64_t opcodeHistogram[64];
    NSString *error;
    NSUInteger errorOffset;
    NSMutableArray *strings;
    NSMutableSet *stringSet;
} JC4Parser;

static pthread_mutex_t gJC4SeenLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableSet *gJC4SeenCleanHashes;

static NSString *JC4SHA256(NSData *data) {
    if (!data.length) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static NSString *JC4SafeName(NSString *text) {
    if (!text.length) return @"unnamed";
    NSMutableString *out = [NSMutableString stringWithCapacity:MIN(text.length, 140)];
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.@"];
    for (NSUInteger i = 0; i < text.length && out.length < 140; i++) {
        unichar c = [text characterAtIndex:i];
        if ([ok characterIsMember:c]) [out appendFormat:@"%C", c];
        else [out appendString:@"_"];
    }
    return out.length ? out : @"unnamed";
}

static BOOL JC4IsLuaSigAt(const uint8_t *p, NSUInteger length, NSUInteger off) {
    return off + 5 <= length && p[off] == 0x1B && p[off + 1] == 'L' && p[off + 2] == 'u' && p[off + 3] == 'a' && p[off + 4] == 0x53;
}

NSInteger JC4FindLua53SignatureOffset(NSData *data) {
    if (!data.length || data.length < 5) return NSNotFound;
    const uint8_t *p = data.bytes;
    NSUInteger limit = MIN((NSUInteger)JC4_MAX_SCAN_OFFSET, data.length - 5);
    for (NSUInteger i = 0; i <= limit; i++) {
        if (JC4IsLuaSigAt(p, data.length, i)) return (NSInteger)i;
    }
    return NSNotFound;
}

static void JC4Fail(JC4Parser *p, NSString *reason) {
    if (!p || !p->ok) return;
    p->ok = NO;
    p->errorOffset = p->pos;
    p->error = [reason copy];
}

static BOOL JC4Need(JC4Parser *p, NSUInteger n) {
    if (!p->ok) return NO;
    if (n > p->length || p->pos > p->length - n) {
        JC4Fail(p, @"truncated");
        return NO;
    }
    return YES;
}

static uint64_t JC4UIntAt(const uint8_t *data, NSUInteger pos, NSUInteger n, BOOL little) {
    uint64_t v = 0;
    if (little) {
        for (NSUInteger i = 0; i < n; i++) v |= ((uint64_t)data[pos + i]) << (8 * i);
    } else {
        for (NSUInteger i = 0; i < n; i++) v = (v << 8) | data[pos + i];
    }
    return v;
}

static uint64_t JC4ReadUInt(JC4Parser *p, NSUInteger n) {
    if (!JC4Need(p, n) || n == 0 || n > 8) return 0;
    uint64_t v = JC4UIntAt(p->data, p->pos, n, p->littleEndian);
    p->pos += n;
    return v;
}

static int64_t JC4ReadSigned(JC4Parser *p, NSUInteger n) {
    uint64_t v = JC4ReadUInt(p, n);
    if (!p->ok) return 0;
    if (n == 1) return (int8_t)v;
    if (n == 2) return (int16_t)v;
    if (n == 4) return (int32_t)v;
    if (n == 8) return (int64_t)v;
    if (n < 8 && (v & ((uint64_t)1 << (n * 8 - 1)))) {
        uint64_t mask = ~((((uint64_t)1) << (n * 8)) - 1);
        return (int64_t)(v | mask);
    }
    return (int64_t)v;
}

static BOOL JC4Skip(JC4Parser *p, uint64_t count, NSUInteger elemSize) {
    if (!p->ok) return NO;
    if (!elemSize || count > (uint64_t)NSUIntegerMax / elemSize) {
        JC4Fail(p, @"size overflow");
        return NO;
    }
    NSUInteger bytes = (NSUInteger)count * elemSize;
    if (!JC4Need(p, bytes)) return NO;
    p->pos += bytes;
    return YES;
}

static uint64_t JC4ReadCount(JC4Parser *p) {
    int64_t n = JC4ReadSigned(p, p->intSize);
    if (!p->ok) return 0;
    if (n < 0 || (uint64_t)n > JC4_MAX_COUNT) {
        JC4Fail(p, [NSString stringWithFormat:@"invalid count %lld", (long long)n]);
        return 0;
    }
    return (uint64_t)n;
}

static void JC4CollectString(JC4Parser *p, NSString *s) {
    if (!s.length) return;
    p->stringsSeen++;
    if (p->strings.count >= 200000) return;
    if ([p->stringSet containsObject:s]) return;
    [p->stringSet addObject:s];
    [p->strings addObject:s];
}

static NSString *JC4ReadString(JC4Parser *p) {
    if (!JC4Need(p, 1)) return nil;
    uint64_t size = p->data[p->pos++];
    if (size == 0) return nil;
    if (size == 0xFF) {
        NSUInteger extSize = p->officialLayout ? p->sizeTSize : 4;
        if (!extSize || extSize > 8) {
            JC4Fail(p, @"invalid extended string size field");
            return nil;
        }
        size = JC4ReadUInt(p, extSize);
        if (!p->ok) return nil;
    }
    if (size == 0) return nil;
    size--;
    if (size > NSUIntegerMax || !JC4Need(p, (NSUInteger)size)) return nil;
    NSString *s = [[[NSString alloc] initWithBytes:p->data + p->pos length:(NSUInteger)size encoding:NSUTF8StringEncoding] autorelease];
    p->pos += (NSUInteger)size;
    if (s.length) JC4CollectString(p, s);
    return s;
}

static double JC4DoubleAt(const uint8_t *data, NSUInteger pos, BOOL little) {
    uint8_t tmp[8];
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    BOOL hostLittle = YES;
#else
    BOOL hostLittle = NO;
#endif
    if (little == hostLittle) memcpy(tmp, data + pos, 8);
    else for (NSUInteger i = 0; i < 8; i++) tmp[i] = data[pos + 7 - i];
    double d = 0.0;
    memcpy(&d, tmp, 8);
    return d;
}

static BOOL JC4PlausibleSize(uint8_t n) {
    return n == 1 || n == 2 || n == 4 || n == 8;
}

static BOOL JC4TryOfficialHeader(JC4Parser *p) {
    if (p->length < 33) return NO;
    NSUInteger q = 12;
    uint8_t intSize = p->data[q++];
    uint8_t sizeTSize = p->data[q++];
    uint8_t instructionSize = p->data[q++];
    uint8_t integerSize = p->data[q++];
    uint8_t numberSize = p->data[q++];
    if (!JC4PlausibleSize(intSize) || !JC4PlausibleSize(sizeTSize) || !JC4PlausibleSize(instructionSize) || !JC4PlausibleSize(integerSize) || !JC4PlausibleSize(numberSize)) return NO;
    if (integerSize > 8 || numberSize != 8 || q + integerSize + numberSize > p->length) return NO;
    uint64_t ivLE = JC4UIntAt(p->data, q, integerSize, YES);
    uint64_t ivBE = JC4UIntAt(p->data, q, integerSize, NO);
    BOOL little;
    if (ivLE == 0x5678) little = YES;
    else if (ivBE == 0x5678) little = NO;
    else return NO;
    q += integerSize;
    double nv = JC4DoubleAt(p->data, q, little);
    if (fabs(nv - 370.5) > 0.000001) return NO;
    q += numberSize;
    p->officialLayout = YES;
    p->compatibleLayout = NO;
    p->littleEndian = little;
    p->intSize = intSize;
    p->sizeTSize = sizeTSize;
    p->instructionSize = instructionSize;
    p->integerSize = integerSize;
    p->numberSize = numberSize;
    p->headerSize = q;
    p->pos = q;
    return YES;
}

static BOOL JC4TryCompatibleHeader(JC4Parser *p) {
    if (p->length < 32) return NO;
    NSUInteger q = 12;
    uint8_t intSize = p->data[q++];
    uint8_t instructionSize = p->data[q++];
    uint8_t integerSize = p->data[q++];
    uint8_t numberSize = p->data[q++];
    if (!JC4PlausibleSize(intSize) || !JC4PlausibleSize(instructionSize) || !JC4PlausibleSize(integerSize) || !JC4PlausibleSize(numberSize)) return NO;
    if (integerSize > 8 || numberSize != 8 || q + integerSize + numberSize > p->length) return NO;
    uint64_t ivLE = JC4UIntAt(p->data, q, integerSize, YES);
    uint64_t ivBE = JC4UIntAt(p->data, q, integerSize, NO);
    BOOL little;
    if (ivLE == 0x5678) little = YES;
    else if (ivBE == 0x5678) little = NO;
    else return NO;
    q += integerSize;
    double nv = JC4DoubleAt(p->data, q, little);
    if (fabs(nv - 370.5) > 0.000001) return NO;
    q += numberSize;
    p->officialLayout = NO;
    p->compatibleLayout = YES;
    p->littleEndian = little;
    p->intSize = intSize;
    p->sizeTSize = 0;
    p->instructionSize = instructionSize;
    p->integerSize = integerSize;
    p->numberSize = numberSize;
    p->headerSize = q;
    p->pos = q;
    return YES;
}

static BOOL JC4ParseHeader(JC4Parser *p) {
    if (p->length < 16) { JC4Fail(p, @"chunk too short"); return NO; }
    if (!(p->data[0] == 0x1B && p->data[1] == 'L' && p->data[2] == 'u' && p->data[3] == 'a')) { JC4Fail(p, @"missing Lua signature"); return NO; }
    p->version = p->data[4];
    p->format = p->data[5];
    if (p->version != 0x53) { JC4Fail(p, [NSString stringWithFormat:@"unsupported Lua version 0x%02x", p->version]); return NO; }
    const uint8_t luacData[6] = {0x19, 0x93, 0x0D, 0x0A, 0x1A, 0x0A};
    if (memcmp(p->data + 6, luacData, 6) != 0) { JC4Fail(p, @"LUAC_DATA mismatch"); return NO; }
    if (!JC4TryOfficialHeader(p) && !JC4TryCompatibleHeader(p)) {
        JC4Fail(p, @"unrecognized Lua 5.3 header layout");
        return NO;
    }
    if (!JC4Need(p, 1)) return NO;
    p->rootUpvalues = p->data[p->pos++];
    return YES;
}

static BOOL JC4ParseFunction(JC4Parser *p, NSUInteger depth) {
    if (!p->ok) return NO;
    if (depth > JC4_MAX_DEPTH) { JC4Fail(p, @"prototype recursion too deep"); return NO; }
    p->functions++;
    (void)JC4ReadString(p);
    (void)JC4ReadSigned(p, p->intSize);
    (void)JC4ReadSigned(p, p->intSize);
    if (!JC4Need(p, 3)) return NO;
    p->pos += 3;

    uint64_t ncode = JC4ReadCount(p);
    if (!p->ok) return NO;
    for (uint64_t i = 0; i < ncode; i++) {
        if (!JC4Need(p, p->instructionSize)) return NO;
        if (p->instructionSize == 4) {
            uint32_t ins = (uint32_t)JC4UIntAt(p->data, p->pos, 4, p->littleEndian);
            uint8_t opcode = (uint8_t)(ins & 0x3F);
            p->opcodeHistogram[opcode]++;
            if (opcode > p->maxOpcode) p->maxOpcode = opcode;
            if (opcode > JC4_MAX_OPCODE) p->opcodeOutOfRange++;
        }
        p->pos += p->instructionSize;
        p->instructions++;
    }

    uint64_t nk = JC4ReadCount(p);
    if (!p->ok) return NO;
    p->constants += nk;
    for (uint64_t i = 0; i < nk; i++) {
        if (!JC4Need(p, 1)) return NO;
        uint8_t t = p->data[p->pos++];
        switch (t) {
            case 0: break;
            case 1:
                if (!JC4Skip(p, 1, 1)) return NO;
                break;
            case 3:
                if (!JC4Skip(p, 1, p->numberSize)) return NO;
                break;
            case 19:
                if (!JC4Skip(p, 1, p->integerSize)) return NO;
                break;
            case 4:
            case 20:
                (void)JC4ReadString(p);
                if (!p->ok) return NO;
                break;
            default:
                JC4Fail(p, [NSString stringWithFormat:@"unknown constant tag %u", t]);
                return NO;
        }
    }

    uint64_t nup = JC4ReadCount(p);
    if (!p->ok || !JC4Skip(p, nup, 2)) return NO;

    uint64_t np = JC4ReadCount(p);
    if (!p->ok) return NO;
    for (uint64_t i = 0; i < np; i++) if (!JC4ParseFunction(p, depth + 1)) return NO;

    uint64_t nline = JC4ReadCount(p);
    if (!p->ok || !JC4Skip(p, nline, p->intSize)) return NO;

    uint64_t nloc = JC4ReadCount(p);
    if (!p->ok) return NO;
    for (uint64_t i = 0; i < nloc; i++) {
        (void)JC4ReadString(p);
        (void)JC4ReadSigned(p, p->intSize);
        (void)JC4ReadSigned(p, p->intSize);
        if (!p->ok) return NO;
    }

    uint64_t nupnames = JC4ReadCount(p);
    if (!p->ok) return NO;
    for (uint64_t i = 0; i < nupnames; i++) {
        (void)JC4ReadString(p);
        if (!p->ok) return NO;
    }
    return p->ok;
}

static NSString *JC4Profile(JC4Parser *p) {
    if (p->officialLayout && p->format == 1) return @"lua53-format1-official-layout";
    if (p->compatibleLayout && p->format == 1) return @"lua53-format1-compatible-layout";
    if (p->officialLayout) return @"lua53-official-layout";
    if (p->compatibleLayout) return @"lua53-compatible-layout";
    return @"lua53-unknown-layout";
}

static NSString *JC4StringsText(NSArray *strings) {
    NSMutableString *out = [NSMutableString string];
    for (NSString *s in strings) {
        NSString *line = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
        line = [line stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        [out appendString:line ?: @""];
        [out appendString:@"\n"];
    }
    return out;
}

void JC4AnalyzeLua53Data(NSData *data, NSString *source, NSString *chunkName, NSString *rootPath) {
    if (!data.length || !rootPath.length) return;
    NSInteger sig = JC4FindLua53SignatureOffset(data);
    if (sig == NSNotFound) return;
    NSUInteger wrapperOffset = (NSUInteger)sig;
    NSData *clean = wrapperOffset ? [data subdataWithRange:NSMakeRange(wrapperOffset, data.length - wrapperOffset)] : data;
    NSString *hash = JC4SHA256(clean);
    if (!hash.length) return;

    pthread_mutex_lock(&gJC4SeenLock);
    if (!gJC4SeenCleanHashes) gJC4SeenCleanHashes = [[NSMutableSet alloc] init];
    BOOL seen = [gJC4SeenCleanHashes containsObject:hash];
    if (!seen) [gJC4SeenCleanHashes addObject:hash];
    pthread_mutex_unlock(&gJC4SeenLock);
    if (seen) return;

    JC4Parser p;
    memset(&p, 0, sizeof(p));
    p.data = clean.bytes;
    p.length = clean.length;
    p.ok = YES;
    p.strings = [[NSMutableArray alloc] init];
    p.stringSet = [[NSMutableSet alloc] init];

    if (JC4ParseHeader(&p)) JC4ParseFunction(&p, 0);
    uint64_t trailing = p.pos <= p.length ? (uint64_t)(p.length - p.pos) : 0;

    NSMutableDictionary *hist = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < 64; i++) if (p.opcodeHistogram[i]) [hist setObject:@(p.opcodeHistogram[i]) forKey:[NSString stringWithFormat:@"%lu", (unsigned long)i]];

    NSString *profile = JC4Profile(&p);
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    [report setObject:JC4_ANALYZER_VERSION forKey:@"analyzer_version"];
    [report setObject:(source ?: @"") forKey:@"source"];
    [report setObject:(chunkName ?: @"") forKey:@"chunk"];
    [report setObject:@(data.length) forKey:@"original_bytes"];
    [report setObject:@(clean.length) forKey:@"clean_bytes"];
    [report setObject:@(wrapperOffset) forKey:@"signature_offset"];
    [report setObject:hash forKey:@"clean_sha256"];
    [report setObject:@(p.version) forKey:@"lua_version_byte"];
    [report setObject:@(p.format) forKey:@"luac_format"];
    [report setObject:profile forKey:@"profile"];
    [report setObject:(p.littleEndian ? @"little" : @"big") forKey:@"endianness"];
    [report setObject:@(p.headerSize) forKey:@"header_bytes"];
    [report setObject:@(p.intSize) forKey:@"sizeof_int"];
    [report setObject:@(p.sizeTSize) forKey:@"sizeof_size_t"];
    [report setObject:@(p.instructionSize) forKey:@"sizeof_instruction"];
    [report setObject:@(p.integerSize) forKey:@"sizeof_lua_integer"];
    [report setObject:@(p.numberSize) forKey:@"sizeof_lua_number"];
    [report setObject:@(p.rootUpvalues) forKey:@"root_upvalues"];
    [report setObject:@(p.ok) forKey:@"parse_ok"];
    [report setObject:@(p.errorOffset) forKey:@"error_offset"];
    [report setObject:(p.error ?: @"") forKey:@"parse_error"];
    [report setObject:@(p.functions) forKey:@"functions"];
    [report setObject:@(p.instructions) forKey:@"instructions"];
    [report setObject:@(p.constants) forKey:@"constants"];
    [report setObject:@(p.stringsSeen) forKey:@"strings_seen"];
    [report setObject:@(p.strings.count) forKey:@"strings_unique"];
    [report setObject:@(p.maxOpcode) forKey:@"max_opcode"];
    [report setObject:@(p.opcodeOutOfRange) forKey:@"opcode_out_of_range_0_46"];
    [report setObject:@(trailing) forKey:@"trailing_bytes"];
    [report setObject:hist forKey:@"opcode_histogram"];
    [report setObject:@"Opcode range validation only; zero out-of-range opcodes does not prove the opcode meanings/order are stock Lua 5.3." forKey:@"opcode_validation_note"];

    NSString *dir = [rootPath stringByAppendingPathComponent:@"lua53_analysis"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *shortHash = hash.length > 12 ? [hash substringToIndex:12] : hash;
    NSString *base = [NSString stringWithFormat:@"%@_%@", JC4SafeName(chunkName ?: @"unnamed"), shortHash];
    NSString *cleanPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".luac"]];
    NSString *jsonPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".analysis.json"]];
    NSString *stringsPath = [dir stringByAppendingPathComponent:[base stringByAppendingString:@".strings.txt"]];
    [clean writeToFile:cleanPath atomically:YES];
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    if (json.length) [json writeToFile:jsonPath atomically:YES];
    [JC4StringsText(p.strings) writeToFile:stringsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [p.error release];
    [p.strings release];
    [p.stringSet release];
}
