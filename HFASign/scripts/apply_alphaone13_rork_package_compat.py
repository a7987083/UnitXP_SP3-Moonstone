#!/usr/bin/env python3
from pathlib import Path

path = Path("HFASignBuild/RorkUsbmux/Package.swift")
text = path.read_text()

old_target = '''        .binaryTarget(
            name: "OpenSSL",
            path: "Vendor/OpenSSL/libopenssl.xcframework"
        ),'''
new_target = '''        .binaryTarget(
            name: "RorkOpenSSL",
            path: "Vendor/OpenSSL/libopenssl.xcframework"
        ),'''
if text.count(old_target) != 1:
    raise SystemExit(
        f"Rork package compat: expected one OpenSSL binary target, found {text.count(old_target)}"
    )
text = text.replace(old_target, new_target, 1)

old_dependency = '''            dependencies: [
                "OpenSSL",
            ],'''
new_dependency = '''            dependencies: [
                "RorkOpenSSL",
            ],'''
if text.count(old_dependency) != 1:
    raise SystemExit(
        f"Rork package compat: expected one OpenSSL dependency, found {text.count(old_dependency)}"
    )
text = text.replace(old_dependency, new_dependency, 1)

path.write_text(text)

if 'name: "OpenSSL"' in text:
    raise SystemExit("Rork package compat: conflicting OpenSSL target name remains")
if '"RorkOpenSSL"' not in text:
    raise SystemExit("Rork package compat: renamed binary target missing")

print("RorkUsbmux package compat applied: OpenSSL target renamed to RorkOpenSSL")
