from pathlib import Path
import re

script = Path('.github/scripts/hfamap_v1925_dual_iosgods_json.py')
code = script.read_text()

bridge_pattern = re.compile(
    r"old_extern = 'extern void HFARegisterPatchString.*?l = replace_once\(l, old_extern, new_extern, 'add iGMM bridge declarations'\)\n",
    re.S,
)
bridge_replacement = r'''bridge_anchor = '#define M0(r,o,s) ((r(*)(id,SEL))objc_msgSend)((id)(o),sel_registerName(s))\n'
bridge_decl = (
    'extern void HFAResetIGMMFeatures(void); '
    'extern unsigned int HFAIGMMFeatureCount(void); '
    'extern void HFARegisterIGMMFeature(const char*,const char*,const char*,const char*,id,id); '
    'extern unsigned int HFAExportIGMMPackage(void);\n'
)
l = replace_once(l, bridge_anchor, bridge_decl + bridge_anchor, 'add iGMM bridge declarations')
'''
code, count = bridge_pattern.subn(lambda _m: bridge_replacement, code, count=1)
if count != 1:
    raise SystemExit(f'bridge source rewrite expected 1, got {count}')

reset_pattern = re.compile(
    r"# Reset the iGMM collector at each explicit full scan\. Legacy state remains untouched\.\n"
    r"pattern = r'\(static unsigned int run_full_scan.*?reset iGMM feature collector per scan'\)\n",
    re.S,
)
reset_replacement = r'''# Reset the iGMM collector at each explicit full scan. Legacy state remains untouched.
l = replace_once(
    l,
    'static unsigned int run_full_scan(void){',
    'static unsigned int run_full_scan(void){HFAResetIGMMFeatures();',
    'reset iGMM feature collector per scan',
)
'''
code, count = reset_pattern.subn(lambda _m: reset_replacement, code, count=1)
if count != 1:
    raise SystemExit(f'reset source rewrite expected 1, got {count}')

exec(compile(code, str(script), 'exec'), {'__name__': '__main__'})
