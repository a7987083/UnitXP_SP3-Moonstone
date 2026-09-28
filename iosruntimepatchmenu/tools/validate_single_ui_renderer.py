#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "iosruntimepatchmenu"
MAKEFILE = PROJECT / "Makefile"
CANONICAL_MARKER = "ZN_UI_CANONICAL_FEATURE_RENDERER"
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
    paths: list[Path] = []
    for token in match.group(1).split():
        if token.endswith((".m", ".mm")):
            path = PROJECT / token
            if path.exists():
                paths.append(path)
    return paths


def has_swizzle_for(text: str, selector: str) -> bool:
    if "method_exchangeImplementations" not in text:
        return False
    # All current wrappers eventually exchange selectors in the same translation unit,
    # either directly or through a local helper such as ZNM620SwapInstance.
    return f"@selector({selector})" in text


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def main() -> int:
    sources = compiled_sources()
    contents = {path: path.read_text(encoding="utf-8", errors="replace") for path in sources}

    canonical = [path for path, text in contents.items() if CANONICAL_MARKER in text]
    errors: list[str] = []

    if len(canonical) != 1:
        errors.append(
            f"expected exactly one compiled canonical Feature renderer marked {CANONICAL_MARKER}; "
            f"found {len(canonical)}: {[rel(p) for p in canonical]}"
        )

    canonical_path = canonical[0] if len(canonical) == 1 else None

    for selector in PROTECTED_SELECTORS:
        owners = [path for path, text in contents.items() if has_swizzle_for(text, selector)]
        if len(owners) > 1:
            errors.append(
                f"protected selector {selector} has multiple active UI swizzle owners: "
                + ", ".join(rel(p) for p in owners)
            )
        if canonical_path is not None:
            foreign = [path for path in owners if path != canonical_path]
            if foreign:
                errors.append(
                    f"protected selector {selector} is swizzled outside canonical renderer "
                    f"{rel(canonical_path)}: " + ", ".join(rel(p) for p in foreign)
                )

    # Explicitly reject the historical pattern where several milestone layers each
    # mutate the same customer Runtime surface. This is a release-blocking invariant.
    runtime_layers = []
    for path, text in contents.items():
        if "@selector(zn51_renderRuntime:)" in text and "method_exchangeImplementations" in text:
            runtime_layers.append(path)
    if len(runtime_layers) > 1:
        errors.append(
            "stacked Runtime Feature render layers are forbidden: "
            + " -> ".join(rel(p) for p in runtime_layers)
        )

    if errors:
        print("UI ARCHITECTURE CONTRACT: FAIL", file=sys.stderr)
        for item in errors:
            print(f" - {item}", file=sys.stderr)
        print(
            "Fix by collapsing customer Feature rendering into one canonical renderer; "
            "do not add another post-processing/swizzle layer.",
            file=sys.stderr,
        )
        return 1

    print(f"UI ARCHITECTURE CONTRACT: PASS canonical={rel(canonical_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
