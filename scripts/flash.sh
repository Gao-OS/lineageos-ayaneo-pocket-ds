#!/usr/bin/env bash
set -euo pipefail

# Flash script for LineageOS 21 — Ayaneo Pocket DS
# Supports fastboot (default) and EDL mode

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }
step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

# --- Defaults ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="fastboot"
DRY_RUN=false
WIPE_DATA=false
IMAGE_DIR=""

# --- Required tools ---
check_tool() {
    command -v "$1" &>/dev/null || die "Required tool not found: $1"
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Modes:
  (default)     Fastboot mode — flash LineageOS build output
  --edl         EDL mode — full reflash using QSaharaServer + fh_loader

Options:
  --image-dir DIR   Directory containing images to flash
                    (default: out/target/product/pocket_ds for fastboot,
                     stock-firmware/ufs for EDL)
  --wipe            Wipe userdata (factory reset)
  --dry-run         Print commands without executing
  --help            Show this help

Fastboot mode flashes:
  boot, vendor_boot, dtbo, init_boot, vbmeta, super (or logical partitions)

EDL mode restores stock firmware using rawprogram/patch XML files.

Examples:
  $(basename "$0")                              # Flash LineageOS via fastboot
  $(basename "$0") --wipe                       # Flash + factory reset
  $(basename "$0") --edl --image-dir stock-firmware/ufs  # Full EDL reflash
  $(basename "$0") --dry-run                    # Preview flash commands
EOF
    exit 0
}

# --- Parse Args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --edl)       MODE="edl" ;;
        --image-dir) IMAGE_DIR="$2"; shift ;;
        --wipe)      WIPE_DATA=true ;;
        --dry-run)   DRY_RUN=true ;;
        --help)      usage ;;
        *)           die "Unknown option: $1 (use --help)" ;;
    esac
    shift
done

# --- Helpers ---
run_cmd() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

confirm() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    echo ""
    warn "$1"
    read -rp "Continue? [y/N] " response
    [[ "$response" =~ ^[Yy]$ ]] || die "Aborted by user"
}

wait_for_device() {
    local tool="$1"
    local timeout=30
    info "Waiting for device in $tool mode (${timeout}s timeout)..."
    local i=0
    while [[ $i -lt $timeout ]]; do
        case "$tool" in
            fastboot)
                if fastboot devices 2>/dev/null | grep -q 'fastboot'; then
                    ok "Device found in fastboot mode"
                    return 0
                fi
                ;;
            adb)
                if adb devices 2>/dev/null | grep -q 'device$'; then
                    ok "Device found via ADB"
                    return 0
                fi
                ;;
        esac
        sleep 1
        ((i++))
    done
    die "Device not found in $tool mode after ${timeout}s"
}

# =============================================================================
# Fastboot Mode
# =============================================================================
flash_fastboot() {
    check_tool fastboot

    # Determine image directory
    if [[ -z "$IMAGE_DIR" ]]; then
        IMAGE_DIR="$ROOT_DIR/out/target/product/pocket_ds"
    fi

    if [[ ! -d "$IMAGE_DIR" ]]; then
        die "Image directory not found: $IMAGE_DIR"
    fi

    info "=== Fastboot Flash Mode ==="
    info "Image directory: $IMAGE_DIR"
    echo ""

    # List images to flash
    local images=()
    for img in boot.img vendor_boot.img dtbo.img init_boot.img vbmeta.img; do
        if [[ -f "$IMAGE_DIR/$img" ]]; then
            images+=("$img")
            info "  Found: $img ($(du -h "$IMAGE_DIR/$img" | cut -f1))"
        else
            warn "  Missing: $img"
        fi
    done

    # Check for super image
    local has_super=false
    if [[ -f "$IMAGE_DIR/super.img" ]]; then
        has_super=true
        info "  Found: super.img ($(du -h "$IMAGE_DIR/super.img" | cut -f1))"
    fi

    if [[ ${#images[@]} -eq 0 && "$has_super" == false ]]; then
        die "No flashable images found in $IMAGE_DIR"
    fi

    confirm "This will flash ${#images[@]} images to the device. Data may be lost."

    wait_for_device fastboot

    # Flash vbmeta first (disable verification)
    if [[ -f "$IMAGE_DIR/vbmeta.img" ]]; then
        step "Flashing vbmeta (verification disabled)..."
        run_cmd fastboot flash vbmeta --disable-verity --disable-verification "$IMAGE_DIR/vbmeta.img"
    fi

    if [[ -f "$IMAGE_DIR/vbmeta_system.img" ]]; then
        step "Flashing vbmeta_system..."
        run_cmd fastboot flash vbmeta_system --disable-verity --disable-verification "$IMAGE_DIR/vbmeta_system.img"
    fi

    # Flash boot images
    for img in boot.img vendor_boot.img dtbo.img init_boot.img; do
        if [[ -f "$IMAGE_DIR/$img" ]]; then
            local part="${img%.img}"
            step "Flashing $part..."
            run_cmd fastboot flash "$part" "$IMAGE_DIR/$img"
        fi
    done

    # Flash super (via fastbootd for dynamic partitions)
    if [[ "$has_super" == true ]]; then
        step "Rebooting to fastbootd for dynamic partition flash..."
        run_cmd fastboot reboot fastboot

        if [[ "$DRY_RUN" != true ]]; then
            sleep 5
            wait_for_device fastboot
        fi

        step "Flashing super..."
        run_cmd fastboot flash super "$IMAGE_DIR/super.img"
    else
        # Try individual logical partitions via fastbootd
        local logical_parts=(system vendor product system_ext odm)
        local has_logical=false
        for part in "${logical_parts[@]}"; do
            if [[ -f "$IMAGE_DIR/${part}.img" ]]; then
                has_logical=true
                break
            fi
        done

        if [[ "$has_logical" == true ]]; then
            step "Rebooting to fastbootd for logical partition flash..."
            run_cmd fastboot reboot fastboot

            if [[ "$DRY_RUN" != true ]]; then
                sleep 5
                wait_for_device fastboot
            fi

            for part in "${logical_parts[@]}"; do
                if [[ -f "$IMAGE_DIR/${part}.img" ]]; then
                    step "Flashing $part..."
                    run_cmd fastboot flash "$part" "$IMAGE_DIR/${part}.img"
                fi
            done
        fi
    fi

    # Wipe data if requested
    if [[ "$WIPE_DATA" == true ]]; then
        step "Wiping userdata..."
        run_cmd fastboot -w
    fi

    # Reboot
    step "Rebooting device..."
    run_cmd fastboot reboot

    echo ""
    ok "=== Flash Complete ==="
    info "Device is rebooting. First boot may take several minutes."
}

# =============================================================================
# EDL Mode (Emergency Download)
# =============================================================================
flash_edl() {
    if [[ -z "$IMAGE_DIR" ]]; then
        IMAGE_DIR="$ROOT_DIR/stock-firmware/ufs"
    fi

    if [[ ! -d "$IMAGE_DIR" ]]; then
        die "Firmware directory not found: $IMAGE_DIR"
    fi

    info "=== EDL Flash Mode ==="
    info "Firmware directory: $IMAGE_DIR"
    echo ""

    # Check for EDL tools
    local qsahara=""
    local fh_loader=""

    for tool_path in "$IMAGE_DIR/QSaharaServer" "/usr/bin/QSaharaServer" "$(command -v QSaharaServer 2>/dev/null || true)"; do
        if [[ -x "$tool_path" ]]; then
            qsahara="$tool_path"
            break
        fi
    done

    for tool_path in "$IMAGE_DIR/fh_loader" "/usr/bin/fh_loader" "$(command -v fh_loader 2>/dev/null || true)"; do
        if [[ -x "$tool_path" ]]; then
            fh_loader="$tool_path"
            break
        fi
    done

    if [[ -z "$qsahara" ]]; then
        die "QSaharaServer not found. Place it in $IMAGE_DIR/ or install to PATH."
    fi
    if [[ -z "$fh_loader" ]]; then
        die "fh_loader not found. Place it in $IMAGE_DIR/ or install to PATH."
    fi

    ok "QSaharaServer: $qsahara"
    ok "fh_loader: $fh_loader"

    # Find rawprogram and patch XML files
    local rawprogram_files=()
    local patch_files=()

    while IFS= read -r -d '' f; do
        rawprogram_files+=("$f")
    done < <(find "$IMAGE_DIR" -name 'rawprogram*.xml' -print0 | sort -z)

    while IFS= read -r -d '' f; do
        patch_files+=("$f")
    done < <(find "$IMAGE_DIR" -name 'patch*.xml' -print0 | sort -z)

    if [[ ${#rawprogram_files[@]} -eq 0 ]]; then
        die "No rawprogram*.xml files found in $IMAGE_DIR"
    fi

    info "Found ${#rawprogram_files[@]} rawprogram XML files"
    info "Found ${#patch_files[@]} patch XML files"

    # Find EDL port
    local edl_port=""
    for port in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyHS0; do
        if [[ -c "$port" ]]; then
            edl_port="$port"
            break
        fi
    done

    if [[ -z "$edl_port" && "$DRY_RUN" != true ]]; then
        warn "No EDL serial port detected."
        warn "Put device in EDL mode: power off, hold Vol- + power, connect USB"
        die "No EDL port found at /dev/ttyUSB*"
    fi
    edl_port="${edl_port:-/dev/ttyUSB0}"  # Default for dry-run

    info "EDL port: $edl_port"

    confirm "This will perform a FULL REFLASH via EDL. ALL data will be erased."

    # Step 1: Load programmer via Sahara protocol
    local programmer=""
    programmer=$(find "$IMAGE_DIR" -name 'prog_firehose_*.mbn' -o -name 'prog_firehose_*.elf' | head -1)
    if [[ -z "$programmer" ]]; then
        die "Firehose programmer not found in $IMAGE_DIR"
    fi

    step "Loading firehose programmer via Sahara..."
    run_cmd "$qsahara" -p "$edl_port" -s "13:$programmer"

    # Step 2: Flash using rawprogram XMLs
    for rawprogram in "${rawprogram_files[@]}"; do
        local basename
        basename=$(basename "$rawprogram")
        step "Flashing: $basename..."
        run_cmd "$fh_loader" --port="$edl_port" --sendxml="$rawprogram" --search_path="$IMAGE_DIR" --noprompt --zlpawarehost=1
    done

    # Step 3: Apply patches
    for patch in "${patch_files[@]}"; do
        local basename
        basename=$(basename "$patch")
        step "Patching: $basename..."
        run_cmd "$fh_loader" --port="$edl_port" --sendxml="$patch" --search_path="$IMAGE_DIR" --noprompt --zlpawarehost=1
    done

    # Step 4: Reset
    step "Resetting device..."
    run_cmd "$fh_loader" --port="$edl_port" --reset --noprompt

    echo ""
    ok "=== EDL Flash Complete ==="
    info "Device will boot into stock firmware."
    info "To flash LineageOS, boot to fastboot and run: $(basename "$0")"
}

# =============================================================================
# Main
# =============================================================================
case "$MODE" in
    fastboot)  flash_fastboot ;;
    edl)       flash_edl ;;
    *)         die "Unknown mode: $MODE" ;;
esac
