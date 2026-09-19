from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
sources = root / "Sources"
errors = []

for path in sources.rglob("*"):
    if not path.is_file():
        continue
    rel = path.relative_to(root)
    if path.suffix == ".swift":
        errors.append(f"unexpected Swift source: {rel}")
    if path.suffix not in {".h", ".m", ".c", ".mm"}:
        continue
    text = path.read_text(encoding="utf-8")
    forbidden = {
        "constructor": r"__attribute__\s*\(\(\s*constructor\s*\)\)",
        "+load": r"\+\s*\(\s*void\s*\)\s*load\b",
        "UIKit": r"#import\s*[<\"]UIKit/",
        "SwiftUI": r"\bSwiftUI\b",
        "Combine": r"\bCombine\b",
        "Jinx": r"\bJinx\b",
        "live StoreKit import": r"#import\s*[<\"]StoreKit/",
        "runtime method replacement": r"\b(class_replaceMethod|method_setImplementation|method_exchangeImplementations)\b",
        "Substrate hook": r"\b(MSHookFunction|MSHookMessageEx|MSFindSymbol)\b",
        "dyld concealment hook": r"\b_dyld_get_image_name\b",
    }
    for label, pattern in forbidden.items():
        if re.search(pattern, text):
            errors.append(f"{rel}: forbidden {label}")

public = (sources / "Public" / "SatellaCore.h").read_text(encoding="utf-8")
for required in [
    "+ (BOOL)setFeature:",
    "+ (BOOL)isFeatureEnabled:",
    "+ (NSDictionary<NSString *, id> *)status;",
    "+ (void)resetConfiguration;",
]:
    if required not in public:
        errors.append(f"public API missing: {required}")

if errors:
    print("SOURCE AUDIT FAILED")
    for error in errors:
        print(f"- {error}")
    sys.exit(1)

print("SOURCE AUDIT PASSED")
