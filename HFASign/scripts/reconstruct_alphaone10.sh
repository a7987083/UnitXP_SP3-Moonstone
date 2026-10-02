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
python3 "${HFASIGN_DIR}/scripts/apply_alphaone13_inbox_restore.py"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone13_rork_usbmux.py"

git -C "${BUILD_DIR}" diff --check
git -C "${BUILD_DIR}" submodule update --init --recursive Zsign

RORK_USBMUX_URL="https://github.com/rorkai/rork-usbmux.git"
RORK_USBMUX_COMMIT="9288f13deef5d109c96696a86892b9c54be87ebc"
rm -rf "${BUILD_DIR}/RorkUsbmux"
git clone "${RORK_USBMUX_URL}" "${BUILD_DIR}/RorkUsbmux"
git -C "${BUILD_DIR}/RorkUsbmux" checkout "${RORK_USBMUX_COMMIT}"
python3 "${HFASIGN_DIR}/scripts/apply_alphaone13_rork_package_compat.py"
git -C "${BUILD_DIR}/RorkUsbmux" diff --check

git -C "${BUILD_DIR}/Zsign" apply "${HFASIGN_DIR}/patches/0017-Fix-Zsign-removeProvision-semantics.patch"

echo "Reconstructed zonoe v3.0.0-alphaone13 from frozen alphaone10 baseline + additive alphaone11/alphaone12/alphaone13 transforms + iOS 13 compatibility + signing settings/Inbox recovery + RorkUsbmux direct-install bridge"
