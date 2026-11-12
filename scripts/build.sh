#!/usr/bin/env bash
set -euo pipefail

# Build orchestration script for LineageOS 24 — Ayaneo Pocket DS
# Usage: ./scripts/build.sh [--all|--init|--extract|--patch|--build] [options]

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }

# --- Defaults ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PHASE_INIT=false
PHASE_EXTRACT=false
PHASE_PATCH=false
PHASE_BUILD=false
DO_CLEAN=false
JOBS="$(nproc)"
VARIANT="userdebug"
WITH_GAPPS=true
FIRMWARE_DIR="$ROOT_DIR/stock-firmware/ufs"

usage() {
    cat <<EOF
Usage: $(basename "$0") [PHASES] [OPTIONS]

Phases (default: --all):
  --all         Run all phases sequentially
  --init        Phase 1: repo init + sync
  --extract     Phase 2: Unpack firmware + extract blobs
  --patch       Phase 3: Apply KernelSU patch
  --build       Phase 4: lunch + mka bacon

Options:
  --clean       Run 'make clean' before building
  --jobs N      Override build parallelism (default: $(nproc))
  --variant V   Build variant: userdebug|user|eng (default: userdebug)
  --no-gapps    Skip GApps inclusion (debug only, non-standard)
  --firmware-dir DIR  Stock firmware location (default: stock-firmware/ufs)
  --help        Show this help

Examples:
  $(basename "$0") --all
  $(basename "$0") --init --build
  $(basename "$0") --build --clean --jobs 8
EOF
    exit 0
}

# --- Parse Args ---
if [[ $# -eq 0 ]]; then
    PHASE_INIT=true
    PHASE_EXTRACT=true
    PHASE_PATCH=true
    PHASE_BUILD=true
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            PHASE_INIT=true
            PHASE_EXTRACT=true
            PHASE_PATCH=true
            PHASE_BUILD=true
            ;;
        --init)     PHASE_INIT=true ;;
        --extract)  PHASE_EXTRACT=true ;;
        --patch)    PHASE_PATCH=true ;;
        --build)    PHASE_BUILD=true ;;
        --clean)    DO_CLEAN=true ;;
        --jobs)     JOBS="$2"; shift ;;
        --variant)  VARIANT="$2"; shift ;;
        --no-gapps)
            WITH_GAPPS=false
            warn "Building WITHOUT GApps — this is a non-standard debug build!"
            ;;
        --firmware-dir) FIRMWARE_DIR="$2"; shift ;;
        --help)     usage ;;
        *)          die "Unknown option: $1 (use --help)" ;;
    esac
    shift
done

cd "$ROOT_DIR"

# =============================================================================
# Phase 1: Init — repo init + sync
# =============================================================================
phase_init() {
    info "=== Phase 1: Repository Init & Sync ==="

    # repo init is idempotent; re-running it also switches an existing
    # checkout to the branch below.
    info "Initializing LineageOS 24 repo..."
    repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs --depth=1

    # Copy local manifests
    mkdir -p .repo/local_manifests
    info "Copying local manifests..."
    cp -v local_manifests/*.xml .repo/local_manifests/

    info "Syncing sources (jobs=$JOBS)..."
    repo sync -c -j"$JOBS" --force-sync --no-tags

    ok "Phase 1 complete: sources synced"
}

# =============================================================================
# Phase 2: Extract — unpack firmware + extract blobs
# =============================================================================
phase_extract() {
    info "=== Phase 2: Firmware Extraction ==="

    if [[ ! -d "$FIRMWARE_DIR" ]]; then
        die "Firmware directory not found: $FIRMWARE_DIR"
    fi

    local unpacked_dir="$ROOT_DIR/stock-firmware/unpacked"

    # Unpack super partition
    if [[ ! -f "$unpacked_dir/partitions/vendor_a.img" ]]; then
        info "Unpacking super partition..."
        "$SCRIPT_DIR/unpack-super.sh" \
            --firmware-dir "$FIRMWARE_DIR" \
            --output-dir "$unpacked_dir"
    else
        ok "Super already unpacked"
    fi

    # Unpack boot images
    if [[ ! -d "$unpacked_dir/boot" ]]; then
        info "Unpacking boot images..."
        "$SCRIPT_DIR/unpack-boot.sh" \
            --firmware-dir "$FIRMWARE_DIR" \
            --output-dir "$unpacked_dir/boot"
    else
        ok "Boot images already unpacked"
    fi

    info "Extracting proprietary blobs..."
    "$SCRIPT_DIR/extract-blobs.sh" --partitions-dir "$unpacked_dir/partitions"

    # Fetch GApps and gsmlg-apps
    if [[ "$WITH_GAPPS" == true ]]; then
        if [[ -x "$SCRIPT_DIR/fetch-gapps.sh" ]]; then
            info "Fetching GApps..."
            "$SCRIPT_DIR/fetch-gapps.sh"
        fi
    fi

    if [[ -x "$SCRIPT_DIR/fetch-gsmlg-apps.sh" ]]; then
        info "Fetching gsmlg-apps..."
        "$SCRIPT_DIR/fetch-gsmlg-apps.sh"
    fi

    ok "Phase 2 complete: blobs extracted"
}

# =============================================================================
# Phase 3: Patch — KernelSU
# =============================================================================
phase_patch() {
    info "=== Phase 3: KernelSU Patch ==="

    local boot_img="$ROOT_DIR/stock-firmware/unpacked/boot/boot.img"
    local vendor_boot_img="$ROOT_DIR/stock-firmware/unpacked/boot/vendor_boot.img"

    if [[ ! -f "$boot_img" ]]; then
        # Fall back to firmware dir
        boot_img="$FIRMWARE_DIR/boot.img"
    fi

    if [[ ! -f "$boot_img" ]]; then
        die "boot.img not found. Run --extract first."
    fi

    local patch_args=(--boot "$boot_img")
    if [[ -f "$vendor_boot_img" ]]; then
        patch_args+=(--vendor-boot "$vendor_boot_img")
    elif [[ -f "$FIRMWARE_DIR/vendor_boot.img" ]]; then
        patch_args+=(--vendor-boot "$FIRMWARE_DIR/vendor_boot.img")
    fi

    info "Patching with KernelSU..."
    "$SCRIPT_DIR/patch-kernelsu.sh" "${patch_args[@]}"

    ok "Phase 3 complete: KernelSU patched"
}

# =============================================================================
# Phase 4: Build — lunch + mka bacon
# =============================================================================
phase_build() {
    info "=== Phase 4: Build ==="

    if [[ ! -f build/envsetup.sh ]]; then
        die "AOSP source not found. Run --init first."
    fi

    if [[ "$DO_CLEAN" == true ]]; then
        info "Cleaning build..."
        # shellcheck disable=SC1091
        set +u
        source build/envsetup.sh
        set -u
        make clean
    fi

    info "Setting up build environment..."
    # shellcheck disable=SC1091
    set +u
    source build/envsetup.sh

    # Prepend AOSP host lib64 to LD_LIBRARY_PATH so the AOSP-built xmllint and
    # other host tools load AOSP's libxml2 (with schematron support) instead of
    # the system libxml2 from nix-ld or pipewire-jack LD_LIBRARY_PATH entries.
    local out_host_lib
    out_host_lib="${OUT_DIR:-out}/host/linux-x86/lib64"
    export LD_LIBRARY_PATH="${out_host_lib}:${LD_LIBRARY_PATH:-}"

    # NixOS: AOSP's prebuilt host tools are started through nix-ld, which
    # needs NIX_LD/NIX_LD_LIBRARY_PATH. soong strips unknown variables from
    # the ninja environment, and without them the prebuilt awk segfaults in
    # sandboxed genrules. Keep the environment when nix-ld is in use.
    if [[ -n "${NIX_LD:-}" ]]; then
        export ALLOW_NINJA_ENV=true
    fi

    # lunch format: <product>-<release>-<variant>; LineageOS records the
    # release it builds against in vendor/lineage/vars/aosp_target_release.
    local aosp_target_release
    # shellcheck disable=SC1091
    source vendor/lineage/vars/aosp_target_release
    local lunch_target="lineage_pocket_ds-${aosp_target_release}-${VARIANT}"
    info "Lunch target: $lunch_target"
    lunch "$lunch_target"

    if [[ "$WITH_GAPPS" != true ]]; then
        export WITH_GAPPS=false
        warn "GApps disabled for this build"
    fi

    info "Building (jobs=$JOBS)..."
    mka bacon -j"$JOBS"
    set -u

    # Copy output
    local out_zip
    out_zip=$(find out/target/product/pocket_ds -maxdepth 1 -name 'lineage-24*.zip' -print -quit 2>/dev/null)

    if [[ -n "$out_zip" ]]; then
        mkdir -p out/release
        cp -v "$out_zip" out/release/
        local sha256
        sha256=$(sha256sum "$out_zip" | cut -d' ' -f1)
        local size
        size=$(du -h "$out_zip" | cut -f1)

        echo ""
        ok "=== Build Complete ==="
        info "Output: $out_zip"
        info "Size:   $size"
        info "SHA256: $sha256"
    else
        warn "Build completed but no output ZIP found in out/target/product/pocket_ds/"
    fi

    ok "Phase 4 complete"
}

# =============================================================================
# Main
# =============================================================================
info "LineageOS 24 — Ayaneo Pocket DS Build"
info "Variant: $VARIANT | Jobs: $JOBS | GApps: $WITH_GAPPS"
echo ""

$PHASE_INIT    && phase_init
$PHASE_EXTRACT && phase_extract
$PHASE_PATCH   && phase_patch
$PHASE_BUILD   && phase_build

echo ""
ok "All requested phases complete!"
