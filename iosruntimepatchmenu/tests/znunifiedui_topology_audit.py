#!/usr/bin/env python3
import argparse, collections, hashlib, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "iosruntimepatchmenu/src/ZNUnifiedUI.mm"
SPLIT_MODULES = [
    ROOT / "iosruntimepatchmenu/src/ZNRangeControl.mm",
    ROOT / "iosruntimepatchmenu/src/ZNM55StaticTypedBinding.mm",
    ROOT / "iosruntimepatchmenu/src/ZNM56StaticValueCellBinding.mm",
]
BASELINE = ROOT / "iosruntimepatchmenu/tests/znunifiedui_topology_baseline.json"

def collect(text: str):
    implementations = re.findall(r"@implementation\s+([A-Za-z0-9_]+)", text)
    selectors = re.findall(r"@selector\s*\(\s*([A-Za-z0-9_:]+)\s*\)", text)
    stages = re.findall(r'ZNRunActivationStage\(@"([^"]+)"\s*,\s*\^\{\s*ZN[A-Za-z0-9_]+\(\);\s*\}\s*\);', text)
    return {
        "newline_count": text.count("\n"),
        "implementation_count": len(implementations),
        "implementation_frequency": dict(sorted(collections.Counter(implementations).items())),
        "method_exchange_implementations_count": len(re.findall(r"\bmethod_exchangeImplementations\s*\(", text)),
        "method_set_implementation_count": len(re.findall(r"\bmethod_setImplementation\s*\(", text)),
        "dispatch_once_count": len(re.findall(r"\bdispatch_once\s*\(", text)),
        "selector_counts": dict(sorted(collections.Counter(selectors).items())),
        "activation_stage_order": stages,
        "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
    }

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", help="write complete observed topology JSON")
    args = ap.parse_args()
    source_paths = [SOURCE] + [p for p in SPLIT_MODULES if p.exists()]
    texts = [SOURCE.read_text(encoding="utf-8")]
    for p in source_paths[1:]:
        module_text = p.read_text(encoding="utf-8")
        begin = f"#pragma mark - BEGIN {p.name}"
        end = f"#pragma mark - END {p.name}"
        a = module_text.index(begin)
        b0 = module_text.index(end, a)
        b = module_text.find("\n", b0)
        b = len(module_text) if b < 0 else b + 1
        texts.append(module_text[a:b])
    text = "".join(texts)
    observed = collect(text)
    observed["source_files"] = [str(p.relative_to(ROOT)) for p in source_paths]
    expected = json.loads(BASELINE.read_text(encoding="utf-8"))

    failures = []
    scalar_keys = [
        "newline_count", "implementation_count",
        "method_exchange_implementations_count",
        "method_set_implementation_count", "dispatch_once_count"
    ]
    for key in scalar_keys:
        if observed[key] != expected[key]:
            failures.append(f"{key}: expected {expected[key]!r}, got {observed[key]!r}")

    if observed["implementation_frequency"] != expected["implementation_frequency"]:
        failures.append("implementation_frequency changed")

    for selector, want in expected["critical_selector_counts"].items():
        got = observed["selector_counts"].get(selector, 0)
        if got != want:
            failures.append(f"selector {selector}: expected {want}, got {got}")

    if observed["activation_stage_order"] != expected["activation_stage_order"]:
        failures.append(
            "activation_stage_order changed:\n  expected="
            + repr(expected["activation_stage_order"])
            + "\n  got=" + repr(observed["activation_stage_order"])
        )

    report = {
        "baseline_commit": expected["baseline_commit"],
        "source": str(SOURCE.relative_to(ROOT)),
        "source_files": observed["source_files"],
        "observed": observed,
        "status": "FAIL" if failures else "PASS",
        "failures": failures,
    }
    if args.report:
        pathlib.Path(args.report).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(json.dumps({
        "status": report["status"],
        "newline_count": observed["newline_count"],
        "implementation_count": observed["implementation_count"],
        "method_exchange_implementations_count": observed["method_exchange_implementations_count"],
        "method_set_implementation_count": observed["method_set_implementation_count"],
        "dispatch_once_count": observed["dispatch_once_count"],
        "activation_stage_order": observed["activation_stage_order"],
        "failures": failures,
    }, indent=2, ensure_ascii=False))
    if failures:
        print("\nZNUnifiedUI topology drift detected. Update the baseline only after explicit behavioral review.", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
