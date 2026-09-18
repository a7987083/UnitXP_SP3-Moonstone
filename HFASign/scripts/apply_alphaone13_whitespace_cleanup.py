#!/usr/bin/env python3
from pathlib import Path

ROOT = Path("HFASignBuild")
paths = [
    ROOT / "Ksign/FeatherApp.swift",
    ROOT / "Ksign/Backend/Sources/SourceRepositoryLoader.swift",
    ROOT / "Ksign/Views/Sources/SourcesView.swift",
    ROOT / "Ksign/Views/Sources/Apps/SourceAppsView.swift",
    ROOT / "Ksign/Views/Sources/Apps/DownloadButtonView.swift",
    ROOT / "Ksign/Views/Settings/URLSchemeView.swift",
]

for path in paths:
    text = path.read_text()
    cleaned = "\n".join(line.rstrip(" \t") for line in text.splitlines()) + "\n"
    path.write_text(cleaned)

print("alphaone13 trailing whitespace cleanup applied")
