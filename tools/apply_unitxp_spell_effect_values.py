#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "UnitXPDbc.cpp"
if not cpp.is_file():
    raise SystemExit(f"missing generated DBC source: {cpp}")

text = cpp.read_text(encoding="utf-8")

# Classic 1.12 Spell.dbc effect payload fields.  Keep the existing API intact and
# only append read-only values to UnitXP("spell", spellId).  Field offsets are
# the same schema already used by the R6.3 DBC Fusion chain:
#   Effect             61..63
#   EffectDieSides     64..66
#   EffectBaseDice     67..69
#   EffectDicePerLevel 70..72
#   EffectRealPointsPerLevel 73..75
#   EffectBasePoints   76..78
#   EffectMechanic     79..81
#   ImplicitTargetA/B  82..87
#   Radius             88..90
#   ApplyAura          91..93
#   EffectAmplitude    94..96
#   EffectMultipleValue 97..99
#   EffectChainTarget  100..102
#   EffectItemType     103..105
#   EffectMiscValue    106..108
#   EffectTriggerSpell 109..111
#   EffectPointsPerComboPoint 112..114
#
# effectSimpleValue mirrors the classic server helper semantics:
# EffectBasePoints + EffectBaseDice.  Raw fields remain available so addons do
# not need to trust/use the derived convenience value.
marker = '        setNumber(L, (std::string("effect") + suffix).c_str(), gSpell.u32(r, 61u + i));\n'
if text.count(marker) != 1:
    raise SystemExit(f"Spell effect marker: expected one match, got {text.count(marker)}")

addition = marker + '''        setNumber(L, (std::string("effectDieSides") + suffix).c_str(), gSpell.i32(r, 64u + i));
        setNumber(L, (std::string("effectBaseDice") + suffix).c_str(), gSpell.u32(r, 67u + i));
        setNumber(L, (std::string("effectDicePerLevel") + suffix).c_str(), gSpell.f32(r, 70u + i));
        setNumber(L, (std::string("effectRealPointsPerLevel") + suffix).c_str(), gSpell.f32(r, 73u + i));
        setNumber(L, (std::string("effectBasePoints") + suffix).c_str(), gSpell.i32(r, 76u + i));
        setNumber(L, (std::string("effectMechanic") + suffix).c_str(), gSpell.u32(r, 79u + i));
        setNumber(L, (std::string("effectAmplitude") + suffix).c_str(), gSpell.u32(r, 94u + i));
        setNumber(L, (std::string("effectMultipleValue") + suffix).c_str(), gSpell.f32(r, 97u + i));
        setNumber(L, (std::string("effectChainTarget") + suffix).c_str(), gSpell.u32(r, 100u + i));
        setNumber(L, (std::string("effectItemType") + suffix).c_str(), gSpell.u32(r, 103u + i));
        setNumber(L, (std::string("effectPointsPerComboPoint") + suffix).c_str(), gSpell.f32(r, 112u + i));
        setNumber(L, (std::string("effectSimpleValue") + suffix).c_str(),
                  static_cast<double>(gSpell.i32(r, 76u + i))
                    + static_cast<double>(gSpell.u32(r, 67u + i)));
'''
text = text.replace(marker, addition, 1)

cpp.write_text(text, encoding="utf-8", newline="\n")

final = cpp.read_text(encoding="utf-8")
checks = [
    'std::string("effectDieSides") + suffix',
    'gSpell.i32(r, 64u + i)',
    'std::string("effectBaseDice") + suffix',
    'gSpell.u32(r, 67u + i)',
    'std::string("effectDicePerLevel") + suffix',
    'gSpell.f32(r, 70u + i)',
    'std::string("effectRealPointsPerLevel") + suffix',
    'gSpell.f32(r, 73u + i)',
    'std::string("effectBasePoints") + suffix',
    'gSpell.i32(r, 76u + i)',
    'std::string("effectMechanic") + suffix',
    'gSpell.u32(r, 79u + i)',
    'std::string("effectAmplitude") + suffix',
    'gSpell.u32(r, 94u + i)',
    'std::string("effectMultipleValue") + suffix',
    'gSpell.f32(r, 97u + i)',
    'std::string("effectChainTarget") + suffix',
    'gSpell.u32(r, 100u + i)',
    'std::string("effectItemType") + suffix',
    'gSpell.u32(r, 103u + i)',
    'std::string("effectPointsPerComboPoint") + suffix',
    'gSpell.f32(r, 112u + i)',
    'std::string("effectSimpleValue") + suffix',
]
for needle in checks:
    if needle not in final:
        raise SystemExit(f"postcondition failed: {needle}")

print("UnitXP Spell.dbc effect value fields: OK")
