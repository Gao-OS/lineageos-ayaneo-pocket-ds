# LineageOS 21 Port for Ayaneo Pocket DS — PRD & Execution Plan

## Project Overview

**Goal**: Port LineageOS 21 (Android 14) to the Ayaneo Pocket DS handheld gaming device, with GApps, gsmlg-apps, and KernelSU baked into the default build.

**Repository**: `Gao-OS/lineageos-ayaneo-pocket-ds`
**Target SoC**: Qualcomm TurboX C8550 (SM8750 / Snapdragon 8 Elite class)
**Stock OS**: Android 13 (source: `AR11_FlatBuild_TurboX_C8550_xx.xx_LA1.0.D.user.20251012.065902`)
**Branch strategy**: Start `lineage-21`, future `lineage-22`, `lineage-23`

---

## Hardware Profile (from stock firmware analysis)

| Component | Detail |
|---|---|
| SoC | Qualcomm TurboX C8550 (SM8750-class, Kryo CPU, Adreno GPU) |
| Storage | UFS (flash via EDL/QSaharaServer + fh_loader) |
| Boot chain | XBL → UEFI (uefi.elf) → ABL (abl.elf) → Linux kernel |
| Hypervisor | Qualcomm hypvm (vm-bootsys partitions, vm-persist) |
| Partitions | Dynamic super (sparse, 8 chunks), GPT across 6 LUNs |
| Verified Boot | AVB 2.0 (vbmeta.img, vbmeta_system.img) |
| Kernel | GKI 2.0 likely (separate boot.img + vendor_boot.img) |
| Modem | NON-HLOS.bin (~260MB), BTFM.bin, dspso.bin |
| Form factor | Dual-screen handheld, integrated gamepad |

---

## Build Defaults

The default `lineage_pocket_ds-userdebug` build MUST include:

1. **LineageOS 21** — base system
2. **MindTheGapps** — GApps (GmsCore, Play Store, SetupWizard, etc.), built into /system at compile time
3. **gsmlg-apps** — prebuilt APKs from `gsmlg-app` GitHub org, installed to /product
4. **KernelSU** — root solution, integrated as GKI kernel module (preferred) or patched into kernel source

---

## Execution Prompts

Each prompt below is a self-contained unit of work for Claude Code. Execute sequentially. Each prompt's output should be committed before proceeding.

---

### Prompt 1: Repository Scaffolding & devenv.nix

**Context**: We are creating the initial repository structure with a Nix-based dev environment for AOSP/LineageOS builds.

**Task**: Initialize the git repository `lineageos-ayaneo-pocket-ds` with the following structure and files:

```
lineageos-ayaneo-pocket-ds/
├── .gitignore
├── .envrc                          # direnv: use devenv
├── devenv.nix                      # Nix dev environment
├── devenv.lock
├── devenv.yaml
├── CLAUDE.md                       # AI context file (created in Prompt 2)
├── README.md
├── local_manifests/
│   ├── device.xml                  # device + vendor + kernel repos
│   ├── gapps.xml                   # MindTheGapps manifest
│   ├── gsmlg-apps.xml             # gsmlg-app prebuilts manifest
│   └── kernelsu.xml               # KernelSU manifest
├── device/
│   └── ayaneo/
│       └── pocket_ds/
│           ├── AndroidProducts.mk
│           ├── BoardConfig.mk
│           ├── device.mk
│           ├── lineage_pocket_ds.mk
│           ├── vendorsetup.sh
│           ├── extract-files.sh
│           ├── proprietary-files.txt  # placeholder
│           ├── gapps.mk
│           ├── gsmlg-apps.mk
│           ├── sepolicy/
│           │   └── .gitkeep
│           ├── overlay/
│           │   └── .gitkeep
│           └── keylayout/
│               └── .gitkeep
├── kernel/
│   └── ayaneo/
│       └── sm8750/
│           └── .gitkeep
├── vendor/
│   └── ayaneo/
│       └── pocket_ds/
│           └── .gitkeep
├── packages/
│   └── gsmlg-apps/
│       ├── Android.mk
│       ├── apps.mk
│       └── prebuilt/
│           └── .gitkeep
├── scripts/
│   ├── extract-blobs.sh
│   ├── unpack-super.sh
│   ├── unpack-boot.sh
│   ├── patch-kernelsu.sh
│   ├── fetch-gapps.sh
│   ├── fetch-gsmlg-apps.sh
│   └── build.sh
└── stock-firmware/
    └── .gitkeep
```

**devenv.nix requirements**:
- Language: Nix with devenv framework
- Packages needed: `repo` (Android repo tool), `android-tools` (adb, fastboot), `simg2img`, `unpackbootimg`, `mkbootimg`, `lpunpack`, `lpmake`, `e2fsprogs`, `python3`, `jdk17`, `git-lfs`, `zip`, `unzip`, `curl`, `xxd`, `bc`, `rsync`, `xmlstarlet` (for parsing rawprogram XML)
- Shell hook: print build instructions, set JAVA_HOME, set `ALLOW_MISSING_DEPENDENCIES=true`
- Android build env vars: `USE_CCACHE=1`, `CCACHE_EXEC` pointing to ccache, `LC_ALL=C`
- Note: some packages (simg2img, unpackbootimg, lpunpack) may not be in nixpkgs — provide fallback shell commands to build from AOSP source or use pre-built binaries

**.gitignore** must include:
```
stock-firmware/ufs/
*.img
*.bin
*.elf
*.mbn
*.melf
*.fv
out/
.repo/
ccache/
*.pyc
```

**README.md**: Project title, description, quickstart (devenv shell, repo init/sync, lunch, build), branch strategy table, credits.

**Commit message**: `feat: initial repository scaffolding with devenv.nix`

---

### Prompt 2: CLAUDE.md — Full Project Context

**Context**: Create the CLAUDE.md that will serve as the canonical reference for all future Claude Code sessions on this project.

**Task**: Create `CLAUDE.md` at the repo root with these sections:

```markdown
# CLAUDE.md — LineageOS 21 for Ayaneo Pocket DS

## Project Identity
- Repo: Gao-OS/lineageos-ayaneo-pocket-ds
- Target: Ayaneo Pocket DS (Qualcomm TurboX C8550 / SM8750)
- Base: LineageOS 21 (Android 14)
- Stock: Android 13 flat build (AR11_FlatBuild_TurboX_C8550)

## Build Defaults
Every build includes: LineageOS + MindTheGapps + gsmlg-apps + KernelSU.
This is non-negotiable. No "vanilla" build target exists.

## Hardware Specifications
[Full SoC details, partition layout from rawprogram XMLs, boot chain,
hypervisor partitions, dual-screen info, gamepad HID, UFS LUN mapping]

## Stock Firmware Partition Map
[Derived from gpt_main*.bin and rawprogram*.xml files]
[Document every partition: name, LUN, start sector, size, image file]
[Note which partitions are in the dynamic super group]

## Boot Chain
XBL (xbl_s.melf) → UEFI (uefi.elf) → ABL (abl.elf) → kernel (boot.img)
- Hypervisor: hypvm.mbn loads before kernel
- TrustZone: tz.mbn
- Verified Boot: AVB 2.0, vbmeta must be disabled or re-signed

## Kernel Strategy
- Stock kernel is GKI 2.0 (verify from boot.img header)
- Start with prebuilt kernel extracted from stock boot.img
- KernelSU as GKI kernel module (not patched into source)
- vendor_boot.img contains vendor ramdisk + vendor kernel modules
- DTB/DTBO in separate partitions

## KernelSU Integration
- Preferred: GKI module injected into vendor_boot ramdisk
- scripts/patch-kernelsu.sh automates this
- KernelSU manager APK bundled as system app
- Must pass SafetyNet/Play Integrity basic attestation

## GApps (MindTheGapps)
- Synced via local_manifests/gapps.xml
- Included via device/ayaneo/pocket_ds/gapps.mk
- Inherits vendor/gapps/arm64/arm64-vendor.mk
- Built into /system at compile time

## gsmlg-apps
- Source: github.com/gsmlg-app org
- Prebuilt APKs in packages/gsmlg-apps/prebuilt/
- Installed to /product partition (user-removable)
- Each app defined in packages/gsmlg-apps/Android.mk as LOCAL_PREBUILT

## Device Tree Reference
- Closest upstream: [identify from LineageOS device list for SM8650/SM8750]
- Qualcomm common: device/qcom/common, hardware/qcom-caf
- Display: dual-screen needs framework overlay + display HAL config
- Input: gamepad keylayout in device/ayaneo/pocket_ds/keylayout/

## Build Commands
```bash
# Enter dev environment
devenv shell

# Initialize LineageOS source
repo init -u https://github.com/LineageOS/android.git -b lineage-21.0 --git-lfs
cp local_manifests/* .repo/local_manifests/
repo sync -c -j$(nproc) --force-sync --no-tags

# Build
source build/envsetup.sh
lunch lineage_pocket_ds-userdebug
mka bacon
```

## Directory Conventions
- device/ — device tree (BoardConfig, overlays, sepolicy)
- vendor/ — proprietary blobs extracted from stock
- kernel/ — prebuilt or source kernel
- packages/gsmlg-apps/ — prebuilt APKs with Android.mk
- scripts/ — automation (extract, unpack, patch, build)
- local_manifests/ — repo manifest fragments
- stock-firmware/ — gitignored, raw firmware dump

## Key Decisions
1. Start lineage-21 (A14) because stock A13 blobs are closest compatible
2. MindTheGapps over OpenGApps — officially supported by LineageOS
3. KernelSU GKI module over Magisk — cleaner, no boot image patching at flash time
4. Prebuilt kernel first, source-built kernel later
5. gsmlg-apps in /product not /system — user can remove if desired

## Common Tasks
[Document: how to add a new gsmlg-app, how to update blobs,
how to switch kernel, how to disable GApps for testing]

## Pitfalls
- super partition is sparse AND split into 8 chunks — must concat then unsparse
- vm-bootsys and vm-persist are hypervisor partitions — do NOT overwrite
- Stock ABL and UEFI must be preserved (no custom bootloader)
- vbmeta must be flashed with --disable-verity --disable-verification
- persist.img contains calibration data — never overwrite
```

**Commit message**: `docs: add CLAUDE.md with full device and build context`

---

### Prompt 3: Stock Firmware Unpacking Scripts

**Context**: The stock firmware is at `stock-firmware/ufs/`. The super partition is split into 8 sparse chunks (`super_1.img` through `super_8.img`). We need scripts to unpack everything for blob extraction.

**Task**: Create these scripts in `scripts/`:

#### scripts/unpack-super.sh
1. Concatenate `super_1.img` through `super_8.img` into `super_combined_sparse.img`
2. Run `simg2img` to convert sparse → raw `super_combined.img`
3. Run `lpunpack super_combined.img output_dir/` to extract logical partitions (system, vendor, product, system_ext, odm)
4. Mount each partition image read-only (using loop device) to a temp directory for blob extraction
5. Print summary of extracted partitions and sizes

#### scripts/unpack-boot.sh
1. Unpack `boot.img` using `unpackbootimg` → extract kernel Image, ramdisk, DTB, boot header info
2. Unpack `vendor_boot.img` → vendor ramdisk, vendor kernel modules, vendor DTB
3. Unpack `dtbo.img` → individual DTB overlays
4. Unpack `init_boot.img` → generic ramdisk (GKI)
5. Print kernel version string from Image, list extracted modules from vendor_boot

#### scripts/extract-blobs.sh
1. Takes mount points of system, vendor, product, system_ext, odm as arguments
2. Reads `device/ayaneo/pocket_ds/proprietary-files.txt` line by line
3. Copies each listed file from the mounted partitions to `vendor/ayaneo/pocket_ds/proprietary/`
4. Generates `vendor/ayaneo/pocket_ds/vendor.mk` and `vendor/ayaneo/pocket_ds/BoardConfigVendor.mk` with `PRODUCT_COPY_FILES` entries
5. Generates SHA256 manifest of all extracted blobs

All scripts must:
- Be POSIX-compatible bash with `set -euo pipefail`
- Check for required tools at the top and exit with clear error if missing
- Accept `--help` flag
- Use color output for status messages
- Be idempotent (safe to re-run)

**Commit message**: `feat: add firmware unpacking and blob extraction scripts`

---

### Prompt 4: KernelSU Integration Script

**Context**: KernelSU for GKI kernels works by patching the kernel image or injecting a module into the boot ramdisk. We need a script that automates this.

**Task**: Create `scripts/patch-kernelsu.sh`:

1. Accept arguments: `--boot <boot.img>` and optionally `--vendor-boot <vendor_boot.img>`
2. Download the latest KernelSU release matching the kernel version (parse from boot.img header)
3. Two integration modes:
   - **Mode A (GKI module)**: Unpack vendor_boot, inject `kernelsu.ko` into vendor ramdisk's `/lib/modules/`, repack vendor_boot.img
   - **Mode B (Kernel patch)**: Unpack boot.img, patch the kernel Image binary with KernelSU's patcher tool, repack boot.img
4. Default to Mode A (GKI module), fall back to Mode B if GKI detection fails
5. Verify output images are valid (check header magic)
6. Also download KernelSU Manager APK and place it in `packages/gsmlg-apps/prebuilt/KernelSUManager.apk`

**Commit message**: `feat: add KernelSU integration script`

---

### Prompt 5: Device Tree — BoardConfig.mk

**Context**: BoardConfig.mk defines the hardware characteristics of the device for the build system. Values must match the stock firmware's partition layout.

**Task**: Create `device/ayaneo/pocket_ds/BoardConfig.mk`:

```makefile
# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv9-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := kryo

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-2a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_VARIANT := cortex-a76

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := pocket_ds
TARGET_NO_BOOTLOADER := true  # ABL handles this

# Kernel
# Start with prebuilt — switch to source-built later
TARGET_PREBUILT_KERNEL := kernel/ayaneo/sm8750/Image
BOARD_BOOT_HEADER_VERSION := 4  # verify from stock boot.img
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_BASE := 0x00000000  # verify from unpackbootimg
BOARD_RAMDISK_USE_LZ4 := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true  # GKI
BOARD_MOVE_GSI_AVB_KEYS_TO_VENDOR_BOOT := true

# Partitions — populate sizes from GPT analysis
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296        # 96MB (from boot.img)
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296 # 96MB (from vendor_boot.img)
BOARD_DTBOIMG_PARTITION_SIZE := 12582912           # 12MB
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608    # 8MB
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600    # 100MB

# Dynamic partitions (super)
BOARD_SUPER_PARTITION_SIZE := 9126805504  # sum of super_*.img raw sizes — VERIFY
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 9122611200  # super size minus overhead
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product system_ext odm

# Filesystem
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_ODM := odm

# Recovery
TARGET_RECOVERY_FSTAB := device/ayaneo/pocket_ds/rootdir/fstab.default
BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_USERIMAGES_USE_F2FS := true

# Verified Boot
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3  # disable verification

# SELinux
include device/qcom/sepolicy/SEPolicy.mk
BOARD_VENDOR_SEPOLICY_DIRS += device/ayaneo/pocket_ds/sepolicy

# HIDL
DEVICE_MANIFEST_FILE := device/ayaneo/pocket_ds/manifest.xml
DEVICE_MATRIX_COMPATIBILITY_MATRIX_FILE := hardware/qcom-caf/common/compatibility_matrix.xml

# Properties
TARGET_SYSTEM_PROP += device/ayaneo/pocket_ds/system.prop
TARGET_VENDOR_PROP += device/ayaneo/pocket_ds/vendor.prop
```

Include TODO comments for every value that needs verification from the actual firmware dump.

Also create placeholder files referenced by BoardConfig:
- `device/ayaneo/pocket_ds/rootdir/fstab.default` (skeleton from stock)
- `device/ayaneo/pocket_ds/manifest.xml` (HIDL/AIDL manifest, skeleton)
- `device/ayaneo/pocket_ds/system.prop`
- `device/ayaneo/pocket_ds/vendor.prop`

**Commit message**: `feat: add BoardConfig.mk and device configuration skeletons`

---

### Prompt 6: Device Tree — Product Makefiles

**Context**: These makefiles define what the build includes. This is where GApps, gsmlg-apps, and KernelSU get wired in.

**Task**: Create these files:

#### device/ayaneo/pocket_ds/device.mk
- Inherit from Qualcomm common (placeholder path, will need adjustment after repo sync)
- Include `gapps.mk`
- Include `gsmlg-apps.mk`
- Set product properties: display density, screen size, Bluetooth, WiFi, NFC flags
- Include KernelSU module in `PRODUCT_PACKAGES`
- Ship stock firmware blobs for modem, WiFi, BT, DSP
- Set `PRODUCT_PACKAGES` for standard Qualcomm HALs

#### device/ayaneo/pocket_ds/lineage_pocket_ds.mk
- Inherit from `device.mk`
- Inherit from `vendor/lineage/config/common_full_phone.mk`
- Set: `PRODUCT_NAME := lineage_pocket_ds`
- Set: `PRODUCT_DEVICE := pocket_ds`
- Set: `PRODUCT_BRAND := Ayaneo`
- Set: `PRODUCT_MODEL := Pocket DS`
- Set: `PRODUCT_MANUFACTURER := Ayaneo`

#### device/ayaneo/pocket_ds/AndroidProducts.mk
- Define `COMMON_LUNCH_CHOICES` with `lineage_pocket_ds-userdebug` and `lineage_pocket_ds-user`

#### device/ayaneo/pocket_ds/vendorsetup.sh
- Add lunch combo

#### device/ayaneo/pocket_ds/gapps.mk
- Conditional include of MindTheGapps vendor makefile
- `WITH_GAPPS := true` flag
- Error message if MindTheGapps not synced

#### device/ayaneo/pocket_ds/gsmlg-apps.mk
- Include `packages/gsmlg-apps/apps.mk`
- Define the list of gsmlg-app packages

#### packages/gsmlg-apps/Android.mk
- Template for prebuilt APK inclusion
- One `include $(CLEAR_VARS)` / `include $(BUILD_PREBUILT)` block per app
- Initially just KernelSU Manager as the first app entry
- Comments explaining how to add more apps

#### packages/gsmlg-apps/apps.mk
- `PRODUCT_PACKAGES` list aggregating all gsmlg-app package names

**Commit message**: `feat: add product makefiles with GApps, gsmlg-apps, and KernelSU integration`

---

### Prompt 7: Local Manifests for repo sync

**Context**: LineageOS uses `repo` (Android repo tool) with XML manifests. Local manifests in `.repo/local_manifests/` add our custom repos to the sync.

**Task**: Create these manifest XMLs in `local_manifests/`:

#### local_manifests/device.xml
```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <!-- Device tree -->
  <project name="Gao-OS/lineageos-ayaneo-pocket-ds"
           path="device/ayaneo/pocket_ds"
           remote="github"
           revision="lineage-21" />

  <!-- Vendor blobs -->
  <project name="Gao-OS/android_vendor_ayaneo_pocket_ds"
           path="vendor/ayaneo/pocket_ds"
           remote="github"
           revision="lineage-21" />

  <!-- Kernel prebuilt -->
  <project name="Gao-OS/android_kernel_ayaneo_sm8750"
           path="kernel/ayaneo/sm8750"
           remote="github"
           revision="lineage-21" />
</manifest>
```

#### local_manifests/gapps.xml
- Add MindTheGapps repo for lineage-21 (arm64)

#### local_manifests/gsmlg-apps.xml
- Add gsmlg-apps prebuilt repo

#### local_manifests/kernelsu.xml
- Add KernelSU source or prebuilt module repo if applicable

Include `<remote>` definitions for GitHub if not already in the main manifest.

**Commit message**: `feat: add local_manifests for device, GApps, gsmlg-apps, KernelSU`

---

### Prompt 8: Build Orchestration Script

**Context**: `scripts/build.sh` should be the single entry point to go from zero to flashable ZIP.

**Task**: Create `scripts/build.sh` that orchestrates the full build:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Phases (each can be run independently via flags):
# --init        : repo init + sync
# --extract     : unpack firmware + extract blobs
# --patch       : apply KernelSU patch
# --build       : lunch + mka bacon
# --all         : run everything (default)

# Phase 1: Init
# - repo init LineageOS 21
# - copy local_manifests
# - repo sync

# Phase 2: Extract (requires stock firmware in stock-firmware/ufs/)
# - run unpack-super.sh
# - run unpack-boot.sh
# - run extract-blobs.sh
# - run fetch-gapps.sh (download MindTheGapps if not synced)
# - run fetch-gsmlg-apps.sh (download/update gsmlg-app APKs)

# Phase 3: Patch
# - run patch-kernelsu.sh on extracted boot/vendor_boot

# Phase 4: Build
# - source build/envsetup.sh
# - lunch lineage_pocket_ds-userdebug
# - mka bacon
# - copy output ZIP to out/release/

# Print summary: output file path, size, SHA256
```

Flags:
- `--clean` : make clean before build
- `--jobs N` : override -j parallelism
- `--variant <userdebug|user|eng>` : build variant
- `--no-gapps` : skip GApps (for debug builds only — prints warning that this is non-standard)
- `--help` : usage

**Commit message**: `feat: add build orchestration script`

---

### Prompt 9: Flash Script

**Context**: Flashing requires fastboot for most partitions, but EDL (Emergency Download) mode via QSaharaServer + fh_loader is needed for full reflash. We need both paths.

**Task**: Create `scripts/flash.sh`:

**Fastboot mode** (default — for flashing LineageOS after initial stock flash):
1. Flash boot, vendor_boot, dtbo, init_boot, vbmeta (with verification disabled)
2. Flash super image (or individual logical partitions via fastbootd)
3. Wipe userdata
4. Reboot

**EDL mode** (`--edl` flag — for recovery or full reflash):
1. Use QSaharaServer and fh_loader from stock firmware
2. Parse rawprogram*.xml and patch*.xml
3. Flash all partitions per stock layout
4. Note: this restores stock, useful for recovery

Both modes:
- Check device connection (adb/fastboot/EDL)
- Confirm with user before flashing
- Print partition table before/after
- `--dry-run` flag for testing

**Commit message**: `feat: add flash script with fastboot and EDL support`

---

### Prompt 10: Documentation — README.md Full Version

**Context**: Replace the skeleton README with a comprehensive one.

**Task**: Write `README.md` with:

1. **Project title + badges** (build status placeholder, LineageOS version, device)
2. **About** — what this is, what's included (GApps, gsmlg-apps, KernelSU)
3. **Prerequisites** — hardware (Ayaneo Pocket DS, USB cable, unlocked bootloader), software (Nix, devenv)
4. **Quick Start** — 5-step from clone to flash
5. **Build Configuration** — how to customize (add/remove gsmlg-apps, switch kernel, disable GApps for testing)
6. **Branch Strategy** — table of lineage-21/22/23 with status
7. **Device-Specific Notes** — dual screen, gamepad, hypervisor partitions to preserve
8. **Contributing** — how to add blobs, test, submit device tree changes
9. **Troubleshooting** — common issues (bootloop, missing blobs, SafetyNet)
10. **Credits** — LineageOS, KernelSU, MindTheGapps, Ayaneo

**Commit message**: `docs: comprehensive README with build and flash instructions`

---

## Execution Order Summary

| # | Prompt | Deliverable | Depends On |
|---|--------|-------------|------------|
| 1 | Repo scaffolding | Directory structure, devenv.nix, .gitignore | — |
| 2 | CLAUDE.md | Full project context for AI sessions | 1 |
| 3 | Unpack scripts | unpack-super.sh, unpack-boot.sh, extract-blobs.sh | 1 |
| 4 | KernelSU script | patch-kernelsu.sh | 1 |
| 5 | BoardConfig | BoardConfig.mk + skeletons | 1 |
| 6 | Product makefiles | device.mk, lineage_pocket_ds.mk, gapps.mk, gsmlg-apps.mk | 5 |
| 7 | Local manifests | XML manifests for repo sync | 1 |
| 8 | Build script | build.sh orchestrator | 3, 4, 6, 7 |
| 9 | Flash script | flash.sh (fastboot + EDL) | 1 |
| 10 | README | Full documentation | all |

## Post-Scaffolding Work (Manual / Next Phase)

These require the actual stock firmware and are NOT part of the scaffolding prompts:

1. **Run unpack-super.sh** on real firmware → get actual partition sizes
2. **Run unpack-boot.sh** → verify GKI, get kernel version, extract prebuilt
3. **Update BoardConfig.mk** with real values from firmware analysis
4. **Populate proprietary-files.txt** from vendor/odm blob catalog
5. **Run extract-blobs.sh** → fill vendor/ayaneo/pocket_ds/
6. **Identify closest upstream device tree** from LineageOS for SM8750 reference
7. **First build attempt** → debug, iterate
8. **First boot** → logcat, fix HALs, iterate
9. **Dual-screen bringup** → display HAL config, framework overlay
10. **Gamepad mapping** → keylayout files, HID config
