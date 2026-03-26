#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# catalog-blobs.sh
#
# Catalogs proprietary blobs from mounted stock partitions (or adb-connected
# device) and generates a verified proprietary-files.txt for LineageOS.
#
# This script is designed to run:
#   1. On a host with stock partitions mounted (via unpack-super.sh --mount)
#   2. On a host connected to the device via ADB (adb root required)
#
# Stock partition images use inline encryption (wrappedkey_v0) and cannot be
# read without the device's key material. Use this script on-device or after
# mounting on the device itself.
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
OUTPUT_FILE="${PROJECT_ROOT}/device/ayaneo/pocket_ds/proprietary-files.txt"
MODE="adb"  # "adb" or "mount"
MOUNT_BASE=""

# ── Usage ──────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Catalog proprietary blobs from stock firmware and generate proprietary-files.txt.

${BOLD}Modes:${RESET}
  --adb                 Use ADB to pull file listings from a connected device
                        (default, requires: adb root)
  --mount <base>        Use locally mounted partitions at <base>/vendor,
                        <base>/system, <base>/system_ext, etc.

${BOLD}Options:${RESET}
  --output <path>       Output proprietary-files.txt path
                        (default: device/ayaneo/pocket_ds/proprietary-files.txt)
  --help                Show this help message and exit

${BOLD}Examples:${RESET}
  # Via ADB (device connected with root access):
  $(basename "$0") --adb

  # Via mounted partitions (after unpack-super.sh --mount):
  sudo $(basename "$0") --mount stock-firmware/unpacked/mnt
EOF
}

# ── Argument Parsing ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --adb)    MODE="adb";          shift   ;;
        --mount)  MODE="mount"; MOUNT_BASE="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2";    shift 2 ;;
        --help)   usage; exit 0                ;;
        *)
            echo -e "${RED}Error:${RESET} Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# ── Helpers ─────────────────────────────────────────────────────────────────
list_files_adb() {
    local partition="$1"
    adb shell "find /${partition} -type f 2>/dev/null" | sed "s|^/${partition}/|${partition}/|" | sort
}

list_files_mount() {
    local partition="$1"
    local mount_point="${MOUNT_BASE}/${partition}_a"
    if [[ ! -d "$mount_point" ]]; then
        mount_point="${MOUNT_BASE}/${partition}"
    fi
    if [[ ! -d "$mount_point" ]]; then
        echo -e "  ${YELLOW}Warning:${RESET} ${partition} not found at ${mount_point}" >&2
        return 0
    fi
    find "$mount_point" -type f | sed "s|^${mount_point}/|${partition}/|" | sort
}

list_files() {
    local partition="$1"
    if [[ "$MODE" == "adb" ]]; then
        list_files_adb "$partition"
    else
        list_files_mount "$partition"
    fi
}

# ── Validate Mode ──────────────────────────────────────────────────────────
if [[ "$MODE" == "adb" ]]; then
    if ! command -v adb &>/dev/null; then
        echo -e "${RED}Error:${RESET} adb not found." >&2
        exit 1
    fi
    if ! adb get-state &>/dev/null 2>&1; then
        echo -e "${RED}Error:${RESET} No device connected via ADB." >&2
        exit 1
    fi
    echo -e "${CYAN}Mode:${RESET} ADB (device connected)"
elif [[ "$MODE" == "mount" ]]; then
    if [[ -z "$MOUNT_BASE" || ! -d "$MOUNT_BASE" ]]; then
        echo -e "${RED}Error:${RESET} Mount base directory not found: ${MOUNT_BASE}" >&2
        exit 1
    fi
    echo -e "${CYAN}Mode:${RESET} Mounted partitions at ${MOUNT_BASE}"
fi

# ── Blob Classification ───────────────────────────────────────────────────
# These patterns identify proprietary blobs vs AOSP files.
# AOSP files are excluded; everything else is a proprietary blob.
is_aosp_file() {
    local path="$1"
    case "$path" in
        # AOSP framework / standard files
        */framework/framework.jar) return 0 ;;
        */framework/services.jar) return 0 ;;
        */framework/ext.jar) return 0 ;;
        */framework/core-*.jar) return 0 ;;
        # Build props
        */build.prop) return 0 ;;
        */default.prop) return 0 ;;
        # AOSP apps (shipped in AOSP source)
        */app/CertInstaller/*) return 0 ;;
        */app/PackageInstaller/*) return 0 ;;
        */app/Settings/*) return 0 ;;
        # Filesystem metadata
        */etc/fs_config_dirs) return 0 ;;
        */etc/fs_config_files) return 0 ;;
        # Selinux
        */etc/selinux/*) return 0 ;;
        # VINTF
        */etc/vintf/compatibility_matrix.xml) return 0 ;;
        */etc/vintf/manifest.xml) return 0 ;;
        # Anything else is proprietary
        *) return 1 ;;
    esac
}

# ── Catalog Blobs ──────────────────────────────────────────────────────────
echo -e "${CYAN}Cataloging proprietary blobs…${RESET}"
echo ""

declare -A SECTION_FILES
PARTITIONS=(vendor system_ext odm product vendor_dlkm system_dlkm)
TOTAL=0

for partition in "${PARTITIONS[@]}"; do
    echo -e "  ${CYAN}Scanning:${RESET} ${partition}"
    count=0
    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue
        if ! is_aosp_file "$filepath"; then
            # Categorize by directory structure
            case "$filepath" in
                */lib64/hw/*)         category="HAL implementations" ;;
                */lib/hw/*)           category="HAL implementations (32-bit)" ;;
                */lib64/egl/*)        category="Graphics (EGL)" ;;
                */bin/hw/*)           category="HAL services" ;;
                */bin/*)              category="Binaries" ;;
                */firmware/*)         category="Firmware" ;;
                */etc/init/*)         category="Init scripts" ;;
                */etc/vintf/*)        category="VINTF manifests" ;;
                */etc/permissions/*)  category="Permissions" ;;
                */etc/audio/*)        category="Audio configs" ;;
                */etc/camera/*)       category="Camera configs" ;;
                */etc/sensors/*)      category="Sensor configs" ;;
                */etc/wifi/*)         category="WiFi configs" ;;
                */etc/display/*)      category="Display configs" ;;
                */etc/*)              category="Configuration" ;;
                */lib/rfsa/*)         category="DSP modules" ;;
                */lib64/*)            category="Shared libraries (64-bit)" ;;
                */lib/*)              category="Shared libraries (32-bit)" ;;
                */framework/*)        category="Framework" ;;
                */app/*)              category="Apps" ;;
                */priv-app/*)         category="Privileged apps" ;;
                *)                    category="Other" ;;
            esac
            SECTION_FILES["${category}"]+="${filepath}"$'\n'
            ((count++)) || true
        fi
    done <<< "$(list_files "$partition")"
    echo -e "  ${GREEN}Found:${RESET} ${count} proprietary files in ${partition}"
    TOTAL=$((TOTAL + count))
done

# ── Generate proprietary-files.txt ─────────────────────────────────────────
echo ""
echo -e "${CYAN}Generating${RESET} ${OUTPUT_FILE}"

{
    cat <<'HEADER'
# Proprietary blobs for Ayaneo Pocket DS (SM8750 / TurboX C8550)
# Format: [- ]<path_on_device>[|sha1sum]
#   Lines starting with '-' are pinned (not updated during extract)
#   |sha1sum suffix pins to a specific file version
#
# Auto-generated by catalog-blobs.sh from stock firmware.
HEADER

    # Sort sections and write
    for category in $(echo "${!SECTION_FILES[@]}" | tr ' ' '\n' | sort); do
        echo ""
        echo "# ${category}"
        echo "${SECTION_FILES[$category]}" | sort -u | while IFS= read -r line; do
            [[ -n "$line" ]] && echo "$line"
        done
    done
} > "${OUTPUT_FILE}"

line_count=$(grep -c '^[^#]' "${OUTPUT_FILE}" | tr -d ' ' || echo "0")
echo -e "  ${GREEN}Done.${RESET} ${line_count} blob entries in ${TOTAL} total files."

echo ""
echo -e "${BOLD}═══ Summary ═══${RESET}"
echo -e "  Output:     ${OUTPUT_FILE}"
echo -e "  Total blobs: ${TOTAL}"
echo -e "  Sections:    ${#SECTION_FILES[@]}"
echo ""
echo -e "${GREEN}All done.${RESET} Review the generated file and remove any device-specific entries."
echo -e "Then run ${BOLD}scripts/extract-blobs.sh${RESET} to copy blobs into vendor/ayaneo/pocket_ds/."
