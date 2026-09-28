#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "iosruntimepatchmenu"
MAKEFILE = PROJECT / "Makefile"
MENU_BINDING = PROJECT / "src/ZNIL2CPPMethodFinderMenuBinding.mm"
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

PROTECTED_SELECTORS = (
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


def main() -> int:
    sources = compiled_sources()
    contents = {p: p.read_text(encoding="utf-8", errors="replace") for p in sources}
    errors: list[str] = []

    canonical = [p for p, text in contents.items() if CANONICAL_MARKER in text]
    if len(canonical) != 1:
        errors.append(
            f"expected exactly one compiled canonical Feature renderer marked {CANONICAL_MARKER}; "
            f"found {len(canonical)}: {[rel(p) for p in canonical]}"
        )
    elif canonical[0].name != "ZNM630SingleUnifiedRenderer.mm":
        errors.append(f"unexpected canonical renderer owner: {rel(canonical[0])}")

    binding = MENU_BINDING.read_text(encoding="utf-8")
    if binding.count(CANONICAL_INSTALL) != 1:
        errors.append(f"canonical renderer must be installed exactly once via {CANONICAL_INSTALL}")

    for installer in FORBIDDEN_ACTIVE_INSTALLERS:
        # Declarations are allowed; active call inside the installer body is not.
        active = re.findall(rf"(?<!void\s){re.escape(installer)}", binding)
        if active:
            errors.append(f"forbidden layered UI installer is active in menu binding: {installer}")

    # A constructor can bypass the explicit install chain. Any compiled file that
    # both auto-installs and touches protected Feature selectors is release-blocking.
    for path, text in contents.items():
        if "__attribute__((constructor))" not in text:
            continue
        touched = [s for s in PROTECTED_SELECTORS if f"@selector({s})" in text]
        if touched:
            errors.append(f"constructor bypasses single-renderer install chain in {rel(path)}: {touched}")

    # M6.2's post-processing source must not be compiled because it has a constructor.
    if any(p.name == "ZNM620UnifiedAuthoringUI.mm" for p in sources):
        errors.append("ZNM620UnifiedAuthoringUI.mm must not be compiled in M6.3")

    if errors:
        print("UI ARCHITECTURE CONTRACT: FAIL", file=sys.stderr)
        for item in errors:
            print(f" - {item}", file=sys.stderr)
        print("Collapse the active Feature UI to the canonical renderer; do not add a post-processing layer.", file=sys.stderr)
        return 1

    print(f"UI ARCHITECTURE CONTRACT: PASS canonical={rel(canonical[0])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
