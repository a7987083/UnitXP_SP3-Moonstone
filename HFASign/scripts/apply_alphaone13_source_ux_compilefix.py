#!/usr/bin/env python3
from pathlib import Path

path = Path("HFASignBuild/Ksign/Views/Sources/SourcesView.swift")
text = path.read_text()
old = "Storage.shared.addSource(url, repository: repository, id: identifier) { error in"
new = "Storage.shared.addSource(url, repository: repository) { error in"
if old not in text:
    raise SystemExit("alphaone13 compilefix: source add call not found")
text = text.replace(old, new, 1)
path.write_text(text)
print("alphaone13 source storage API compilefix applied")
