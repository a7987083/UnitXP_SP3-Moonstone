#!/usr/bin/env python3
# Compatibility wrapper for the proven B3.4 totem/group patch plus B3.7 DBC classifier.
# The original B3.4 script is pinned to the exact commit that produced the live-tested
# 735232-byte lineage, then the additive B3.7 patch is applied. This keeps the old
# scanner/source filtering unchanged while adding AutoRange.TotemInfo.

from pathlib import Path
import runpy
import sys
import urllib.request

BASE_COMMIT = "a9b7bf1b4c64ec244c2a90756a0d23d3ab3f6a9d"
BASE_URL = (
    "https://raw.githubusercontent.com/a7987083/UnitXP_SP3-Moonstone/"
    + BASE_COMMIT
    + "/tools/apply_groundprobe_b34_totem.py"
)

source = urllib.request.urlopen(BASE_URL, timeout=30).read().decode("utf-8")
exec(compile(source, "apply_groundprobe_b34_totem.base.py", "exec"), globals(), globals())

extra = Path(__file__).with_name("apply_autorange_b37_totemdbc.py")
if not extra.is_file():
    raise SystemExit(f"missing additive patch: {extra}")
runpy.run_path(str(extra), run_name="__main__")

print("GroundProbe B3.4 + AutoRange B3.7 event-totem chain: OK")
