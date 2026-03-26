#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# unpack-super.sh
#
# Concatenates split super images, converts sparse -> raw, extracts logical
# partitions via lpunpack, and optionally mounts them read-only.
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
OUTPUT_DIR="${PROJECT_ROOT}/stock-firmware/unpacked"
DO_MOUNT=false

# ── Usage ──────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Concatenate split super images, convert sparse to raw, and extract logical
partitions (system, vendor, product, system_ext, odm).

${BOLD}Options:${RESET}
  --firmware-dir <path>   Directory containing super_1.img … super_8.img
                          (default: stock-firmware/ufs)
  --output-dir <path>     Where to write combined image and extracted partitions
                          (default: stock-firmware/unpacked)
  --mount                 Mount extracted partitions read-only via loop device
  --help                  Show this help message and exit
EOF
}

# ── Argument Parsing ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --firmware-dir) FIRMWARE_DIR="$2"; shift 2 ;;
        --output-dir)   OUTPUT_DIR="$2";   shift 2 ;;
        --mount)        DO_MOUNT=true;     shift   ;;
        --help)         usage; exit 0              ;;
        *)
            echo -e "${RED}Error:${RESET} Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# ── Dependency Checks ─────────────────────────────────────────────────────
MISSING=()
for cmd in simg2img lpunpack; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}Error:${RESET} Missing required tools: ${MISSING[*]}" >&2
    echo "Install them with your package manager (e.g., android-tools, lpunpack)." >&2
    exit 1
fi
if $DO_MOUNT && [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error:${RESET} --mount requires root privileges (run with sudo)." >&2
    exit 1
fi

# ── Validate Firmware Directory ────────────────────────────────────────────
if [[ ! -d "$FIRMWARE_DIR" ]]; then
    echo -e "${RED}Error:${RESET} Firmware directory not found: ${FIRMWARE_DIR}" >&2
    exit 1
fi

for i in $(seq 1 8); do
    if [[ ! -f "${FIRMWARE_DIR}/super_${i}.img" ]]; then
        echo -e "${RED}Error:${RESET} Missing ${FIRMWARE_DIR}/super_${i}.img" >&2
        exit 1
    fi
done

# ── Prepare Output Directory ──────────────────────────────────────────────
mkdir -p "${OUTPUT_DIR}"

SPARSE_IMG="${OUTPUT_DIR}/super_combined_sparse.img"
RAW_IMG="${OUTPUT_DIR}/super_combined.img"
PARTITIONS_DIR="${OUTPUT_DIR}/partitions"
MOUNT_DIR="${OUTPUT_DIR}/mnt"

# ── Step 1: Reconstruct Super Image ──────────────────────────────────────
# The super partition is split into 8 chunks placed at specific sector offsets
# on the UFS disk (4096-byte sectors). We must parse rawprogram_unsparse0.xml
# to determine the correct offsets, or fall back to naive concatenation.

RAWPROGRAM="${FIRMWARE_DIR}/rawprogram_unsparse0.xml"

if [[ -f "$RAW_IMG" ]]; then
    echo -e "${YELLOW}Skipping:${RESET} ${RAW_IMG} already exists (idempotent)."
elif [[ -f "$RAWPROGRAM" ]]; then
    echo -e "${CYAN}[1/2]${RESET} Reconstructing super image from rawprogram sector offsets"

    # Parse super chunk entries from rawprogram XML
    # Each <program> entry with label="super" has start_sector and num_partition_sectors
    SUPER_START=""
    declare -a CHUNK_SECTORS=()
    declare -a CHUNK_COUNTS=()
    declare -a CHUNK_FILES=()

    while IFS= read -r line; do
        if echo "$line" | grep -q 'label="super"' && echo "$line" | grep -q 'filename="super_'; then
            sector=$(echo "$line" | sed -n 's/.*start_sector="\([0-9]*\)".*/\1/p')
            count=$(echo "$line" | sed -n 's/.*num_partition_sectors="\([0-9]*\)".*/\1/p')
            fname=$(echo "$line" | sed -n 's/.*filename="\([^"]*\)".*/\1/p')
            if [[ -z "$SUPER_START" ]]; then
                SUPER_START="$sector"
            fi
            CHUNK_SECTORS+=("$sector")
            CHUNK_COUNTS+=("$count")
            CHUNK_FILES+=("$fname")
        fi
    done < "$RAWPROGRAM"

    if [[ -z "$SUPER_START" || ${#CHUNK_FILES[@]} -eq 0 ]]; then
        echo -e "${RED}Error:${RESET} Could not parse super chunk layout from ${RAWPROGRAM}" >&2
        exit 1
    fi

    # Determine super partition total size from LP metadata (sector 0 of super)
    # First chunk gives us the LP header; read geometry at offset 4096
    LP_MAGIC="$(xxd -s 4096 -l 4 -p "${FIRMWARE_DIR}/${CHUNK_FILES[0]}" 2>/dev/null || true)"
    if [[ "$LP_MAGIC" == "67446c61" ]]; then
        # Read LP geometry block size at offset 4096+4 (4 bytes LE)
        SUPER_SIZE_HEX="$(xxd -s 4100 -l 4 -e "${FIRMWARE_DIR}/${CHUNK_FILES[0]}" 2>/dev/null | awk '{print $2}' || true)"
    fi

    # Calculate total size from last chunk end if LP metadata read fails
    last_idx=$(( ${#CHUNK_SECTORS[@]} - 1 ))
    last_end=$(( CHUNK_SECTORS[last_idx] + CHUNK_COUNTS[last_idx] - SUPER_START ))
    FALLBACK_SIZE=$(( last_end * 4096 ))

    # Use lpdump to get actual super size if available
    SUPER_SIZE=""
    if command -v lpdump &>/dev/null; then
        SUPER_SIZE=$(lpdump "${FIRMWARE_DIR}/${CHUNK_FILES[0]}" 2>/dev/null | grep -o 'block_device.*size: [0-9]*' | grep -o '[0-9]*$' || true)
    fi
    # Fall back to standard 6 GiB or computed size
    if [[ -z "$SUPER_SIZE" ]]; then
        # Round up to nearest GiB boundary (common for super partitions)
        SUPER_SIZE=$(( ((FALLBACK_SIZE + 1073741823) / 1073741824) * 1073741824 ))
    fi

    echo -e "  Super start sector: ${SUPER_START} (4096-byte sectors)"
    echo -e "  Chunks: ${#CHUNK_FILES[@]}"
    echo -e "  Target size: $(( SUPER_SIZE / 1048576 )) MiB"

    # Create the image and place each chunk at its offset
    truncate -s "${SUPER_SIZE}" "${RAW_IMG}"
    for i in "${!CHUNK_FILES[@]}"; do
        offset_sectors=$(( CHUNK_SECTORS[i] - SUPER_START ))
        offset_bytes=$(( offset_sectors * 4096 ))
        src="${FIRMWARE_DIR}/${CHUNK_FILES[$i]}"
        echo -e "  Writing ${CHUNK_FILES[$i]} at offset ${offset_bytes}"
        dd if="$src" of="${RAW_IMG}" bs=4096 seek="${offset_sectors}" conv=notrunc status=none 2>/dev/null
    done
    echo -e "${GREEN}  Done.${RESET} Size: $(du -h "${RAW_IMG}" | cut -f1)"
else
    # Fallback: naive concatenation (works for standard Android sparse images)
    echo -e "${CYAN}[1/2]${RESET} Concatenating super_1.img … super_8.img"
    cat "${FIRMWARE_DIR}"/super_{1..8}.img > "${SPARSE_IMG}"
    echo -e "${GREEN}  Done.${RESET} Size: $(du -h "${SPARSE_IMG}" | cut -f1)"

    # Check if the combined image is sparse (magic 0xED26FF3A) or already raw
    MAGIC="$(xxd -l4 -p "${SPARSE_IMG}" 2>/dev/null || true)"
    if [[ "$MAGIC" == "3aff26ed" ]]; then
        echo -e "${CYAN}Converting sparse → raw (simg2img)${RESET}"
        simg2img "${SPARSE_IMG}" "${RAW_IMG}"
        echo -e "${GREEN}  Done.${RESET} Size: $(du -h "${RAW_IMG}" | cut -f1)"
    else
        ln -sf "$(basename "${SPARSE_IMG}")" "${RAW_IMG}"
    fi
fi

# ── Step 3: Extract Logical Partitions ────────────────────────────────────
EXPECTED_PARTITIONS=(system_a vendor_a product_a system_ext_a odm_a system_dlkm_a vendor_dlkm_a)

if [[ -d "$PARTITIONS_DIR" ]]; then
    existing=0
    for part in "${EXPECTED_PARTITIONS[@]}"; do
        [[ -f "${PARTITIONS_DIR}/${part}.img" ]] && ((existing++)) || true
    done
    if [[ $existing -eq ${#EXPECTED_PARTITIONS[@]} ]]; then
        echo -e "${YELLOW}Skipping:${RESET} All partitions already extracted (idempotent)."
    else
        echo -e "${CYAN}[2/2]${RESET} Extracting logical partitions with lpunpack"
        lpunpack "${RAW_IMG}" "${PARTITIONS_DIR}"
        echo -e "${GREEN}  Done.${RESET}"
    fi
else
    mkdir -p "${PARTITIONS_DIR}"
    echo -e "${CYAN}[2/2]${RESET} Extracting logical partitions with lpunpack"
    lpunpack "${RAW_IMG}" "${PARTITIONS_DIR}"
    echo -e "${GREEN}  Done.${RESET}"
fi

# ── Optional: Mount Partitions ────────────────────────────────────────────
if $DO_MOUNT; then
    echo ""
    echo -e "${CYAN}Mounting partitions read-only…${RESET}"
    mkdir -p "${MOUNT_DIR}"
    for part in "${EXPECTED_PARTITIONS[@]}"; do
        part_img="${PARTITIONS_DIR}/${part}.img"
        mnt_point="${MOUNT_DIR}/${part}"
        if [[ ! -f "$part_img" ]]; then
            echo -e "  ${YELLOW}Warning:${RESET} ${part}.img not found, skipping."
            continue
        fi
        mkdir -p "${mnt_point}"
        if mountpoint -q "${mnt_point}" 2>/dev/null; then
            echo -e "  ${YELLOW}Skipping:${RESET} ${part} already mounted at ${mnt_point}"
        else
            mount -o ro,loop "${part_img}" "${mnt_point}"
            echo -e "  ${GREEN}Mounted:${RESET} ${part} → ${mnt_point}"
        fi
    done
fi

# ── LP Metadata ──────────────────────────────────────────────────────────
echo ""
if command -v lpdump &>/dev/null; then
    echo -e "${BOLD}═══ LP Metadata (lpdump) ═══${RESET}"
    lpdump "${RAW_IMG}" 2>/dev/null || echo -e "  ${YELLOW}lpdump failed.${RESET}"
    echo ""
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══ Partition Summary ═══${RESET}"
printf "  ${BOLD}%-20s %10s${RESET}\n" "PARTITION" "SIZE"
printf "  %-20s %10s\n" "────────────────────" "──────────"
for part in "${EXPECTED_PARTITIONS[@]}"; do
    part_img="${PARTITIONS_DIR}/${part}.img"
    if [[ -f "$part_img" ]]; then
        size="$(du -h "${part_img}" | cut -f1)"
        printf "  ${GREEN}%-20s${RESET} %10s\n" "${part}" "${size}"
    else
        printf "  ${RED}%-20s${RESET} %10s\n" "${part}" "(missing)"
    fi
done
echo ""

if $DO_MOUNT; then
    echo -e "${BOLD}Mount points:${RESET} ${MOUNT_DIR}/<partition>"
fi
echo -e "${GREEN}All done.${RESET}"
