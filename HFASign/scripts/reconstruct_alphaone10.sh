#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${ROOT_DIR}/HFASignBuild"
HFASIGN_DIR="${ROOT_DIR}/HFASign"
SERIES_FILE="${HFASIGN_DIR}/patch-series-alphaone10.txt"
UPSTREAM_URL="https://github.com/Nyasami/Ksign.git"
UPSTREAM_COMMIT="03a3a9c86897d79f9faf8106037b9971841d56a0"

rm -rf "${BUILD_DIR}"
git clone "${UPSTREAM_URL}" "${BUILD_DIR}"
git -C "${BUILD_DIR}" checkout "${UPSTREAM_COMMIT}"

while IFS= read -r patch_name || [[ -n "${patch_name}" ]]; do
    [[ -z "${patch_name}" ]] && continue
    [[ "${patch_name}" == \#* ]] && continue

    patch_path="${HFASIGN_DIR}/patches/${patch_name}"
    if [[ ! -f "${patch_path}" ]]; then
        echo "Missing patch from canonical series: ${patch_name}" >&2
        exit 1
    fi

    echo "Applying ${patch_name}"
    git -C "${BUILD_DIR}" apply "${patch_path}"
done < "${SERIES_FILE}"

python3 "${HFASIGN_DIR}/scripts/apply_alphaone10_udid_reliability.py"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone10_udid_fixed_port_hotfix.py"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone11_source_notice_urlscheme.py"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone12_features.py"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone13_source_ui_cleanup.py"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone13_source_ux_compilefix.py"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone13_ios13_compat.py"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone14_signing_inbox_fixes.py"

git -C "${BUILD_DIR}" diff --check
git -C "${BUILD_DIR}" submodule update --init --recursive

# IDeviceKit's wrapper manifest pins iOS 15 even though its binary IDevice
# dependency supports iOS 12. Keep zonoe's established iOS 13 deployment target
# by lowering only the locally reconstructed wrapper package; do not rewrite the
# pinned submodule commit or dependency version.
python3 - "${BUILD_DIR}/IDeviceKit/Package.swift" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = ".iOS(.v15)"
new = ".iOS(.v13)"
count = text.count(old)
if count != 1:
    raise SystemExit(f"IDeviceKit iOS13 compat: expected one {old}, found {count}")
path.write_text(text.replace(old, new, 1))
PY

grep -Fq '.iOS(.v13)' "${BUILD_DIR}/IDeviceKit/Package.swift"
git -C "${BUILD_DIR}/IDeviceKit" diff --check

git -C "${BUILD_DIR}/Zsign" apply "${HFASIGN_DIR}/patches/0017-Fix-Zsign-removeProvision-semantics.patch"

echo "Reconstructed zonoe v3.0.0-alphaone14 from frozen alphaone10 baseline + additive alphaone11/alphaone12/alphaone13/alphaone14 transforms + iOS 13 compatibility"
