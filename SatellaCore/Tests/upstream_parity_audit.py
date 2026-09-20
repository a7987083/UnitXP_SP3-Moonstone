from pathlib import Path
import base64
import hashlib
import re
import sys

root = Path(__file__).resolve().parents[1]
errors = []

receipt = (root / 'Sources/Internal/SJReceiptGenerator.m').read_text(encoding='utf-8')
engine = (root / 'Sources/Internal/SJStoreKitTestEngine.m').read_text(encoding='utf-8')
core = (root / 'Sources/Internal/SatellaCore.m').read_text(encoding='utf-8')
models = (root / 'Sources/Internal/SJReceiptModels.m').read_text(encoding='utf-8')
config = (root / 'Sources/Internal/SJConfiguration.m').read_text(encoding='utf-8')
mock = (root / 'Sources/Internal/SJStoreKitMock.m').read_text(encoding='utf-8')
header = (root / 'Sources/Public/SJStoreKitTestEngine.h').read_text(encoding='utf-8')

# Signature baseline extracted from Paisseon/SatellaJailed@469e6eb.
m = re.search(r'upstreamReceiptSignatureBase64\s*\{[\s\S]*?return @"([A-Za-z0-9+/=]+)";', receipt)
if not m:
    errors.append('SJReceiptGenerator.m: upstream receipt signature constant missing')
else:
    try:
        signature = base64.b64decode(m.group(1), validate=True)
    except Exception as exc:
        errors.append(f'SJReceiptGenerator.m: invalid signature base64: {exc}')
    else:
        if len(signature) != 1667:
            errors.append(f'SJReceiptGenerator.m: signature length {len(signature)} != 1667')
        digest = hashlib.sha256(signature).hexdigest()
        if digest != '5140ee9463d2f8ac278ff300f0b149bc3bb2d6fa02a74722d1d44a2de6e69a95':
            errors.append(f'SJReceiptGenerator.m: signature SHA-256 mismatch: {digest}')

checks = [
    (receipt, '@"emt.paisseon.satella"', 'upstream bundle fallback missing'),
    (receipt, '@"emt.paisseon.satella.product"', 'upstream old-receipt product fallback missing'),
    (receipt, 'arc4random_uniform(0x07151129u) + 1u', 'inclusive upstream receipt ID range missing'),
    (receipt, 'long long seconds = (long long)date.timeIntervalSince1970;', 'upstream second-granularity timestamp conversion missing'),
    (receipt, 'NSString *nowMs = [self milliseconds:[NSDate date]];', 'first Date() evaluation for milliseconds missing'),
    (receipt, 'NSString *nowText = [self nowText:[NSDate date]];', 'second Date() evaluation for textual date missing'),
    (receipt, '@"original_purchase_date_ms": nowText', 'upstream original_purchase_date_ms behaviour missing'),
    (receipt, 'if (configuration.behaviorMode == SJBehaviorModeUpstreamParity)', 'strict environment parity mode missing'),
    (receipt, 'return @"Production";', 'Production literal missing'),
    (config, 'config.behaviorMode = SJBehaviorModeUpstreamParity;', 'default upstream parity mode missing'),
    (models, '_environment=@"Production";', 'receipt response model default is not Production'),
    (engine, 'return NSUUID.UUID.UUIDString;', 'dynamic transaction identifier getter missing'),
    (engine, 'return [NSDate date];', 'dynamic transaction date getter missing'),
    (engine, 'if (product) [products addObject:product];', 'fallback product identity preservation missing'),
    (mock, 'return state.products[productIdentifier];', 'mock product identity preservation missing'),
    (header, 'invalidProductIdentifiers:(NSArray<NSString *> *)invalidProductIdentifiers', 'invalid product identifier API missing'),
    (engine, 'response.invalidProductIdentifiers = invalidProductIdentifiers;', 'non-empty response invalid identifiers are not preserved'),
    (engine, 'response.invalidProductIdentifiers = @[];', 'fallback response invalid identifiers are not cleared like upstream fake response'),
    (engine, 'if (state.configuration.behaviorMode == SJBehaviorModeUpstreamParity) return YES;', 'canMakePayments strict parity result missing'),
    (engine, '[NSDecimalNumber decimalNumberWithString:@"0.01"]', 'strict price literal missing'),
    (engine, 'nil + no', 'pass-through result documentation missing'),
    (core, '@"1.3.0-result-parity"', 'result-parity version marker missing'),
]
for text, needle, message in checks:
    if needle not in text:
        errors.append(message)

for forbidden, message in [
    ('SATELLA-LOCAL-TEST-SIGNATURE', 'LocalTest receipt signature marker still present'),
    ('@"receipt_type": @"LocalTest"', 'LocalTest receipt_type still present'),
    ('response.environment = @"LocalTest"', 'LocalTest verification environment still present'),
    ('Transaction simulation requires an available mock product.', 'invented transaction/product dependency still present'),
    ('[[NSArray alloc] initWithArray:current copyItems:YES]', 'observer still deep-copies transactions'),
    ('[products addObject:[product copy]]', 'fallback product response still copies product objects'),
    ('copyItems:YES', 'products response copy still deep-copies product objects'),
]:
    if forbidden in receipt + engine + core + models + mock:
        errors.append(message)

if errors:
    print('UPSTREAM PARITY AUDIT FAILED')
    for error in errors:
        print('-', error)
    sys.exit(1)

print('UPSTREAM PARITY AUDIT PASSED')
