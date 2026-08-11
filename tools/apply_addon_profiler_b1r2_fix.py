#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "addonProfiler.cpp"
if not cpp.is_file():
    raise SystemExit(f"missing generated profiler source: {cpp}")

text = cpp.read_text(encoding="utf-8")

text = text.replace(
    'constexpr const char* kVersion = "AddonProfiler B1";',
    'constexpr const char* kVersion = "AddonProfiler B1R2";',
    1,
)

old = '''    const int rc = lua_sethook(L, &profilerHook, LUA_MASKCALL | LUA_MASKRET, 0);\n    if (rc != 0) {\n        gRunning = false;\n        reason = "SETHOOK_FAILED";\n        return false;\n    }\n    reason = "OK";\n    return true;\n'''

new = '''    // Lua 5.0.x lua_sethook() returns 1 on success.  Do not interpret the\n    // numeric return as a Win32-style zero-success code.  Verify the state\n    // directly so this remains robust on client forks.\n    const int rc = lua_sethook(L, &profilerHook, LUA_MASKCALL | LUA_MASKRET, 0);\n    (void)rc;\n    const int wantedMask = LUA_MASKCALL | LUA_MASKRET;\n    const lua_Hook installedHook = lua_gethook(L);\n    const int installedMask = lua_gethookmask(L);\n    if (installedHook != &profilerHook || (installedMask & wantedMask) != wantedMask) {\n        // Never leave our hook behind after a failed start verification.\n        if (installedHook == &profilerHook) {\n            lua_sethook(L, nullptr, 0, 0);\n        }\n        gRunning = false;\n        gStack.clear();\n        reason = "SETHOOK_VERIFY_FAILED";\n        return false;\n    }\n    reason = "OK";\n    return true;\n'''

if old not in text:
    raise SystemExit("B1 startProfiler block not found")
text = text.replace(old, new, 1)

# Expose the active mask in status; useful for smoke testing the exact CALL/RET hook.
needle = '        pushFieldBool(L, "hookBusy", hook != nullptr && hook != &profilerHook);\n'
addition = needle + '        pushFieldNumber(L, "hookMask", static_cast<double>(lua_gethookmask(L)));\n'
if '"hookMask"' not in text:
    if needle not in text:
        raise SystemExit("status hookBusy marker not found")
    text = text.replace(needle, addition, 1)

cpp.write_text(text, encoding="utf-8", newline="\n")

final = cpp.read_text(encoding="utf-8")
checks = [
    'AddonProfiler B1R2',
    'installedHook != &profilerHook',
    'SETHOOK_VERIFY_FAILED',
    'lua_gethookmask(L)',
    '"hookMask"',
]
for marker in checks:
    if marker not in final:
        raise SystemExit(f"postcondition failed: {marker}")

if 'if (rc != 0)' in final:
    raise SystemExit("old inverted lua_sethook return check still present")

print("AddonProfiler B1R2 sethook verification fix: OK")
