from pathlib import Path
import re
import sys

root=Path(__file__).resolve().parents[1]
sources=root/'Sources'
errors=[]
patterns={
    'constructor': r'__attribute__\s*\(\s*\(.*?constructor',
    '+load': r'\+\s*\(\s*void\s*\)\s*load\b',
    'UIKit import': r'(?:#import\s*[<"]UIKit/|@import\s+UIKit\s*;)',
    'SwiftUI': r'\bSwiftUI\b',
    'Combine': r'\bCombine\b',
    'Jinx': r'\bJinx\b',
    'live StoreKit import': r'(?:#import\s*[<"]StoreKit/|@import\s+StoreKit\s*;)',
    'objc runtime mutation': r'\b(class_replaceMethod|method_setImplementation|method_exchangeImplementations|class_addMethod)\b',
    'Substrate hook': r'\b(MSHookFunction|MSHookMessageEx|MSFindSymbol)\b',
    'dyld image concealment': r'\b_dyld_get_image_name\b',
}
for path in sources.rglob('*'):
    if not path.is_file(): continue
    if path.suffix=='.swift': errors.append(f'unexpected Swift source: {path.relative_to(root)}')
    if path.suffix not in {'.h','.m','.c','.mm'}: continue
    text=path.read_text(encoding='utf-8')
    for label,pattern in patterns.items():
        if re.search(pattern,text,re.S): errors.append(f'{path.relative_to(root)}: forbidden {label}')

public=(sources/'Public'/'SatellaCore.h').read_text(encoding='utf-8')
for required in ['SJFeatureProductCatalogFallback','SJFeatureTransactionSimulation','SJFeatureReceiptSimulation','SJFeatureCanMakePaymentsOverride','SJFeaturePriceOverride','SJFeatureObserverBridge','SJFeatureStealthSimulation','reloadPreferencesFromUserDefaults']:
    if required not in public: errors.append(f'public API missing: {required}')

engine=(sources/'Public'/'SJStoreKitTestEngine.h').read_text(encoding='utf-8')
for required in ['canMakePaymentsWithSystemValue','effectivePriceForProduct','deliverProductsForIdentifiers','publishTransactions','oldReceiptDataForProductIdentifier','verificationResponseDataForURL']:
    if required not in engine: errors.append(f'test engine API missing: {required}')

if errors:
    print('SOURCE AUDIT FAILED')
    for e in errors: print('-',e)
    sys.exit(1)
print('SOURCE AUDIT PASSED')
