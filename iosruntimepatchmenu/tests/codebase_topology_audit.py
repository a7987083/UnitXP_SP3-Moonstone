#!/usr/bin/env python3
import argparse, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "iosruntimepatchmenu" / "src"
MAKEFILE = ROOT / "iosruntimepatchmenu" / "Makefile"

CONSTRUCTOR_ALLOWLIST = {
    "ZNDeferredBootstrap.mm": {("200", "ZNDeferredColdLauncherBootstrap")},
    "ZNNativeHookLifecycleBootstrap.mm": {("201", "ZNNativeHookEarlyLifecycleBootstrap")},
}

SWIZZLE_FILE_ALLOWLIST = {
    "ZNUnifiedUI.mm",
    "ZNIL2CPPMethodFinderSearchV2.mm",
    "ZNIL2CPPMethodFinderZeroVMAddrFix.mm",
    "ZNIL2CPPNamedOffsetWorkspace.mm",
    "ZNM462InstanceSafety.mm",
    "ZNM46SignatureExecution.mm",
    "ZNM47MultiArgInvoke.mm",
    "ZNM48ReturnCapture.mm",
    "ZNM50ManagedReturnChaining.mm",
    "ZNM52ChainStoreV2.mm",
    "ZNM52ImmediateChainV2.mm",
    "ZNM551AuthoringPersistence.mm",
    "ZNM592OffsetAuthoringPersistence.mm",
    "ZNOffsetResolverV2.mm",
    "ZNPatchCoreV041.mm",
    "ZNRuntimeDiagnosticsV042.mm",
    "ZNSharedSiteExecutionProbeV3Bootstrap.mm",
}

SETIMP_FILE_ALLOWLIST = {
    "ZNUnifiedUI.mm",
    "ZNSharedSiteExecutionProbeV3.mm",
    "ZNSharedSiteExecutionProbeV3Bootstrap.mm",
    "ZNSharedSiteProbeV2.mm",
}

CORE_PIPELINES = {
    "build": {
        "ZNBuildManifest.mm", "ZNBuildExecutor.mm", "ZNBuildStaticPrepare.mm",
        "ZNStaticBinaryBuilderV3.mm", "ZNRuntimeOnlyBinaryBuilder.mm",
        "ZNNativeHookBuildPrepare.mm",
    },
    "runtime": {
        "ZNRuntimeActionRuntime.mm", "ZNRuntimeArgumentMarshaller.mm",
        "ZNIL2CPPInvokeEngine.mm", "ZNDirectNativeCallEngine.mm",
    },
    "native_hook": {
        "ZNNativeHookRuntime.mm", "ZNNativeHookScheduler.mm",
        "ZNNativeHookLifecycleBootstrap.mm",
    },
}

def source_files():
    return sorted(p for p in SRC.rglob("*") if p.suffix in {".m", ".mm", ".c", ".cpp", ".h", ".hpp"})

def compiled_sources():
    text = MAKEFILE.read_text(encoding="utf-8")
    m = re.search(r"ZonoePatchV03_FILES\s*=\s*(.+)", text)
    if not m:
        return set()
    return {pathlib.Path(x).name for x in m.group(1).split()}

def collect():
    files = source_files()
    constructors = {}
    swizzle_files = {}
    setimp_files = {}
    implementations = {}
    installers = {}
    total_exchange = 0
    total_setimp = 0

    ctor_re = re.compile(
        r"__attribute__\s*\(\(\s*constructor(?:\((\d+)\))?\s*\)\)"
        r"\s*static\s+void\s+([A-Za-z0-9_]+)"
    )
    impl_re = re.compile(r"@implementation\s+([A-Za-z0-9_]+)(?:\s*\(([^)]+)\))?")
    installer_re = re.compile(
        r'(?:extern\s+"C"\s+)?(?:void|BOOL)\s+'
        r'(ZN(?:Install|Prepare|Bootstrap|Start)[A-Za-z0-9_]+)\s*\('
    )

    for path in files:
        if path.suffix not in {".m", ".mm", ".c", ".cpp"}:
            continue
        text = path.read_text(encoding="utf-8")
        name = path.name
        cs = {(prio or "", fn) for prio, fn in ctor_re.findall(text)}
        if cs:
            constructors[name] = sorted(cs)
        ex = len(re.findall(r"\bmethod_exchangeImplementations\s*\(", text))
        si = len(re.findall(r"\bmethod_setImplementation\s*\(", text))
        total_exchange += ex
        total_setimp += si
        if ex:
            swizzle_files[name] = ex
        if si:
            setimp_files[name] = si
        imps = [c + (f"({cat})" if cat else "") for c, cat in impl_re.findall(text)]
        if imps:
            implementations[name] = imps
        ins = installer_re.findall(text)
        if ins:
            installers[name] = ins

    return {
        "constructors": constructors,
        "swizzle_files": swizzle_files,
        "setimp_files": setimp_files,
        "method_exchange_total": total_exchange,
        "method_setimp_total": total_setimp,
        "implementations": implementations,
        "installers": installers,
        "compiled_sources": sorted(compiled_sources()),
    }

def validate(observed):
    failures = []

    actual_ctor = {
        f: {(p, n) for p, n in entries}
        for f, entries in observed["constructors"].items()
    }
    if actual_ctor != CONSTRUCTOR_ALLOWLIST:
        failures.append(
            "constructor topology changed: expected "
            f"{CONSTRUCTOR_ALLOWLIST!r}, got {actual_ctor!r}"
        )

    extra_swizzle = set(observed["swizzle_files"]) - SWIZZLE_FILE_ALLOWLIST
    if extra_swizzle:
        failures.append(f"new swizzle owner files: {sorted(extra_swizzle)}")

    extra_setimp = set(observed["setimp_files"]) - SETIMP_FILE_ALLOWLIST
    if extra_setimp:
        failures.append(f"new method_setImplementation owner files: {sorted(extra_setimp)}")

    compiled = set(observed["compiled_sources"])
    for domain, required in CORE_PIPELINES.items():
        missing = required - compiled
        if missing:
            failures.append(f"{domain} pipeline missing from Makefile: {sorted(missing)}")

    # These files are intentionally historical and must never silently return
    # to the production source list.
    if "ZNLegacyStaticBinaryPipeline.mm" in compiled:
        failures.append("legacy static binary pipeline is compiled into production")

    return failures

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report")
    args = ap.parse_args()

    observed = collect()
    failures = validate(observed)
    report = {
        "status": "FAIL" if failures else "PASS",
        "failures": failures,
        "observed": observed,
        "architecture": {
            "bootstrap_owners": [
                "ZNDeferredBootstrap.mm",
                "ZNNativeHookLifecycleBootstrap.mm",
            ],
            "runtime_ui_owner": "ZNUnifiedUI.mm",
            "pipelines": {k: sorted(v) for k, v in CORE_PIPELINES.items()},
        },
    }
    if args.report:
        pathlib.Path(args.report).write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    print(json.dumps({
        "status": report["status"],
        "method_exchange_total": observed["method_exchange_total"],
        "method_setimp_total": observed["method_setimp_total"],
        "constructor_files": sorted(observed["constructors"]),
        "swizzle_files": observed["swizzle_files"],
        "setimp_files": observed["setimp_files"],
        "failures": failures,
    }, indent=2, ensure_ascii=False))
    return 1 if failures else 0

if __name__ == "__main__":
    raise SystemExit(main())
