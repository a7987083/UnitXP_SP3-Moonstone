from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "iosruntimepatchmenu" / "src"
MENU = SRC / "ZonoeRuntimeMenu.mm"

text = MENU.read_text(encoding="utf-8")
original = text

# 1) Remove the complete legacy V049 Shared-Site Probe UI layer. This block is
# uniquely bounded by its import/comment and the V053 current-UI marker.
start_marker = '#import "ZNSharedSiteProbe.h"\n\n// v0.4.9 Shared-Site Probe.'
end_marker = '// v0.5.5 current UI layer.'
start = text.find(start_marker)
if start >= 0:
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit("V049 end marker not found")
    text = text[:start] + '// v0.4.9 game-specific probe layer removed by M5.10.5 Offset cleanup.\n\n' + text[end:]

# 2) Remove the residual probe section embedded directly in the current V053
# Debug renderer. Keep the generic target+offset+patch validation section.
probe_anchor = '    ZNSharedSiteProbe *probe = [ZNSharedSiteProbe sharedProbe];\n'
anchor = text.find(probe_anchor)
if anchor >= 0:
    block_start = text.rfind('    y = MAX(CGRectGetHeight(self.contentView.frame), CGRectGetHeight(self.contentScroll.bounds)) + 4.0;\n', 0, anchor)
    if block_start < 0:
        raise SystemExit("V053 probe block start not found")
    block_end_marker = '    [self zn40_updateContentHeight:y];\n'
    block_end = text.find(block_end_marker, anchor)
    if block_end < 0:
        raise SystemExit("V053 probe block end not found")
    block_end += len(block_end_marker)
    text = text[:block_start] + text[block_end:]

# Remove purely historical display wording left in comments/footer text. Actual
# executable references are verified separately below.
text = text.replace('Shared-Site Probe', 'removed legacy probe')
text = text.replace('shared-site probe', 'removed legacy probe')

# The active consolidated menu must no longer contain any game-specific probe
# symbol, selector, fixed address, or sample identity after transformation.
for forbidden in (
    'ZNSharedSiteProbe',
    'MdhpNuX',
    '0x2E25904',
    '0x2E1BCA0',
    '0x2E257E4',
    'Posters(5)',
    'Prestige(10)',
    'zn49_toggleSharedSiteProbe',
    'zn49_snapshotSharedSiteProbe',
    'zn49_clearSharedSiteProbe',
    'zn49_copySharedSiteProbe',
    'ZNInstallV049SharedSiteProbeUI',
):
    if forbidden in text:
        raise SystemExit(f"forbidden legacy probe residue remains in menu: {forbidden}")

if text != original:
    MENU.write_text(text, encoding="utf-8")

# 3) Physically delete the legacy probe implementation/header files. They are
# outside the M5.10 Offset Core and are not part of Runtime Method / IL2CPP.
for name in (
    'ZNSharedSiteProbe.h',
    'ZNSharedSiteProbeV2.mm',
    'ZNSharedSiteExecutionProbeV3.h',
    'ZNSharedSiteExecutionProbeV3.mm',
    'ZNSharedSiteExecutionProbeV3Bootstrap.mm',
):
    path = SRC / name
    if path.exists():
        path.unlink()

print('M5.10.5 final Offset cleanup applied')
