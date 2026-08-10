#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "UnitXPDbc.cpp"
if not cpp.is_file():
    raise SystemExit(f"missing generated DBC source: {cpp}")

text = cpp.read_text(encoding="utf-8")

# Reliquary's 1.12 Spell schema places EffectApplyAuraName immediately after
# EffectRadiusIndex.  B1R1 already corrected RadiusIndex to fields 88..90,
# therefore ApplyAura is 91..93.  These are read-only, on-demand fields.
if 'std::string("applyAura") + suffix' not in text:
    needle = '        setNumber(L, (std::string("radiusIndex") + suffix).c_str(), gSpell.u32(r, 88u + i));\n'
    addition = (
        needle
        + '        setNumber(L, (std::string("applyAura") + suffix).c_str(), gSpell.u32(r, 91u + i));\n'
    )
    if text.count(needle) != 1:
        raise SystemExit(f"Spell radius marker: expected one match, got {text.count(needle)}")
    text = text.replace(needle, addition, 1)

# Expose the localized text fields used only by the one-shot totem resolver and
# diagnostics.  Field numbers follow Reliquary's classic Spell schema:
# name_enUS=120, name_zhCN=124, description_enUS=138,
# description_zhCN=142, auraDescription_enUS=147, auraDescription_zhCN=151.
if '"descriptionZhCN"' not in text:
    needle = '    if (gSpell.fields > 120u) setString(L, "name", gSpell.str(r, 120u));\n'
    replacement = (
        needle
        + '    if (gSpell.fields > 124u) setString(L, "nameZhCN", gSpell.str(r, 124u));\n'
        + '    if (gSpell.fields > 138u) setString(L, "descriptionEnUS", gSpell.str(r, 138u));\n'
        + '    if (gSpell.fields > 142u) setString(L, "descriptionZhCN", gSpell.str(r, 142u));\n'
        + '    if (gSpell.fields > 147u) setString(L, "auraDescriptionEnUS", gSpell.str(r, 147u));\n'
        + '    if (gSpell.fields > 151u) setString(L, "auraDescriptionZhCN", gSpell.str(r, 151u));\n'
    )
    if text.count(needle) != 1:
        raise SystemExit(f"Spell name marker: expected one match, got {text.count(needle)}")
    text = text.replace(needle, replacement, 1)

cpp.write_text(text, encoding="utf-8", newline="\n")

final = cpp.read_text(encoding="utf-8")
checks = [
    'std::string("applyAura") + suffix',
    'gSpell.u32(r, 91u + i)',
    '"descriptionEnUS"',
    'gSpell.str(r, 138u)',
    '"descriptionZhCN"',
    'gSpell.str(r, 142u)',
    '"auraDescriptionEnUS"',
    'gSpell.str(r, 147u)',
    '"auraDescriptionZhCN"',
    'gSpell.str(r, 151u)',
]
for needle in checks:
    if needle not in final:
        raise SystemExit(f"postcondition failed: {needle}")

print("AutoRange R6.3 Reliquary-derived Spell chain fields: OK")
