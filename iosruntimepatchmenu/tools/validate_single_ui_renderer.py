#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "iosruntimepatchmenu"
MAKEFILE = PROJECT / "Makefile"
MENU_BINDING = PROJECT / "src/ZNIL2CPPMethodFinderMenuBinding.mm"
DEFERRED_BOOTSTRAP = PROJECT / "src/ZNDeferredBootstrap.mm"
RUNTIME_BOOTSTRAP = PROJECT / "src/ZNRuntimeMethodCallBootstrap.mm"
BUILDER = PROJECT / "src/ZNM641UnifiedAuthoringRenderer.mm"
CANONICAL_FILE = "ZNM641UnifiedClientRenderer.mm"
CANONICAL_MARKER = "ZN_UI_CANONICAL_FEATURE_RENDERER"
CANONICAL_INSTALL = "ZNInstallM641UnifiedClientRendererDeferred();"

FORBIDDEN_ACTIVE_INSTALLERS = (
    "ZNInstallFeatureGroupUIDeferred();",
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
    "ZNInstallM630SingleUnifiedRendererDeferred();",
)

PROTECTED_SELECTORS = (
    "renderFullPage",
    "renderCompactPage",
    "zn51_renderRuntime:",
    "zn50b_renderOther",
    "renderPage",
)


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


def active_call(text: str, installer: str) -> bool:
    return bool(re.search(rf"(?<!void\s){re.escape(installer)}", text))


def main() -> int:
    sources = compiled_sources()
    contents = {p: p.read_text(encoding="utf-8", errors="replace") for p in sources}
    errors: list[str] = []

    canonical = [p for p, text in contents.items() if CANONICAL_MARKER in text]
    if len(canonical) != 1:
        errors.append(f"expected exactly one compiled canonical Feature renderer marked {CANONICAL_MARKER}; found {len(canonical)}: {[rel(p) for p in canonical]}")
    elif canonical[0].name != CANONICAL_FILE:
        errors.append(f"unexpected canonical renderer owner: {rel(canonical[0])}")

    binding = MENU_BINDING.read_text(encoding="utf-8")
    if binding.count(CANONICAL_INSTALL) != 1:
        errors.append(f"canonical renderer must be installed exactly once via {CANONICAL_INSTALL}")

    bootstrap = DEFERRED_BOOTSTRAP.read_text(encoding="utf-8")
    for installer in FORBIDDEN_ACTIVE_INSTALLERS:
        if active_call(binding, installer) or active_call(bootstrap, installer):
            errors.append(f"forbidden layered UI installer is active: {installer}")

    runtime_bootstrap = RUNTIME_BOOTSTRAP.read_text(encoding="utf-8")
    if re.search(r"(?<!void\s)ZNInstallRuntimeMethodCallBuilderUIDeferred\(\);", runtime_bootstrap):
        errors.append("RuntimeMethodCallBootstrap still activates the historical second Builder renderer")

    if BUILDER not in sources:
        errors.append(f"canonical Builder is not compiled: {rel(BUILDER)}")
    builder = BUILDER.read_text(encoding="utf-8")
    required_builder_markers = (
        "M6.4.1 canonical authoring renderer",
        "Backend 与控件独立",
        "Runtime Method",
        "Static Patch",
        "Patch HEX",
        "＋ 增加功能",
    )
    for marker in required_builder_markers:
        if marker not in builder:
            errors.append(f"canonical Builder is missing marker: {marker}")

    if any(p.name == "ZNM630UnifiedAuthoringRenderer.mm" for p in sources):
        errors.append("M6.3/M6.4 authoring renderer must not be compiled")
    if any(p.name == "ZNM630SingleUnifiedRenderer.mm" for p in sources):
        errors.append("M6.3 client renderer must not be compiled")
    if any(p.name == "ZNM620UnifiedAuthoringUI.mm" for p in sources):
        errors.append("ZNM620UnifiedAuthoringUI.mm must not be compiled")
    if any(p.name == "ZNFeatureBuilderUI.mm" for p in sources):
        errors.append("legacy ZNFeatureBuilderUI.mm must not be compiled")

    client = PROJECT / "src" / CANONICAL_FILE
    if client not in sources:
        errors.append(f"canonical client renderer is not compiled: {rel(client)}")
    else:
        text = client.read_text(encoding="utf-8")
        required_client = (
            "one customer Feature renderer owns BOTH Static and Runtime records",
            "M641StaticFeatures",
            "M641RuntimeRecords",
            "m641_renderFeaturesCompact",
        )
        for marker in required_client:
            if marker not in text:
                errors.append(f"canonical client renderer missing marker: {marker}")

    # Constructors may not take ownership of the protected Feature surfaces.
    for path, text in contents.items():
        if "__attribute__((constructor))" not in text:
            continue
        touched = [s for s in PROTECTED_SELECTORS if f"@selector({s})" in text]
        if touched:
            errors.append(f"constructor bypasses single-renderer install chain in {rel(path)}: {touched}")

    # Backend helpers are allowed to swizzle validators/builders, but must never own UI.
    backend_helper = PROJECT / "src/ZNM641StaticControlBackend.mm"
    if backend_helper in sources:
        text = backend_helper.read_text(encoding="utf-8")
        if "UIView" in text or "renderFullPage" in text or "renderCompactPage" in text:
            errors.append("Static backend helper must remain UI-free")

    if errors:
        print("UI ARCHITECTURE CONTRACT: FAIL", file=sys.stderr)
        for item in errors:
            print(f" - {item}", file=sys.stderr)
        print("M6.4.1 requires exactly one customer renderer and one authoring renderer. Backend helpers may not render UI.", file=sys.stderr)
        return 1

    print(f"UI ARCHITECTURE CONTRACT: PASS canonical={rel(canonical[0])}; authoring={rel(BUILDER)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
