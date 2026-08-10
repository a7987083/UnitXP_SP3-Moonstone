#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "UnitXPDbc.cpp"
if not cpp.is_file():
    raise SystemExit(f"missing generated DBC source: {cpp}")

text = cpp.read_text(encoding="utf-8")

replacements = [
    (
        'setNumber(L, (std::string("targetA") + suffix).c_str(), gSpell.u32(r, 85u + i));',
        'setNumber(L, (std::string("targetA") + suffix).c_str(), gSpell.u32(r, 82u + i));',
        "Spell ImplicitTargetA offset",
    ),
    (
        'setNumber(L, (std::string("targetB") + suffix).c_str(), gSpell.u32(r, 88u + i));',
        'setNumber(L, (std::string("targetB") + suffix).c_str(), gSpell.u32(r, 85u + i));',
        "Spell ImplicitTargetB offset",
    ),
    (
        'setNumber(L, (std::string("radiusIndex") + suffix).c_str(), gSpell.u32(r, 91u + i));',
        'setNumber(L, (std::string("radiusIndex") + suffix).c_str(), gSpell.u32(r, 88u + i));',
        "Spell EffectRadiusIndex offset",
    ),
    (
        'setNumber(L, "radiusPerLevel", gRadius.f32(r, 2u));',
        'setNumber(L, "radiusPerLevel", gRadius.i32(r, 2u));',
        "SpellRadius per-level type",
    ),
    (
        'setNumber(L, "radiusMax", gRadius.f32(r, 3u));',
        'setNumber(L, "radiusMax", gRadius.i32(r, 3u));',
        "SpellRadius max type",
    ),
]

for old, new, label in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one old expression, found {count}")
    text = text.replace(old, new, 1)

cpp.write_text(text, encoding="utf-8", newline="\n")

checks = [
    'gSpell.u32(r, 82u + i)',
    'gSpell.u32(r, 85u + i)',
    'gSpell.u32(r, 88u + i)',
    'gRadius.i32(r, 2u)',
    'gRadius.i32(r, 3u)',
]
final = cpp.read_text(encoding="utf-8")
for needle in checks:
    if needle not in final:
        raise SystemExit(f"postcondition failed: {needle}")

print("UnitXP DBC fusion B1 schema correction: OK")
