#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "iosruntimepatchmenu"
MAKEFILE = PROJECT / "Makefile"
MENU_BINDING = PROJECT / "src/ZNIL2CPPMethodFinderMenuBinding.mm"
RUNTIME_BOOTSTRAP = PROJECT / "src/ZNRuntimeMethodCallBootstrap.mm"
BUILDER = PROJECT / "src/ZNM630UnifiedAuthoringRenderer.mm"
CANONICAL_MARKER = "ZN_UI_CANONICAL_FEATURE_RENDERER"
CANONICAL_INSTALL = "ZNInstallM630SingleUnifiedRendererDeferred();"

FORBIDDEN_ACTIVE_INSTALLERS = (
    "ZNInstallFeatureRuntimeControlsV2Deferred();",
    "ZNInstallFeatureBuilderControlsV2Deferred();",
    "ZNInstallRuntimeMethodCallBuilderUIDeferred();",
    "ZNInstallM58UnifiedControlRuntimeDeferred();",
    "ZNInstallM584SchemeALayoutDeferred();",
    "ZNInstallM585UnifiedControlSemanticsDeferred();",
    "ZNInstallM585StaticRuntimeRangeDeferred();",
    "ZNInstallM590UnifiedActionModelDeferred();",
    "ZNInstallM591OffsetHookControlsDeferred();",
    "ZNInstallM600UnifiedFeatureSurfaceDeferred();",
    "ZNInstallM620UnifiedAuthoringUIDeferred();",
)

PROTECTED_SELECTORS = ("zn51_renderRuntime:", "zn50b_renderOther", "renderPage")


def compiled_sources() -> list[Path]:
    text = MAKEFILE.read_text(encoding="utf-8")
    match = re.search(r"^ZonoePatchV03_FILES\s*=\s*(.+)$", text, re.MULTILINE)
    if not match:
        raise SystemExit("UI-CONTRACT: cannot parse ZonoePatchV03_FILES from Makefile")
    out: list[Path] = []
    for token in match.group(1).split():
        if token.endswith((".m", ".mm")):
            p = PROJECT / token
            if p.exists():
                out.append(p)
    return out


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def main() -> int:
    sources = compiled_sources()
    contents = {p: p.read_text(encoding="utf-8", errors="replace") for p in sources}
    errors: list[str] = []

    canonical = [p for p, text in contents.items() if CANONICAL_MARKER in text]
    if len(canonical) != 1:
        errors.append(f"expected exactly one compiled canonical Feature renderer marked {CANONICAL_MARKER}; found {len(canonical)}: {[rel(p) for p in canonical]}")
    elif canonical[0].name != "ZNM630SingleUnifiedRenderer.mm":
        errors.append(f"unexpected canonical renderer owner: {rel(canonical[0])}")

    binding = MENU_BINDING.read_text(encoding="utf-8")
    if binding.count(CANONICAL_INSTALL) != 1:
        errors.append(f"canonical renderer must be installed exactly once via {CANONICAL_INSTALL}")
    for installer in FORBIDDEN_ACTIVE_INSTALLERS:
        if re.findall(rf"(?<!void\s){re.escape(installer)}", binding):
            errors.append(f"forbidden layered UI installer is active in menu binding: {installer}")

    bootstrap = RUNTIME_BOOTSTRAP.read_text(encoding="utf-8")
    if re.search(r"(?<!void\s)ZNInstallRuntimeMethodCallBuilderUIDeferred\(\);", bootstrap):
        errors.append("RuntimeMethodCallBootstrap still activates the historical second Builder renderer")

    if BUILDER not in sources:
        errors.append(f"canonical Builder is not compiled: {rel(BUILDER)}")
    builder = BUILDER.read_text(encoding="utf-8")
    required_builder_markers = (
        "M6.4 canonical authoring renderer",
        "single Builder renderer installed",
        "二进制",
        "M640PlaceholderRow",
        "Fixed Value restored",
        "exact IL2CPP Method Offset",
    )
    for marker in required_builder_markers:
        if marker not in builder:
            errors.append(f"canonical Builder is missing marker: {marker}")

    forbidden_builder_patterns = {
        'raw ARM64 HEX field': 'placeholder:@"ARM64 HEX"',
        'multi-Patch creation button': 'zn40_button:@"＋ 增加 Patch"',
        'Enabled raw patch label': 'label:@"Enabled"',
    }
    for label, pattern in forbidden_builder_patterns.items():
        if pattern in builder:
            errors.append(f"canonical Builder still exposes {label}")

    for path, text in contents.items():
        if "__attribute__((constructor))" not in text:
            continue
        touched = [s for s in PROTECTED_SELECTORS if f"@selector({s})" in text]
        if touched:
            errors.append(f"constructor bypasses single-renderer install chain in {rel(path)}: {touched}")

    if any(p.name == "ZNM620UnifiedAuthoringUI.mm" for p in sources):
        errors.append("ZNM620UnifiedAuthoringUI.mm must not be compiled")
    if any(p.name == "ZNFeatureBuilderUI.mm" for p in sources):
        errors.append("legacy ZNFeatureBuilderUI.mm must not be compiled")

    if errors:
        print("UI ARCHITECTURE CONTRACT: FAIL", file=sys.stderr)
        for item in errors:
            print(f" - {item}", file=sys.stderr)
        print("Collapse customer + authoring UI to canonical renderers; never patch UI with another post-processing layer.", file=sys.stderr)
        return 1

    print(f"UI ARCHITECTURE CONTRACT: PASS canonical={rel(canonical[0])}; authoring={rel(BUILDER)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
