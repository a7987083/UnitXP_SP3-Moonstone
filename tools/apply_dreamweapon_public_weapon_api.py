#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
p = root / "dllmain.cpp"
if not p.is_file():
    raise SystemExit(f"missing required source: {p}")

text = p.read_text(encoding="utf-8-sig")

helper = r'''
static bool dreamWeaponPublicWeaponCommand(const std::string& command) {
    std::string suffix;
    const std::string officialPrefix = "MoonMarker.DreamAvatar.";
    const std::string aliasPrefix = "DreamAvatar.";
    if (command.compare(0, officialPrefix.size(), officialPrefix) == 0)
        suffix = command.substr(officialPrefix.size());
    else if (command.compare(0, aliasPrefix.size(), aliasPrefix) == 0)
        suffix = command.substr(aliasPrefix.size());
    else
        return false;

    // Public surface is intentionally limited to local weapon operations.
    return suffix == "WeaponStatus"
        || suffix == "GetTargetWeapons"
        || suffix == "GetTargetNpcWeapons"
        || suffix == "ApplyWeapon"
        || suffix == "RestoreWeapons"
        || suffix == "MaintainWeapons"
        || suffix == "SetAutoMaintainWeapons";
}

static bool dreamWeaponReceiveOnlySyncCommand(const std::string& command) {
    std::string suffix;
    const std::string officialPrefix = "MoonMarker.DreamAvatar.";
    const std::string aliasPrefix = "DreamAvatar.";
    if (command.compare(0, officialPrefix.size(), officialPrefix) == 0)
        suffix = command.substr(officialPrefix.size());
    else if (command.compare(0, aliasPrefix.size(), aliasPrefix) == 0)
        suffix = command.substr(aliasPrefix.size());
    else
        return false;

    // Receive side keeps the existing signed/timestamped/replay-protected sync path.
    // Sync.Build and Sync.BuildClear are deliberately NOT listed here and therefore
    // remain behind the normal MoonMarker guild authorization gate.
    return suffix == "Sync.Receive"
        || suffix == "Sync.Reapply"
        || suffix == "Sync.RestoreSender"
        || suffix == "Sync.RestoreAll";
}

'''

if "dreamWeaponPublicWeaponCommand" not in text:
    marker = "int __fastcall detoured_UnitXP(void* L) {"
    if text.count(marker) != 1:
        raise SystemExit(f"detoured_UnitXP marker count != 1: {text.count(marker)}")
    text = text.replace(marker, helper + marker, 1)

old = '''            // DreamAvatar.Sync.* deliberately has no guild/leader/officer gate.\n            // The packet itself is MAC-signed, timestamped, sender-bound and replay-protected.\n            if (!moonMarkerDreamAvatar::isSyncCommand(dreamAvatarCommand)\n                && !moonMarkerGuildAuth::isAuthorized(L)) {\n                return moonMarkerGuildAuth::denyAdvanced(L);\n            }\n'''
new = '''            // Unified public-weapon policy:\n            //   * local weapon operations: no guild authorization required;\n            //   * receive-side signed sync: keeps its existing no-guild-gate behavior;\n            //   * character model / glow / mount / MoonMarker advanced / Sync.Build /\n            //     Sync.BuildClear and all other DreamAvatar commands remain protected.\n            const bool dreamWeaponPublic = dreamWeaponPublicWeaponCommand(dreamAvatarCommand);\n            const bool dreamWeaponReceiveSync = dreamWeaponReceiveOnlySyncCommand(dreamAvatarCommand);\n            if (!dreamWeaponPublic && !dreamWeaponReceiveSync\n                && !moonMarkerGuildAuth::isAuthorized(L)) {\n                return moonMarkerGuildAuth::denyAdvanced(L);\n            }\n'''

if old in text:
    text = text.replace(old, new, 1)
elif new not in text:
    pattern = re.compile(
        r'\s*// DreamAvatar\.Sync\.\* deliberately has no guild/leader/officer gate\.\n'
        r'\s*// The packet itself is MAC-signed, timestamped, sender-bound and replay-protected\.\n'
        r'\s*if \(!moonMarkerDreamAvatar::isSyncCommand\(dreamAvatarCommand\)\n'
        r'\s*&& !moonMarkerGuildAuth::isAuthorized\(L\)\) \{\n'
        r'\s*return moonMarkerGuildAuth::denyAdvanced\(L\);\n'
        r'\s*\}\n'
    )
    text2, n = pattern.subn("\n" + new, text, count=1)
    if n != 1:
        raise SystemExit("DreamAvatar authorization marker not found")
    text = text2

# Hard postconditions: the public list is exact, receive-only sync remains exact,
# and the normal authorization call still exists for everything else.
required = [
    'suffix == "WeaponStatus"',
    'suffix == "GetTargetWeapons"',
    'suffix == "GetTargetNpcWeapons"',
    'suffix == "ApplyWeapon"',
    'suffix == "RestoreWeapons"',
    'suffix == "MaintainWeapons"',
    'suffix == "SetAutoMaintainWeapons"',
    'suffix == "Sync.Receive"',
    'suffix == "Sync.Reapply"',
    'suffix == "Sync.RestoreSender"',
    'suffix == "Sync.RestoreAll"',
    '!moonMarkerGuildAuth::isAuthorized(L)',
    'moonMarkerGuildAuth::denyAdvanced(L)',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"postcondition failed: missing {needle}")

# Build/send sync must not appear in either bypass helper body.
helper_start = text.index("static bool dreamWeaponPublicWeaponCommand")
handler_start = text.index("int __fastcall detoured_UnitXP", helper_start)
helper_text = text[helper_start:handler_start]
if 'suffix == "Sync.Build"' in helper_text or 'suffix == "Sync.BuildClear"' in helper_text:
    raise SystemExit("Sync.Build/BuildClear accidentally entered bypass helper")

p.write_text(text, encoding="utf-8", newline="\n")
print("DreamWeapon public weapon-only authorization bypass: OK")
print("Public: WeaponStatus/GetTargetWeapons/GetTargetNpcWeapons/ApplyWeapon/RestoreWeapons/MaintainWeapons/SetAutoMaintainWeapons")
print("Receive-only no-guild-gate: Sync.Receive/Reapply/RestoreSender/RestoreAll")
print("Protected: character/glow/mount/Sync.Build/Sync.BuildClear/all other DreamAvatar commands")
