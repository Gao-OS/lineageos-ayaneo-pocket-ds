#!/usr/bin/env bash
#
# SPDX-License-Identifier: Apache-2.0
#
# Generate vendor makefiles from proprietary-files.txt.
# Called by extract-files.sh after blob extraction.

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

setup_vendor "pocket_ds" "ayaneo" "${ANDROID_ROOT}" false

write_headers "pocket_ds" "ayaneo"
write_makefiles "${MY_DIR}/proprietary-files.txt" true
write_footers
