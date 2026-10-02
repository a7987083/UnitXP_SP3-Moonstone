#!/usr/bin/env python3
from pathlib import Path

package = Path("HFASignBuild/IDeviceKit/Package.swift")
text = package.read_text()
old = "\t\t.iOS(.v15),"
new = "\t\t.iOS(.v13),"
count = text.count(old)
if count != 1:
    raise SystemExit(f"iOS13 dependency compat: expected one IDeviceKit iOS 15 platform declaration, found {count}")
package.write_text(text.replace(old, new, 1))

print("iOS13 dependency compat applied: IDeviceKit platform iOS 15 -> iOS 13")
