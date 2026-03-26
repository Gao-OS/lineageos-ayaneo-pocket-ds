#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Extract proprietary blobs from a stock ROM dump or connected device.
# Standard LineageOS extract-files pattern.

set -euo pipefail

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [[ ! -f "${HELPER}" ]]; then
    echo "Unable to find extract_utils.sh at ${HELPER}"
    echo "Ensure you have synced LineageOS sources (repo sync)."
    exit 1
fi
# shellcheck source=/dev/null
source "${HELPER}"

# Default cleanup (removes old vendor files before re-extracting)
CLEANUP_VENDOR=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--no-cleanup) CLEANUP_VENDOR=false; shift ;;
        -k|--kang) KANG="--kang"; shift ;;
        -s|--section) SECTION="$2"; shift 2 ;;
        *) SRC="$1"; shift ;;
    esac
done

if [[ -z "${SRC:-}" ]]; then
    SRC="adb"
fi

setup_vendor "pocket_ds" "ayaneo" "${ANDROID_ROOT}" false "${CLEANUP_VENDOR}"
extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG:-}" "${SECTION:-}"

"${MY_DIR}/setup-makefiles.sh"
