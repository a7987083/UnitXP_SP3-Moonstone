from pathlib import Path

p = Path("hfamap/src/HFAMapLegacy.m")
s = p.read_text()
old = r'\1HFAResetIGMMFeatures();'
new = 'static unsigned int run_full_scan(void){HFAResetIGMMFeatures();'
if s.count(old) != 1:
    raise SystemExit(f"expected malformed reset marker once, found {s.count(old)}")
p.write_text(s.replace(old, new, 1))
