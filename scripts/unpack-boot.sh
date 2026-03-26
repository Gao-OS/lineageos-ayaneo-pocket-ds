#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# unpack-boot.sh
#
# Unpacks boot.img, vendor_boot.img, dtbo.img, and init_boot.img using
# unpackbootimg / mkdtboimg, and prints kernel version + vendor modules.
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

FIRMWARE_DIR="${PROJECT_ROOT}/stock-firmware/ufs"
OUTPUT_DIR="${PROJECT_ROOT}/stock-firmware/unpacked/boot"

# ── Usage ──────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Unpack boot images from stock firmware:
  - boot.img      → kernel Image, ramdisk, DTB, boot header
  - vendor_boot.img → vendor ramdisk, vendor kernel modules, vendor DTB
  - dtbo.img      → individual DTB overlays
  - init_boot.img → generic ramdisk

${BOLD}Options:${RESET}
  --firmware-dir <path>   Directory containing boot images
                          (default: stock-firmware/ufs)
  --output-dir <path>     Where to write unpacked artifacts
                          (default: stock-firmware/unpacked/boot)
  --help                  Show this help message and exit
EOF
}

# ── Argument Parsing ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --firmware-dir) FIRMWARE_DIR="$2"; shift 2 ;;
        --output-dir)   OUTPUT_DIR="$2";   shift 2 ;;
        --help)         usage; exit 0              ;;
        *)
            echo -e "${RED}Error:${RESET} Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# ── Dependency Checks ─────────────────────────────────────────────────────
# unpack_bootimg.py (AOSP) or unpackbootimg binary
UNPACK_BOOTIMG=""
if command -v unpack_bootimg.py &>/dev/null; then
    UNPACK_BOOTIMG="unpack_bootimg.py"
elif command -v unpackbootimg &>/dev/null; then
    UNPACK_BOOTIMG="unpackbootimg"
elif [[ -f /tmp/mkbootimg/unpack_bootimg.py ]]; then
    UNPACK_BOOTIMG="python3 /tmp/mkbootimg/unpack_bootimg.py"
else
    echo -e "${RED}Error:${RESET} No boot image unpacker found." >&2
    echo "  Install: git clone https://android.googlesource.com/platform/system/tools/mkbootimg /tmp/mkbootimg" >&2
    exit 1
fi
echo -e "  ${GREEN}Using:${RESET} ${UNPACK_BOOTIMG}"

HAS_MKDTBOIMG=false
if command -v mkdtboimg &>/dev/null; then
    HAS_MKDTBOIMG=true
fi

# ── Validate Firmware Directory ────────────────────────────────────────────
if [[ ! -d "$FIRMWARE_DIR" ]]; then
    echo -e "${RED}Error:${RESET} Firmware directory not found: ${FIRMWARE_DIR}" >&2
    exit 1
fi

# ── Prepare Output Directory ──────────────────────────────────────────────
mkdir -p "${OUTPUT_DIR}"

# ── Helper: unpack a boot-style image ─────────────────────────────────────
unpack_boot_image() {
    local img_name="$1"
    local img_path="${FIRMWARE_DIR}/${img_name}"
    local out="${OUTPUT_DIR}/${img_name%.img}"

    if [[ ! -f "$img_path" ]]; then
        echo -e "  ${YELLOW}Warning:${RESET} ${img_name} not found in ${FIRMWARE_DIR}, skipping."
        return 0
    fi

    if [[ -d "$out" && "$(ls -A "$out" 2>/dev/null)" ]]; then
        echo -e "  ${YELLOW}Skipping:${RESET} ${img_name} already unpacked (idempotent)."
        return 0
    fi

    mkdir -p "$out"
    echo -e "  ${CYAN}Unpacking${RESET} ${img_name} → ${out}/"
    $UNPACK_BOOTIMG --boot_img "${img_path}" --out "${out}" 2>&1 | sed 's/^/    /'
    echo -e "  ${GREEN}Done.${RESET}"
}

# ── Step 1: boot.img ─────────────────────────────────────────────────────
echo -e "${BOLD}[1/4] boot.img${RESET} (kernel, ramdisk, DTB, header)"
unpack_boot_image "boot.img"

# ── Step 2: vendor_boot.img ──────────────────────────────────────────────
echo -e "${BOLD}[2/4] vendor_boot.img${RESET} (vendor ramdisk, modules, DTB)"
unpack_boot_image "vendor_boot.img"

# ── Step 3: dtbo.img ─────────────────────────────────────────────────────
echo -e "${BOLD}[3/4] dtbo.img${RESET} (DTB overlays)"
DTBO_IMG="${FIRMWARE_DIR}/dtbo.img"
DTBO_OUT="${OUTPUT_DIR}/dtbo"
if ! $HAS_MKDTBOIMG; then
    echo -e "  ${YELLOW}Warning:${RESET} mkdtboimg not found, skipping dtbo.img."
elif [[ ! -f "$DTBO_IMG" ]]; then
    echo -e "  ${YELLOW}Warning:${RESET} dtbo.img not found, skipping."
elif [[ -d "$DTBO_OUT" && "$(ls -A "$DTBO_OUT" 2>/dev/null)" ]]; then
    echo -e "  ${YELLOW}Skipping:${RESET} dtbo.img already unpacked (idempotent)."
else
    mkdir -p "${DTBO_OUT}"
    echo -e "  ${CYAN}Unpacking${RESET} dtbo.img → ${DTBO_OUT}/"
    mkdtboimg dump "${DTBO_IMG}" -b "${DTBO_OUT}/dtbo" 2>&1 | sed 's/^/    /'
    echo -e "  ${GREEN}Done.${RESET}"
fi

# ── Step 4: init_boot.img ────────────────────────────────────────────────
echo -e "${BOLD}[4/4] init_boot.img${RESET} (generic ramdisk)"
unpack_boot_image "init_boot.img"

# ── Kernel Version ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══ Kernel Version ═══${RESET}"
# unpack_bootimg.py outputs to "kernel", unpackbootimg outputs to "boot.img-kernel"
KERNEL_IMG=""
for candidate in "${OUTPUT_DIR}/boot/kernel" "${OUTPUT_DIR}/boot/boot.img-kernel"; do
    [[ -f "$candidate" ]] && KERNEL_IMG="$candidate" && break
done
if [[ -n "$KERNEL_IMG" ]]; then
    # Try to find kernel version via vermagic-style strings
    version_string="$(strings "${KERNEL_IMG}" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[a-z0-9]+' | head -1 || true)"
    if [[ -n "$version_string" ]]; then
        echo -e "  ${GREEN}Kernel:${RESET} ${version_string}"
    else
        echo -e "  ${YELLOW}Could not extract kernel version string from binary.${RESET}"
    fi
    echo -e "  ${GREEN}Size:${RESET} $(du -h "${KERNEL_IMG}" | cut -f1)"
else
    echo -e "  ${YELLOW}No kernel image found to extract version from.${RESET}"
fi

# ── Vendor Modules ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══ Vendor Kernel Modules ═══${RESET}"
VENDOR_RAMDISK="${OUTPUT_DIR}/vendor_boot"
if [[ -d "$VENDOR_RAMDISK" ]]; then
    # Look for modules inside unpacked vendor ramdisk
    modules_found=false
    while IFS= read -r -d '' mod; do
        modules_found=true
        echo -e "  ${GREEN}*${RESET} ${mod#"${VENDOR_RAMDISK}"/}"
    done < <(find "${VENDOR_RAMDISK}" -name "*.ko" -print0 2>/dev/null || true)

    if ! $modules_found; then
        # Vendor ramdisk may be compressed; try to unpack it
        vendor_ramdisk_file=""
        for candidate in "${VENDOR_RAMDISK}/vendor_ramdisk00" \
                         "${VENDOR_RAMDISK}/vendor_boot.img-vendor_ramdisk" \
                         "${VENDOR_RAMDISK}/vendor_boot.img-ramdisk"; do
            if [[ -f "$candidate" ]]; then
                vendor_ramdisk_file="$candidate"
                break
            fi
        done

        if [[ -n "$vendor_ramdisk_file" ]]; then
            ramdisk_extract="${VENDOR_RAMDISK}/ramdisk_extracted"
            if [[ ! -d "$ramdisk_extract" ]]; then
                mkdir -p "$ramdisk_extract"
                # Detect compression and extract
                magic="$(xxd -l4 -p "$vendor_ramdisk_file" 2>/dev/null || true)"
                case "$magic" in
                    1f8b*)  # gzip
                        (cd "$ramdisk_extract" && gzip -dc "$vendor_ramdisk_file" | cpio -idm 2>/dev/null) || true
                        ;;
                    fd377a58*)  # xz
                        (cd "$ramdisk_extract" && xz -dc "$vendor_ramdisk_file" | cpio -idm 2>/dev/null) || true
                        ;;
                    28b52ffd*)  # zstd
                        if command -v zstd &>/dev/null; then
                            (cd "$ramdisk_extract" && zstd -dc "$vendor_ramdisk_file" | cpio -idm 2>/dev/null) || true
                        fi
                        ;;
                    894c5a4f*)  # lzo
                        if command -v lzop &>/dev/null; then
                            (cd "$ramdisk_extract" && lzop -dc "$vendor_ramdisk_file" | cpio -idm 2>/dev/null) || true
                        fi
                        ;;
                    02214c18*)  # lz4
                        if command -v lz4 &>/dev/null; then
                            (cd "$ramdisk_extract" && lz4 -dc "$vendor_ramdisk_file" | cpio -idm 2>/dev/null) || true
                        fi
                        ;;
                    *)
                        # Try gzip as fallback
                        (cd "$ramdisk_extract" && gzip -dc "$vendor_ramdisk_file" 2>/dev/null | cpio -idm 2>/dev/null) || true
                        ;;
                esac
            fi

            while IFS= read -r -d '' mod; do
                modules_found=true
                echo -e "  ${GREEN}*${RESET} ${mod#"${ramdisk_extract}"/}"
            done < <(find "${ramdisk_extract}" -name "*.ko" -print0 2>/dev/null || true)
        fi

        if ! $modules_found; then
            echo -e "  ${YELLOW}No .ko modules found.${RESET}"
        fi
    fi
else
    echo -e "  ${YELLOW}vendor_boot not unpacked; no modules to list.${RESET}"
fi

echo ""
echo -e "${GREEN}All done.${RESET}"
