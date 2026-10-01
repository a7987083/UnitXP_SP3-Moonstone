from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "iosruntimepatchmenu" / "src"
bootstrap = SRC / "ZNDeferredBootstrap.mm"
text = bootstrap.read_text(encoding="utf-8")

for line in (
    'extern "C" void ZNInstallRuntimeExecutorV041Deferred(void);\n',
    'extern "C" void ZNInstallRuntimeDiagnosticsV042Deferred(void);\n',
    '        ZNRunActivationStage(@"RuntimeExecutorV041", ^{ ZNInstallRuntimeExecutorV041Deferred(); });\n',
    '        ZNRunActivationStage(@"RuntimeDiagnosticsV042", ^{ ZNInstallRuntimeDiagnosticsV042Deferred(); });\n',
):
    if line not in text:
        raise SystemExit(f"expected bootstrap line missing: {line.strip()}")
    text = text.replace(line, "", 1)

for forbidden in ('ZNInstallRuntimeExecutorV041Deferred', 'ZNInstallRuntimeDiagnosticsV042Deferred'):
    if forbidden in text:
        raise SystemExit(f"legacy executor bootstrap residue remains: {forbidden}")
bootstrap.write_text(text, encoding="utf-8")

for name in (
    'ZNPatchCoreV041.mm',
    'ZNRuntimePatchExecutor.h',
    'ZNRuntimePatchExecutor.mm',
    'ZNRuntimeDiagnosticsV042.mm',
):
    path = SRC / name
    if path.exists():
        path.unlink()

print('M5.10.7 legacy PatchManager executor/diagnostics swizzle chain removed')
