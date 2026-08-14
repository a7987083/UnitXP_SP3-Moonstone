#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
p = root / "dllmain.cpp"
if not p.is_file():
    raise SystemExit(f"missing required source: {p}")

text = p.read_text(encoding="utf-8-sig")

helper = r'''
// UnitXP("castAOE", "target"|"player")
// One-shot bridge for the client's current ground-target cursor.  It deliberately
// does not start a spell, poll, move the mouse, or send a packet itself; it only
// resolves the requested unit position and feeds that XYZ to the vanilla client's
// Spell_C::HandleTerrainClick (WoW 1.12.1 build 5875 @ 0x006E60F0).
static bool unitXpCastAOEAtUnit(const std::string& unitID) {
    if (unitID != "target" && unitID != "player") {
        return false;
    }

    // SPELLMGR targeting state for WoW 1.12.1 build 5875.
    // +0x60: target-mask/flag_word.  +0x30: ground-target cursor flag.
    volatile uint16_t* targetingFlags = reinterpret_cast<volatile uint16_t*>(0x00CECAC0);
    volatile uint32_t* groundTargetFlag = reinterpret_cast<volatile uint32_t*>(0x00CECA90);
    if (*targetingFlags == 0 || *groundTargetFlag == 0) {
        return false;
    }

    const uint64_t guid = vanilla1121_unitGUID(unitID.c_str());
    if (guid == 0) {
        return false;
    }

    const uint32_t unit = vanilla1121_getVisiableObject(guid);
    if (unit == 0 || (unit & 1) != 0) {
        return false;
    }

    const int objectType = vanilla1121_objectType(unit);
    if (objectType != OBJECT_TYPE_Unit && objectType != OBJECT_TYPE_Player) {
        return false;
    }

    const C3Vector position = vanilla1121_unitPosition(unit);
    if (!std::isfinite(position.x) || !std::isfinite(position.y) || !std::isfinite(position.z)) {
        return false;
    }

    float xyz[3] = { position.x, position.y, position.z };
    typedef void(__fastcall* SPELL_C_HANDLETERRAINCLICK)(float*);
    static auto pSpellHandleTerrainClick =
        reinterpret_cast<SPELL_C_HANDLETERRAINCLICK>(0x006E60F0);

    pSpellHandleTerrainClick(xyz);

    // A valid accepted terrain click consumes the pending target mask.  Returning
    // false when it remains set makes diagnostics useful without changing game logic.
    return *targetingFlags == 0;
}

'''

if "static bool unitXpCastAOEAtUnit" not in text:
    marker = "int __fastcall detoured_UnitXP(void* L) {"
    if text.count(marker) != 1:
        raise SystemExit(f"detoured_UnitXP marker count != 1: {text.count(marker)}")
    text = text.replace(marker, helper + marker, 1)

branch = r'''        if (cmd == "castAOE") {
            const std::string unitID{ lua_tostring(L, 2) };
            lua_pushboolean(L, unitXpCastAOEAtUnit(unitID));
            return 1;
        }
'''

if 'if (cmd == "castAOE")' not in text:
    marker = '        string cmd{ lua_tostring(L, 1) };\n\n'
    if text.count(marker) != 1:
        raise SystemExit(f"command-dispatch marker count != 1: {text.count(marker)}")
    text = text.replace(marker, marker + branch + "\n", 1)

required = [
    'static bool unitXpCastAOEAtUnit',
    'if (cmd == "castAOE")',
    'unitID != "target" && unitID != "player"',
    '0x00CECAC0',
    '0x00CECA90',
    'vanilla1121_unitGUID(unitID.c_str())',
    'vanilla1121_getVisiableObject(guid)',
    'vanilla1121_unitPosition(unit)',
    '0x006E60F0',
    'pSpellHandleTerrainClick(xyz)',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"postcondition failed: missing {needle}")

# This API must remain request-driven: no timers, hooks, polling, or OnUpdate path.
helper_start = text.index("static bool unitXpCastAOEAtUnit")
handler_start = text.index("int __fastcall detoured_UnitXP", helper_start)
helper_text = text[helper_start:handler_start]
for forbidden in ["CreateThread", "SetTimer", "OnUpdate", "Sleep("]:
    if forbidden in helper_text:
        raise SystemExit(f"castAOE helper unexpectedly contains background mechanism: {forbidden}")

p.write_text(text, encoding="utf-8", newline="\n")
print('UnitXP castAOE unit-anchor patch: OK')
print('  UnitXP("castAOE","target")')
print('  UnitXP("castAOE","player")')
print('  native terrain-click entry: 0x006E60F0')
print('  background polling/hooks: none')
