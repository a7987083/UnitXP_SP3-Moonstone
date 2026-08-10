#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else "upstream")
cpp = root / "nativeM2Test.cpp"
if not cpp.is_file():
    raise SystemExit(f"missing {cpp}")

s = cpp.read_text(encoding="utf-8")

old = r'''    AutoRangePreviewSlot* slot = allocateAutoRangePreview(key);
    if (slot == nullptr) { gLastErrorStage = "autorange_slots_full"; return false; }
    const C3Vector white = {1.0f, 1.0f, 1.0f};
'''
new = r'''    // B3.8R2: VisualSet is idempotent for an already-live key. Lua may temporarily
    // lose confidence after a transient VisualMove/runtime miss while the native M2
    // is still perfectly alive. Never call createPreview() over that existing slot.
    if (AutoRangePreviewSlot* existing = findAutoRangePreview(key)) {
        existing->preview.position = position;
        existing->preview.scale = scale;
        existing->preview.yawDegrees = yawDegrees;
        applyPreviewWorldMatrix(existing->preview);
        reinterpret_cast<SetBooleanProc>(kSetActiveTimestampAddress)(existing->preview.model, 1);
        if (!existing->hidden && readField<void*>(existing->preview.model, 0x44) == nullptr)
            reinterpret_cast<SetBooleanProc>(kAttachToRenderListAddress)(existing->preview.model, 1);
        if (!existing->preview.renderReady)
            pollPreviewRenderReady(existing->preview, 0);
        ++gAutoRangeSetSuccess;
        gLastErrorStage = "autorange_set_existing";
        return true;
    }

    AutoRangePreviewSlot* slot = allocateAutoRangePreview(key);
    if (slot == nullptr) { gLastErrorStage = "autorange_slots_full"; return false; }
    const C3Vector white = {1.0f, 1.0f, 1.0f};
'''
if s.count(old) != 1:
    raise SystemExit(f"VisualSet allocation marker count={s.count(old)}")
s = s.replace(old, new, 1)

old_stats = r'''        << "|models=" << models << "|keys=" << keys
        << "|set=" << gAutoRangeSetCalls << "|setOK=" << gAutoRangeSetSuccess
        << "|move=" << gAutoRangeMoveCalls << "|hide=" << gAutoRangeHideCalls
'''
new_stats = r'''        << "|models=" << models << "|keys=" << keys
        << "|set=" << gAutoRangeSetCalls << "|setOK=" << gAutoRangeSetSuccess
        << "|setFail=" << (gAutoRangeSetCalls - gAutoRangeSetSuccess)
        << "|move=" << gAutoRangeMoveCalls << "|hide=" << gAutoRangeHideCalls
'''
if s.count(old_stats) != 1:
    raise SystemExit(f"VisualStats marker count={s.count(old_stats)}")
s = s.replace(old_stats, new_stats, 1)

cpp.write_text(s, encoding="utf-8", newline="\n")

checks = [
    "autorange_set_existing",
    "if (AutoRangePreviewSlot* existing = findAutoRangePreview(key))",
    "|setFail=",
]
final = cpp.read_text(encoding="utf-8")
for needle in checks:
    if needle not in final:
        raise SystemExit(f"postcondition failed: {needle}")
print("AutoRange B3.8R2 native VisualSet idempotent resync: OK")
