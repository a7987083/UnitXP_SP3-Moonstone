#!/usr/bin/env python3
from pathlib import Path
import sys


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly 1 marker, found {count}")
    return text.replace(old, new, 1)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_unitxp_tooltip_fields.py <upstream-source-dir>")
    root = Path(sys.argv[1])
    cpp_path = root / "UnitXPDbc.cpp"
    text = cpp_path.read_text(encoding="utf-8")

    marker = '    setNumber(L, "stackAmount", gSpell.u32(r, 39u));\n'
    addition = marker + '''    // Spell.dbc fields needed by the classic 1.12 spell-description $-token engine.\n    setNumber(L, "procFlags", gSpell.u32(r, 24u));\n    setNumber(L, "procChance", gSpell.u32(r, 25u));\n    setNumber(L, "procCharges", gSpell.u32(r, 26u));\n    setNumber(L, "maximumLevel", gSpell.u32(r, 27u));\n    setNumber(L, "baseLevel", gSpell.u32(r, 28u));\n    setNumber(L, "spellLevel", gSpell.u32(r, 29u));\n    setNumber(L, "manaCostPerLevel", gSpell.u32(r, 33u));\n    setNumber(L, "manaPerSecond", gSpell.u32(r, 34u));\n    setNumber(L, "manaPerSecondPerLevel", gSpell.u32(r, 35u));\n'''
    text = replace_once(text, marker, addition, "early tooltip fields")

    marker2 = '    if (gSpell.fields > 151u) setString(L, "auraDescriptionZhCN", gSpell.str(r, 151u));\n    return 1;\n'
    addition2 = '''    if (gSpell.fields > 151u) setString(L, "auraDescriptionZhCN", gSpell.str(r, 151u));\n    if (gSpell.fields > 156u) setNumber(L, "manaCostPercentage", gSpell.u32(r, 156u));\n    if (gSpell.fields > 157u) setNumber(L, "startRecoveryCategory", gSpell.u32(r, 157u));\n    if (gSpell.fields > 158u) setNumber(L, "startRecoveryTime", gSpell.u32(r, 158u));\n    if (gSpell.fields > 159u) setNumber(L, "maximumTargetLevel", gSpell.u32(r, 159u));\n    if (gSpell.fields > 160u) setNumber(L, "spellFamilyName", gSpell.u32(r, 160u));\n    if (gSpell.fields > 161u) setNumber(L, "spellFamilyFlags1", gSpell.u32(r, 161u));\n    if (gSpell.fields > 162u) setNumber(L, "spellFamilyFlags2", gSpell.u32(r, 162u));\n    if (gSpell.fields > 163u) setNumber(L, "maximumAffectedTargets", gSpell.u32(r, 163u));\n    if (gSpell.fields > 164u) setNumber(L, "damageClass", gSpell.u32(r, 164u));\n    if (gSpell.fields > 165u) setNumber(L, "preventionType", gSpell.u32(r, 165u));\n    if (gSpell.fields > 166u) setNumber(L, "stanceBarOrder", gSpell.u32(r, 166u));\n    if (gSpell.fields > 169u) {\n        for (std::uint32_t i = 0u; i < 3u; ++i) {\n            const std::string suffix(1, static_cast<char>('1' + i));\n            setNumber(L, (std::string("effectDamageMultiplier") + suffix).c_str(), gSpell.f32(r, 167u + i));\n        }\n    }\n    return 1;\n'''
    text = replace_once(text, marker2, addition2, "late tooltip fields")

    cpp_path.write_text(text, encoding="utf-8", newline="\n")
    final = cpp_path.read_text(encoding="utf-8")
    for needle in [
        '"procChance"', 'gSpell.u32(r, 25u)', '"procCharges"', 'gSpell.u32(r, 26u)',
        '"maximumTargetLevel"', 'gSpell.u32(r, 159u)',
        '"maximumAffectedTargets"', 'gSpell.u32(r, 163u)',
        'std::string("effectDamageMultiplier") + suffix',
    ]:
        if needle not in final:
            raise RuntimeError(f"postcondition failed: {needle}")
    print("UnitXP classic tooltip support fields: OK")


if __name__ == "__main__":
    main()
