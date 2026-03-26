#!/usr/bin/env bash
set -euo pipefail

# ── Color helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { printf "${BLUE}[INFO]${RESET}    %s\n" "$*"; }
success() { printf "${GREEN}[OK]${RESET}      %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${RESET}    %s\n" "$*"; }
error()   { printf "${RED}[ERROR]${RESET}   %s\n" "$*" >&2; }
step()    { printf "${CYAN}${BOLD}▶ %s${RESET}\n" "$*"; }

# ── Globals ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BOOT_IMG=""
VENDOR_BOOT_IMG=""
OUTPUT_DIR=""
WORK_DIR=""
MODE=""  # "gki" or "patch"

KERNELSU_MANAGER_DEST="${PROJECT_ROOT}/packages/gsmlg-apps/prebuilt/KernelSUManager.apk"
KERNELSU_GH_API="https://api.github.com/repos/tiann/KernelSU/releases"
KERNELSU_MANAGER_GH_API="https://api.github.com/repos/tiann/KernelSU/releases"

REQUIRED_TOOLS=(unpackbootimg mkbootimg curl jq cpio gzip file)

# ── Usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]

Patch boot/vendor_boot images with KernelSU support.

${BOLD}Options:${RESET}
  --boot <boot.img>            Path to boot.img (required)
  --vendor-boot <vendor_boot>  Path to vendor_boot.img (optional, enables GKI mode)
  --output-dir <path>          Output directory for patched images (required)
  --help                       Show this help message

${BOLD}Integration Modes:${RESET}
  Mode A (GKI module, default):
    Requires --vendor-boot. Injects kernelsu.ko into the vendor ramdisk
    at /lib/modules/ and repacks vendor_boot.img.

  Mode B (Kernel patch, fallback):
    Patches the kernel Image binary inside boot.img using KernelSU's
    patcher tool.  Used when GKI detection fails or --vendor-boot is
    not provided.

${BOLD}Example:${RESET}
  $(basename "$0") \\
      --boot stock-firmware/boot.img \\
      --vendor-boot stock-firmware/vendor_boot.img \\
      --output-dir out/patched
EOF
    exit 0
}

# ── Argument parsing ─────────────────────────────────────────────────────────
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --boot)
                BOOT_IMG="$2"; shift 2 ;;
            --vendor-boot)
                VENDOR_BOOT_IMG="$2"; shift 2 ;;
            --output-dir)
                OUTPUT_DIR="$2"; shift 2 ;;
            --help)
                usage ;;
            *)
                error "Unknown option: $1"
                usage ;;
        esac
    done

    if [[ -z "${BOOT_IMG}" ]]; then
        error "--boot is required"
        exit 1
    fi
    if [[ ! -f "${BOOT_IMG}" ]]; then
        error "Boot image not found: ${BOOT_IMG}"
        exit 1
    fi
    if [[ -n "${VENDOR_BOOT_IMG}" && ! -f "${VENDOR_BOOT_IMG}" ]]; then
        error "Vendor boot image not found: ${VENDOR_BOOT_IMG}"
        exit 1
    fi
    if [[ -z "${OUTPUT_DIR}" ]]; then
        error "--output-dir is required"
        exit 1
    fi
}

# ── Preflight checks ────────────────────────────────────────────────────────
check_tools() {
    local missing=()
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            missing+=("${tool}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        error "Install them before running this script."
        exit 1
    fi
    success "All required tools found"
}

# ── Cleanup handler ──────────────────────────────────────────────────────────
cleanup() {
    if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" ]]; then
        rm -rf "${WORK_DIR}"
    fi
}
trap cleanup EXIT

# ── Helpers ──────────────────────────────────────────────────────────────────

# Parse the kernel version string from boot.img via unpackbootimg header output.
get_kernel_version() {
    local boot="$1"
    local unpack_dir="${WORK_DIR}/boot_header"
    mkdir -p "${unpack_dir}"

    unpackbootimg --boot_img "${boot}" --out "${unpack_dir}" &>/dev/null || true

    local version_file="${unpack_dir}/boot.img-os_version"
    local kver=""

    # Try the os_version file first (contains something like "12.0.0" or kernel version).
    if [[ -f "${version_file}" ]]; then
        kver="$(cat "${version_file}" | tr -d '[:space:]')"
    fi

    # Also try extracting from the kernel Image itself.
    if [[ -z "${kver}" || "${kver}" == "0.0.0" ]]; then
        local kernel_file="${unpack_dir}/boot.img-kernel"
        if [[ -f "${kernel_file}" ]]; then
            # Linux kernel images contain a version string like "5.15.137-android14-..."
            kver="$(strings "${kernel_file}" 2>/dev/null | grep -oP '^\d+\.\d+\.\d+' | head -1 || true)"
        fi
    fi

    if [[ -z "${kver}" ]]; then
        error "Could not determine kernel version from boot.img"
        exit 1
    fi

    echo "${kver}"
}

# Detect whether the kernel is GKI-compatible by checking for certain markers.
detect_gki() {
    local boot="$1"
    local unpack_dir="${WORK_DIR}/boot_header"
    local kernel_file="${unpack_dir}/boot.img-kernel"

    # GKI kernels typically have "android1[2-5]-" in their version string
    if [[ -f "${kernel_file}" ]]; then
        if strings "${kernel_file}" 2>/dev/null | grep -qP '\d+\.\d+\.\d+-android1[2-9]'; then
            return 0
        fi
    fi

    return 1
}

# Download the latest KernelSU LKM (.ko) matching a kernel version.
download_kernelsu_lkm() {
    local kver="$1"
    local dest="$2"
    local kver_major_minor
    kver_major_minor="$(echo "${kver}" | grep -oP '^\d+\.\d+')"

    step "Fetching latest KernelSU release info"
    local releases_json
    releases_json="$(curl -fsSL "${KERNELSU_GH_API}?per_page=30")"

    # Look for an asset whose name contains the kernel major.minor and ends in .ko
    local download_url=""
    download_url="$(echo "${releases_json}" | jq -r --arg kv "${kver_major_minor}" '
        [.[] | .assets[]
         | select(.name | test("(?i)kernelsu.*" + $kv + ".*\\.ko$"))
        ] | first | .browser_download_url // empty
    ')"

    # Broader fallback: any .ko asset from the latest release
    if [[ -z "${download_url}" ]]; then
        download_url="$(echo "${releases_json}" | jq -r '
            [.[] | .assets[] | select(.name | test("(?i)\\.ko$"))]
            | first | .browser_download_url // empty
        ')"
    fi

    if [[ -z "${download_url}" ]]; then
        warn "No KernelSU LKM (.ko) found for kernel ${kver}"
        return 1
    fi

    info "Downloading KernelSU LKM from: ${download_url}"
    curl -fsSL -o "${dest}" "${download_url}"
    success "Downloaded KernelSU LKM"
}

# Download the KernelSU kernel patcher tool.
download_kernelsu_patcher() {
    local dest="$1"

    step "Fetching latest KernelSU release info for patcher"
    local releases_json
    releases_json="$(curl -fsSL "${KERNELSU_GH_API}?per_page=30")"

    local arch
    arch="$(uname -m)"
    case "${arch}" in
        x86_64)  arch="x86_64" ;;
        aarch64) arch="aarch64" ;;
        *)       arch="x86_64" ;;
    esac

    # Look for the patcher binary (ksud or similar)
    local download_url=""
    download_url="$(echo "${releases_json}" | jq -r --arg arch "${arch}" '
        [.[] | .assets[]
         | select(.name | test("(?i)(ksud|patcher).*" + $arch + ".*linux"))
        ] | first | .browser_download_url // empty
    ')"

    # Broader fallback: any ksud linux asset
    if [[ -z "${download_url}" ]]; then
        download_url="$(echo "${releases_json}" | jq -r '
            [.[] | .assets[] | select(.name | test("(?i)ksud.*linux"))]
            | first | .browser_download_url // empty
        ')"
    fi

    if [[ -z "${download_url}" ]]; then
        error "Could not find KernelSU patcher binary in releases"
        return 1
    fi

    info "Downloading KernelSU patcher from: ${download_url}"
    curl -fsSL -o "${dest}" "${download_url}"
    chmod +x "${dest}"
    success "Downloaded KernelSU patcher"
}

# Download KernelSU Manager APK.
download_manager_apk() {
    step "Downloading KernelSU Manager APK"

    local releases_json
    releases_json="$(curl -fsSL "${KERNELSU_MANAGER_GH_API}?per_page=30")"

    local download_url=""
    download_url="$(echo "${releases_json}" | jq -r '
        [.[] | .assets[] | select(.name | test("(?i)manager.*\\.apk$"))]
        | first | .browser_download_url // empty
    ')"

    # Fallback: any .apk asset
    if [[ -z "${download_url}" ]]; then
        download_url="$(echo "${releases_json}" | jq -r '
            [.[] | .assets[] | select(.name | test("(?i)\\.apk$"))]
            | first | .browser_download_url // empty
        ')"
    fi

    if [[ -z "${download_url}" ]]; then
        warn "Could not find KernelSU Manager APK in releases; skipping"
        return 0
    fi

    mkdir -p "$(dirname "${KERNELSU_MANAGER_DEST}")"
    info "Downloading from: ${download_url}"
    curl -fsSL -o "${KERNELSU_MANAGER_DEST}" "${download_url}"
    success "KernelSU Manager APK saved to ${KERNELSU_MANAGER_DEST}"
}

# Verify an image file by checking header magic bytes.
verify_image() {
    local img="$1"
    local label="$2"

    if [[ ! -f "${img}" ]]; then
        error "${label} not found at ${img}"
        return 1
    fi

    local magic
    magic="$(xxd -l 8 -p "${img}" 2>/dev/null || od -A n -t x1 -N 8 "${img}" | tr -d ' \n')"

    # Android boot image magic: "ANDROID!" = 414e44524f494421
    if echo "${magic}" | grep -qi "^414e44524f494421"; then
        success "${label} has valid Android boot image header"
        return 0
    fi

    # Vendor boot image magic: "VNDRBOOT" = 564e4452424f4f54
    if echo "${magic}" | grep -qi "^564e4452424f4f54"; then
        success "${label} has valid vendor boot image header"
        return 0
    fi

    warn "${label} header magic not recognized (${magic}); image may still be valid"
    return 0
}

# ── Mode A: GKI module injection ─────────────────────────────────────────────
mode_gki() {
    local kver="$1"
    step "Mode A: GKI module injection into vendor_boot"

    local vb_dir="${WORK_DIR}/vendor_boot"
    mkdir -p "${vb_dir}"

    # 1. Download KernelSU LKM
    local ko_file="${WORK_DIR}/kernelsu.ko"
    if ! download_kernelsu_lkm "${kver}" "${ko_file}"; then
        warn "LKM download failed; falling back to Mode B"
        MODE="patch"
        mode_patch "${kver}"
        return
    fi

    # 2. Unpack vendor_boot
    info "Unpacking vendor_boot.img"
    unpackbootimg --boot_img "${VENDOR_BOOT_IMG}" --out "${vb_dir}"

    # 3. Find and extract vendor ramdisk
    local ramdisk_file
    ramdisk_file="$(find "${vb_dir}" -name '*vendor_ramdisk*' -o -name '*ramdisk*' | head -1)"
    if [[ -z "${ramdisk_file}" || ! -f "${ramdisk_file}" ]]; then
        warn "Could not locate vendor ramdisk; falling back to Mode B"
        MODE="patch"
        mode_patch "${kver}"
        return
    fi

    local ramdisk_dir="${WORK_DIR}/vendor_ramdisk"
    mkdir -p "${ramdisk_dir}"

    info "Extracting vendor ramdisk"
    (cd "${ramdisk_dir}" && gzip -dc "${ramdisk_file}" 2>/dev/null | cpio -idm 2>/dev/null) || \
    (cd "${ramdisk_dir}" && lz4 -dc "${ramdisk_file}" 2>/dev/null | cpio -idm 2>/dev/null) || \
    (cd "${ramdisk_dir}" && cat "${ramdisk_file}" | cpio -idm 2>/dev/null) || true

    if [[ ! -d "${ramdisk_dir}" ]] || [[ -z "$(ls -A "${ramdisk_dir}" 2>/dev/null)" ]]; then
        warn "Vendor ramdisk extraction produced empty result; falling back to Mode B"
        MODE="patch"
        mode_patch "${kver}"
        return
    fi

    # 4. Inject kernelsu.ko
    local modules_dir="${ramdisk_dir}/lib/modules"
    mkdir -p "${modules_dir}"

    # Remove any existing kernelsu module for idempotency
    rm -f "${modules_dir}"/kernelsu*.ko

    cp "${ko_file}" "${modules_dir}/kernelsu.ko"
    success "Injected kernelsu.ko into /lib/modules/"

    # 5. Repack vendor ramdisk
    info "Repacking vendor ramdisk"
    local new_ramdisk="${WORK_DIR}/vendor_ramdisk_new.cpio.gz"
    (cd "${ramdisk_dir}" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "${new_ramdisk}")

    # 6. Repack vendor_boot.img
    info "Repacking vendor_boot.img"

    local out_vendor_boot="${OUTPUT_DIR}/vendor_boot.img"

    # Gather mkbootimg arguments from unpacked header files
    local mkboot_args=()
    mkboot_args+=(--vendor_ramdisk "${new_ramdisk}")

    # Read header version
    local header_version_file="${vb_dir}/$(basename "${VENDOR_BOOT_IMG}")-header_version"
    if [[ -f "${header_version_file}" ]]; then
        mkboot_args+=(--header_version "$(cat "${header_version_file}" | tr -d '[:space:]')")
    fi

    # Read page size
    local pagesize_file="${vb_dir}/$(basename "${VENDOR_BOOT_IMG}")-pagesize"
    if [[ -f "${pagesize_file}" ]]; then
        mkboot_args+=(--pagesize "$(cat "${pagesize_file}" | tr -d '[:space:]')")
    fi

    # Read kernel base
    local base_file="${vb_dir}/$(basename "${VENDOR_BOOT_IMG}")-base"
    if [[ -f "${base_file}" ]]; then
        mkboot_args+=(--base "$(cat "${base_file}" | tr -d '[:space:]')")
    fi

    # Read dtb if present
    local dtb_file="${vb_dir}/$(basename "${VENDOR_BOOT_IMG}")-dtb"
    if [[ -f "${dtb_file}" && -s "${dtb_file}" ]]; then
        mkboot_args+=(--dtb "${dtb_file}")
    fi

    # Read vendor cmdline
    local cmdline_file="${vb_dir}/$(basename "${VENDOR_BOOT_IMG}")-vendor_cmdline"
    if [[ -f "${cmdline_file}" ]]; then
        mkboot_args+=(--vendor_cmdline "$(cat "${cmdline_file}")")
    fi

    # Read board/name
    local board_file="${vb_dir}/$(basename "${VENDOR_BOOT_IMG}")-board"
    if [[ -f "${board_file}" ]]; then
        local board_val
        board_val="$(cat "${board_file}" | tr -d '[:space:]')"
        if [[ -n "${board_val}" ]]; then
            mkboot_args+=(--board "${board_val}")
        fi
    fi

    mkbootimg --vendor_boot "${out_vendor_boot}" "${mkboot_args[@]}"
    success "Repacked vendor_boot.img -> ${out_vendor_boot}"

    # 7. Copy original boot.img to output (unmodified for Mode A)
    cp "${BOOT_IMG}" "${OUTPUT_DIR}/boot.img"
    info "Copied original boot.img to output directory"
}

# ── Mode B: Kernel Image patching ────────────────────────────────────────────
mode_patch() {
    local kver="$1"
    step "Mode B: Kernel Image binary patching"

    local boot_dir="${WORK_DIR}/boot"
    mkdir -p "${boot_dir}"

    # 1. Unpack boot.img
    info "Unpacking boot.img"
    unpackbootimg --boot_img "${BOOT_IMG}" --out "${boot_dir}"

    local kernel_file="${boot_dir}/boot.img-kernel"
    if [[ ! -f "${kernel_file}" ]]; then
        # Try alternate naming
        kernel_file="$(find "${boot_dir}" -name '*kernel*' | head -1)"
    fi
    if [[ -z "${kernel_file}" || ! -f "${kernel_file}" ]]; then
        error "Could not find kernel Image in unpacked boot.img"
        exit 1
    fi

    # 2. Download KernelSU patcher
    local patcher="${WORK_DIR}/ksud"
    download_kernelsu_patcher "${patcher}"

    # 3. Patch the kernel Image
    info "Patching kernel Image with KernelSU"
    "${patcher}" patch-kernel "${kernel_file}" || {
        # Some versions use a different subcommand
        "${patcher}" patch "${kernel_file}" || {
            error "KernelSU patcher failed"
            exit 1
        }
    }
    success "Kernel Image patched successfully"

    # 4. Repack boot.img
    info "Repacking boot.img"

    local out_boot="${OUTPUT_DIR}/boot.img"
    local mkboot_args=()
    mkboot_args+=(--kernel "${kernel_file}")

    # Ramdisk
    local ramdisk_file="${boot_dir}/boot.img-ramdisk"
    if [[ -f "${ramdisk_file}" ]]; then
        mkboot_args+=(--ramdisk "${ramdisk_file}")
    fi

    # Header version
    local header_version_file="${boot_dir}/boot.img-header_version"
    if [[ -f "${header_version_file}" ]]; then
        mkboot_args+=(--header_version "$(cat "${header_version_file}" | tr -d '[:space:]')")
    fi

    # OS version
    local os_version_file="${boot_dir}/boot.img-os_version"
    if [[ -f "${os_version_file}" ]]; then
        mkboot_args+=(--os_version "$(cat "${os_version_file}" | tr -d '[:space:]')")
    fi

    # OS patch level
    local os_patch_file="${boot_dir}/boot.img-os_patch_level"
    if [[ -f "${os_patch_file}" ]]; then
        mkboot_args+=(--os_patch_level "$(cat "${os_patch_file}" | tr -d '[:space:]')")
    fi

    # Page size
    local pagesize_file="${boot_dir}/boot.img-pagesize"
    if [[ -f "${pagesize_file}" ]]; then
        mkboot_args+=(--pagesize "$(cat "${pagesize_file}" | tr -d '[:space:]')")
    fi

    # Base address
    local base_file="${boot_dir}/boot.img-base"
    if [[ -f "${base_file}" ]]; then
        mkboot_args+=(--base "$(cat "${base_file}" | tr -d '[:space:]')")
    fi

    # Kernel offset
    local kernel_offset_file="${boot_dir}/boot.img-kernel_offset"
    if [[ -f "${kernel_offset_file}" ]]; then
        mkboot_args+=(--kernel_offset "$(cat "${kernel_offset_file}" | tr -d '[:space:]')")
    fi

    # Ramdisk offset
    local ramdisk_offset_file="${boot_dir}/boot.img-ramdisk_offset"
    if [[ -f "${ramdisk_offset_file}" ]]; then
        mkboot_args+=(--ramdisk_offset "$(cat "${ramdisk_offset_file}" | tr -d '[:space:]')")
    fi

    # Tags offset
    local tags_offset_file="${boot_dir}/boot.img-tags_offset"
    if [[ -f "${tags_offset_file}" ]]; then
        mkboot_args+=(--tags_offset "$(cat "${tags_offset_file}" | tr -d '[:space:]')")
    fi

    # Command line
    local cmdline_file="${boot_dir}/boot.img-cmdline"
    if [[ -f "${cmdline_file}" ]]; then
        mkboot_args+=(--cmdline "$(cat "${cmdline_file}")")
    fi

    # Board
    local board_file="${boot_dir}/boot.img-board"
    if [[ -f "${board_file}" ]]; then
        local board_val
        board_val="$(cat "${board_file}" | tr -d '[:space:]')"
        if [[ -n "${board_val}" ]]; then
            mkboot_args+=(--board "${board_val}")
        fi
    fi

    # DTB
    local dtb_file="${boot_dir}/boot.img-dtb"
    if [[ -f "${dtb_file}" && -s "${dtb_file}" ]]; then
        mkboot_args+=(--dtb "${dtb_file}")
    fi

    mkbootimg --output "${out_boot}" "${mkboot_args[@]}"
    success "Repacked boot.img -> ${out_boot}"

    # Copy vendor_boot.img if provided (unmodified for Mode B)
    if [[ -n "${VENDOR_BOOT_IMG}" ]]; then
        cp "${VENDOR_BOOT_IMG}" "${OUTPUT_DIR}/vendor_boot.img"
        info "Copied original vendor_boot.img to output directory"
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    check_tools

    # Set up working directory
    WORK_DIR="$(mktemp -d -t kernelsu-patch.XXXXXX)"
    info "Working directory: ${WORK_DIR}"

    # Create output directory (idempotent)
    mkdir -p "${OUTPUT_DIR}"

    # Parse kernel version from boot.img
    step "Parsing kernel version from boot.img"
    local kver
    kver="$(get_kernel_version "${BOOT_IMG}")"
    success "Kernel version: ${kver}"

    # Decide integration mode
    if [[ -n "${VENDOR_BOOT_IMG}" ]]; then
        info "vendor_boot.img provided; attempting GKI detection"
        if detect_gki "${BOOT_IMG}"; then
            success "GKI kernel detected; using Mode A (GKI module injection)"
            MODE="gki"
        else
            warn "GKI detection failed; falling back to Mode B (kernel patch)"
            MODE="patch"
        fi
    else
        info "No vendor_boot.img provided; using Mode B (kernel patch)"
        MODE="patch"
    fi

    # Execute selected mode
    if [[ "${MODE}" == "gki" ]]; then
        mode_gki "${kver}"
    else
        mode_patch "${kver}"
    fi

    # Verify output images
    step "Verifying output images"
    if [[ -f "${OUTPUT_DIR}/boot.img" ]]; then
        verify_image "${OUTPUT_DIR}/boot.img" "boot.img"
    fi
    if [[ -f "${OUTPUT_DIR}/vendor_boot.img" ]]; then
        verify_image "${OUTPUT_DIR}/vendor_boot.img" "vendor_boot.img"
    fi

    # Download KernelSU Manager APK
    download_manager_apk

    # Summary
    echo ""
    step "Done!"
    info "Mode used: ${MODE}"
    info "Output directory: ${OUTPUT_DIR}"
    ls -lh "${OUTPUT_DIR}/"*.img 2>/dev/null || true
    if [[ -f "${KERNELSU_MANAGER_DEST}" ]]; then
        info "Manager APK: ${KERNELSU_MANAGER_DEST}"
    fi
}

main "$@"
