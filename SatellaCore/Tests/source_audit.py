from pathlib import Path
import re
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
sources = root / 'Sources'
errors = []
warnings = []

# These remain hard policy boundaries for the Objective-C port.
forbidden_patterns = {
    'SwiftUI': r'\bSwiftUI\b',
    'Combine': r'\bCombine\b',
    'Jinx': r'\bJinx\b',
    'Substrate hook': r'\b(MSHookFunction|MSHookMessageEx|MSFindSymbol)\b',
}

# StoreKit and native Objective-C runtime/dyld APIs are no longer globally
# forbidden. If introduced, they must be isolated and explicitly marked for
# review so the audit catches accidental, unaudited runtime-sensitive changes.
runtime_sensitive_patterns = {
    'StoreKit dependency': r'(?:#import\s*[<"]StoreKit/|@import\s+StoreKit\s*;)',
    'Objective-C runtime mutation': r'\b(class_replaceMethod|method_setImplementation|method_exchangeImplementations|class_addMethod)\b',
    'dyld image API': r'\b_dyld_get_image_name\b',
}
review_marker = 'SJ_RUNTIME_REVIEWED'

for path in sources.rglob('*'):
    if not path.is_file():
        continue
    if path.suffix == '.swift':
        errors.append(f'unexpected Swift source: {path.relative_to(root)}')
    if path.suffix not in {'.h', '.m', '.c', '.mm'}:
        continue
    text = path.read_text(encoding='utf-8')
    for label, pattern in forbidden_patterns.items():
        if re.search(pattern, text, re.S):
            errors.append(f'{path.relative_to(root)}: forbidden {label}')
    sensitive_hits = [label for label, pattern in runtime_sensitive_patterns.items() if re.search(pattern, text, re.S)]
    if sensitive_hits and review_marker not in text:
        errors.append(
            f'{path.relative_to(root)}: runtime-sensitive code ({", ".join(sensitive_hits)}) '
            f'must contain {review_marker} and be separately reviewed'
        )
    elif sensitive_hits:
        warnings.append(f'{path.relative_to(root)}: reviewed runtime-sensitive code: {", ".join(sensitive_hits)}')

public = (sources / 'Public' / 'SatellaCore.h').read_text(encoding='utf-8')
for required in [
    'SJFeatureProductCatalogFallback',
    'SJFeatureTransactionSimulation',
    'SJFeatureReceiptSimulation',
    'SJFeatureCanMakePaymentsOverride',
    'SJFeaturePriceOverride',
    'SJFeatureObserverBridge',
    'SJFeatureStealthSimulation',
    'reloadPreferencesFromUserDefaults',
]:
    if required not in public:
        errors.append(f'public API missing: {required}')

config_header = (sources / 'Public' / 'SJConfiguration.h').read_text(encoding='utf-8')
for required in ['SJBehaviorModeUpstreamParity', 'SJBehaviorModeExtendedTesting', 'behaviorMode']:
    if required not in config_header:
        errors.append(f'configuration API missing: {required}')

engine = (sources / 'Public' / 'SJStoreKitTestEngine.h').read_text(encoding='utf-8')
for required in [
    'canMakePaymentsWithSystemValue',
    'effectivePriceForProduct',
    'deliverProductsForIdentifiers',
    'invalidProductIdentifiers',
    'publishTransactions',
    'oldReceiptDataForProductIdentifier',
    'verificationResponseDataForURL',
]:
    if required not in engine:
        errors.append(f'test engine API missing: {required}')

if errors:
    print('SOURCE AUDIT FAILED')
    for error in errors:
        print('-', error)
    sys.exit(1)

for warning in warnings:
    print('SOURCE AUDIT NOTE:', warning)

parity = root / 'Tests' / 'upstream_parity_audit.py'
result = subprocess.run([sys.executable, str(parity)], cwd=root)
if result.returncode != 0:
    sys.exit(result.returncode)

print('SOURCE AUDIT PASSED')
