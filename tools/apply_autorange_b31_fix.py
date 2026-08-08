#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "AutoRange.cpp"
if not cpp.is_file():
    raise SystemExit(f"missing {cpp}")

text = cpp.read_text(encoding="utf-8")

# WoW 1.12.1 client Spell.dbc has NO EffectBonusCoefficient[3] columns.
# The vMaNGOS runtime SpellEntry class inserts those server-side fields, so using
# its in-memory member comments as raw DBC column numbers shifts every field
# after EffectBasePoints by +3.  Correct raw 1.12 client DBC columns are:
#   EffectMechanic       79..81
#   ImplicitTargetA      82..84
#   ImplicitTargetB      85..87
#   EffectRadiusIndex    88..90
#   EffectAura           91..93
#   EffectAmplitude      94..96
#   EffectMultipleValue  97..99
#   EffectChainTarget   100..102
#   EffectItemType      103..105
#   EffectMiscValue     106..108
#   EffectTriggerSpell  109..111
#   EffectPointsCombo   112..114

repls = [
    ("gCache.spell.u32(r, 85u + i)", "gCache.spell.u32(r, 82u + i)"),
    ("gCache.spell.u32(r, 88u + i)", "gCache.spell.u32(r, 85u + i)"),
    ("gCache.spell.u32(r, 91u + i)", "gCache.spell.u32(r, 88u + i)"),
    ("gCache.spell.u32(r, 112u + i)", "gCache.spell.u32(r, 109u + i)"),
]
for old, new in repls:
    count = text.count(old)
    if count < 1:
        raise SystemExit(f"expected marker missing: {old}")
    text = text.replace(old, new)

# Make the schema origin explicit in native status so screenshots identify the fix.
old = 'return std::string("OK|Spell=") + safeSource(gCache.spell.source)'
new = 'return std::string("OK|Schema=CLIENT1121|Spell=") + safeSource(gCache.spell.source)'
if old not in text:
    raise SystemExit("status marker missing")
text = text.replace(old, new, 1)

cpp.write_text(text, encoding="utf-8", newline="\n")

checks = [
    "gCache.spell.u32(r, 82u + i)",
    "gCache.spell.u32(r, 85u + i)",
    "gCache.spell.u32(r, 88u + i)",
    "gCache.spell.u32(r, 109u + i)",
    "Schema=CLIENT1121",
]
final = cpp.read_text(encoding="utf-8")
for needle in checks:
    if needle not in final:
        raise SystemExit(f"postcondition missing: {needle}")

print("AutoRange B3.1 raw 1.12 Spell.dbc offset fix: OK")
