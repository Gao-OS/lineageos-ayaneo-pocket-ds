#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# extract-blobs.sh
#
# Reads device/ayaneo/pocket_ds/proprietary-files.txt, copies listed blobs
# from mounted partition images, generates vendor makefiles and a SHA256
# manifest.
# ---------------------------------------------------------------------------

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Defaults ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SYSTEM_DIR=""
VENDOR_DIR=""
PRODUCT_DIR=""
SYSTEM_EXT_DIR=""
ODM_DIR=""
OUTPUT_DIR="${PROJECT_ROOT}/vendor/ayaneo/pocket_ds"
PROPRIETARY_FILES="${PROJECT_ROOT}/device/ayaneo/pocket_ds/proprietary-files.txt"

# ── Usage ──────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Extract proprietary blobs from mounted partition images based on
device/ayaneo/pocket_ds/proprietary-files.txt.

${BOLD}Required:${RESET}
  --system <path>        Mount point of system partition
  --vendor <path>        Mount point of vendor partition
  --product <path>       Mount point of product partition
  --system-ext <path>    Mount point of system_ext partition
  --odm <path>           Mount point of odm partition

${BOLD}Options:${RESET}
  --output-dir <path>    Output directory for extracted blobs and makefiles
                         (default: vendor/ayaneo/pocket_ds)
  --help                 Show this help message and exit
EOF
}

# ── Argument Parsing ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)      SYSTEM_DIR="$2";     shift 2 ;;
        --vendor)      VENDOR_DIR="$2";     shift 2 ;;
        --product)     PRODUCT_DIR="$2";    shift 2 ;;
        --system-ext)  SYSTEM_EXT_DIR="$2"; shift 2 ;;
        --odm)         ODM_DIR="$2";        shift 2 ;;
        --output-dir)  OUTPUT_DIR="$2";     shift 2 ;;
        --help)        usage; exit 0                ;;
        *)
            echo -e "${RED}Error:${RESET} Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# ── Dependency Checks ─────────────────────────────────────────────────────
MISSING=()
for cmd in sha256sum cp mkdir find; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}Error:${RESET} Missing required tools: ${MISSING[*]}" >&2
    exit 1
fi

# ── Validate Required Arguments ────────────────────────────────────────────
error=false
for arg_name in SYSTEM_DIR VENDOR_DIR PRODUCT_DIR SYSTEM_EXT_DIR ODM_DIR; do
    if [[ -z "${!arg_name}" ]]; then
        echo -e "${RED}Error:${RESET} --${arg_name,,} is required (use _ as - in flag names)." >&2
        error=true
    fi
done
# More helpful error for the flag names
if [[ "$error" == true ]]; then
    echo "" >&2
    echo "Required flags: --system, --vendor, --product, --system-ext, --odm" >&2
    exit 1
fi

for dir_var in SYSTEM_DIR VENDOR_DIR PRODUCT_DIR SYSTEM_EXT_DIR ODM_DIR; do
    dir_val="${!dir_var}"
    if [[ ! -d "$dir_val" ]]; then
        echo -e "${RED}Error:${RESET} Directory does not exist: ${dir_val} (${dir_var})" >&2
        error=true
    fi
done
if [[ "$error" == true ]]; then
    exit 1
fi

# ── Validate Proprietary Files List ───────────────────────────────────────
if [[ ! -f "$PROPRIETARY_FILES" ]]; then
    echo -e "${RED}Error:${RESET} proprietary-files.txt not found at ${PROPRIETARY_FILES}" >&2
    exit 1
fi

# ── Prepare Output ────────────────────────────────────────────────────────
PROPRIETARY_DIR="${OUTPUT_DIR}/proprietary"
mkdir -p "${PROPRIETARY_DIR}"

# ── Resolve Partition for a File Path ─────────────────────────────────────
# proprietary-files.txt entries look like:
#   vendor/lib64/libfoo.so        → vendor partition
#   system/app/Foo/Foo.apk        → system partition
#   system_ext/priv-app/Bar.apk   → system_ext partition
#   product/etc/foo.xml           → product partition
#   odm/lib64/libbar.so           → odm partition
#   lib64/libfoo.so               → system partition (no prefix = system)
resolve_source() {
    local entry="$1"
    local partition=""
    local rel_path=""

    case "$entry" in
        system/*)     partition="$SYSTEM_DIR";     rel_path="${entry#system/}" ;;
        vendor/*)     partition="$VENDOR_DIR";     rel_path="${entry#vendor/}" ;;
        product/*)    partition="$PRODUCT_DIR";    rel_path="${entry#product/}" ;;
        system_ext/*) partition="$SYSTEM_EXT_DIR"; rel_path="${entry#system_ext/}" ;;
        odm/*)        partition="$ODM_DIR";        rel_path="${entry#odm/}" ;;
        *)            partition="$SYSTEM_DIR";     rel_path="${entry}" ;;
    esac

    echo "${partition}/${rel_path}"
}

# ── Extract Blobs ─────────────────────────────────────────────────────────
echo -e "${CYAN}Extracting proprietary blobs…${RESET}"
echo ""

copied=0
skipped=0
missing=0
COPY_FILES_ENTRIES=()

while IFS= read -r line; do
    # Skip empty lines and comments
    line="$(echo "$line" | sed 's/#.*//' | xargs)"
    [[ -z "$line" ]] && continue

    # Handle lines with optional leading dash (means optional/not fatal)
    optional=false
    if [[ "$line" == -* ]]; then
        optional=true
        line="${line#-}"
    fi

    # Resolve source path
    src="$(resolve_source "$line")"

    # Determine destination
    case "$line" in
        system/*|vendor/*|product/*|system_ext/*|odm/*)
            dest_rel="$line"
            ;;
        *)
            dest_rel="system/${line}"
            ;;
    esac
    dest="${PROPRIETARY_DIR}/${dest_rel}"

    # Idempotent: skip if already extracted
    if [[ -f "$dest" ]]; then
        ((skipped++)) || true
        continue
    fi

    if [[ ! -f "$src" ]]; then
        if $optional; then
            echo -e "  ${YELLOW}Optional:${RESET} ${line} (not found, skipping)"
        else
            echo -e "  ${RED}Missing:${RESET}  ${line}"
        fi
        ((missing++)) || true
        continue
    fi

    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    echo -e "  ${GREEN}Copied:${RESET}   ${line}"
    ((copied++)) || true

    # Record for PRODUCT_COPY_FILES
    COPY_FILES_ENTRIES+=("${dest_rel}")

done < "$PROPRIETARY_FILES"

echo ""
echo -e "${BOLD}Extraction:${RESET} ${GREEN}${copied} copied${RESET}, ${YELLOW}${skipped} skipped (already exist)${RESET}, ${RED}${missing} missing${RESET}"

# ── Collect All Extracted Files for Makefiles ─────────────────────────────
# Include previously extracted files too (idempotent runs)
ALL_FILES=()
if [[ -d "$PROPRIETARY_DIR" ]]; then
    while IFS= read -r -d '' f; do
        rel="${f#"${PROPRIETARY_DIR}"/}"
        ALL_FILES+=("$rel")
    done < <(find "$PROPRIETARY_DIR" -type f -print0 | sort -z)
fi

# ── Generate vendor.mk ───────────────────────────────────────────────────
VENDOR_MK="${OUTPUT_DIR}/vendor.mk"
echo -e "${CYAN}Generating${RESET} ${VENDOR_MK}"

{
    cat <<'HEADER'
# Auto-generated by extract-blobs.sh — do not edit manually.
#
# Copyright (C) The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

PRODUCT_SOONG_NAMESPACES += \
    vendor/ayaneo/pocket_ds

HEADER

    if [[ ${#ALL_FILES[@]} -gt 0 ]]; then
        echo "PRODUCT_COPY_FILES += \\"
        last_idx=$(( ${#ALL_FILES[@]} - 1 ))
        for i in "${!ALL_FILES[@]}"; do
            entry="${ALL_FILES[$i]}"
            # Target path: strip partition prefix for the install location
            src_path="vendor/ayaneo/pocket_ds/proprietary/${entry}"
            partition="${entry%%/*}"
            # Android build uses uppercase TARGET_COPY_OUT_* variables
            partition_upper="$(echo "$partition" | tr '[:lower:]' '[:upper:]')"
            if [[ $i -eq $last_idx ]]; then
                echo "    ${src_path}:\$(TARGET_COPY_OUT_${partition_upper})/${entry#*/}"
            else
                echo "    ${src_path}:\$(TARGET_COPY_OUT_${partition_upper})/${entry#*/} \\"
            fi
        done
    fi
    echo ""
} > "${VENDOR_MK}"
echo -e "  ${GREEN}Done.${RESET}"

# ── Generate BoardConfigVendor.mk ────────────────────────────────────────
BOARD_MK="${OUTPUT_DIR}/BoardConfigVendor.mk"
echo -e "${CYAN}Generating${RESET} ${BOARD_MK}"

cat > "${BOARD_MK}" <<'EOF'
# Auto-generated by extract-blobs.sh — do not edit manually.
#
# Copyright (C) The LineageOS Project
# SPDX-License-Identifier: Apache-2.0

LOCAL_PATH := $(call my-dir)

# Vendor board configuration flags can be added below.
EOF
echo -e "  ${GREEN}Done.${RESET}"

# ── Generate SHA256 Manifest ─────────────────────────────────────────────
MANIFEST="${OUTPUT_DIR}/proprietary-sha256.txt"
echo -e "${CYAN}Generating SHA256 manifest${RESET} → ${MANIFEST}"

if [[ ${#ALL_FILES[@]} -gt 0 ]]; then
    (
        cd "${PROPRIETARY_DIR}"
        sha256sum "${ALL_FILES[@]}" 2>/dev/null || true
    ) > "${MANIFEST}"
    line_count="$(wc -l < "${MANIFEST}")"
    echo -e "  ${GREEN}Done.${RESET} ${line_count} entries."
else
    echo "# No blobs extracted." > "${MANIFEST}"
    echo -e "  ${YELLOW}No blobs to hash.${RESET}"
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══ Summary ═══${RESET}"
echo -e "  Proprietary blobs: ${PROPRIETARY_DIR}/"
echo -e "  vendor.mk:         ${VENDOR_MK}"
echo -e "  BoardConfig:       ${BOARD_MK}"
echo -e "  SHA256 manifest:   ${MANIFEST}"
echo ""
echo -e "${GREEN}All done.${RESET}"
