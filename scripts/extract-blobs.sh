#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# extract-blobs.sh
#
# Extracts the proprietary blobs listed in
# device/ayaneo/pocket_ds/proprietary-files.txt from the stock firmware and
# regenerates the vendor makefiles under vendor/ayaneo/pocket_ds/.
#
#   1. Dumps the stock logical partitions (ext4 images produced by
#      unpack-super.sh) into plain directories with debugfs. No root or loop
#      mounts are needed.
#   2. Runs the LineageOS extract-utils based
#      device/ayaneo/pocket_ds/extract-files.py on that dump.
#
# Requires a synced LineageOS tree (tools/extract-utils) and e2fsprogs.
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PARTITIONS_DIR="${PROJECT_ROOT}/stock-firmware/unpacked/partitions"
DUMP_DIR="${PROJECT_ROOT}/stock-firmware/extracted"
DEVICE_DIR="${PROJECT_ROOT}/device/ayaneo/pocket_ds"
SLOT="a"
EXTRACT_ARGS=()

usage() {
    cat <<USAGE
Usage: $(basename "$0") [OPTIONS] [-- EXTRACT_FILES_ARGS...]

Options:
  --partitions-dir <path>  Stock partition images (default: stock-firmware/unpacked/partitions)
  --dump-dir <path>        Where to dump partition contents (default: stock-firmware/extracted)
  --slot <a|b>             Slot suffix of the images to read (default: a)
  --redump                 Delete and recreate the partition dump
  --help                   Show this help

Anything after -- is passed to extract-files.py (for example
--regenerate_makefiles to only rewrite the makefiles).
USAGE
}

REDUMP=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --partitions-dir) PARTITIONS_DIR="$2"; shift 2 ;;
        --dump-dir)       DUMP_DIR="$2"; shift 2 ;;
        --slot)           SLOT="$2"; shift 2 ;;
        --redump)         REDUMP=true; shift ;;
        --help)           usage; exit 0 ;;
        --)               shift; EXTRACT_ARGS=("$@"); break ;;
        *)                echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

command -v debugfs >/dev/null || { echo "debugfs (e2fsprogs) is required" >&2; exit 1; }
[[ -d "${PROJECT_ROOT}/tools/extract-utils" ]] || {
    echo "tools/extract-utils not found; sync the LineageOS tree first" >&2
    exit 1
}

for part in system system_ext product vendor odm; do
    img="${PARTITIONS_DIR}/${part}_${SLOT}.img"
    out="${DUMP_DIR}/${part}"
    [[ -f "$img" ]] || { echo "Missing partition image: $img (run unpack-super.sh)" >&2; exit 1; }
    if [[ "$REDUMP" == true ]]; then
        rm -rf "$out"
    fi
    if [[ ! -d "$out" ]]; then
        echo "Dumping ${part}_${SLOT}.img -> ${out}"
        mkdir -p "$out"
        # debugfs reports chown failures when run unprivileged; ownership is
        # irrelevant for blob extraction.
        debugfs -R "rdump / ${out}" "$img" >/dev/null 2>&1
    fi
done

# extract-utils expects system files under <dump>/system/..., which matches
# the system-as-root layout of the stock system image.
cd "$DEVICE_DIR"
exec ./extract-files.py "${EXTRACT_ARGS[@]}" "$DUMP_DIR"
