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
- SoC: Qualcomm TurboX C8550 (SM8750-class, Kryo CPU, Adreno GPU)
- Storage: UFS (flash via EDL/QSaharaServer + fh_loader)
- Boot chain: XBL → UEFI (uefi.elf) → ABL (abl.elf) → Linux kernel
- Hypervisor: Qualcomm hypvm (vm-bootsys partitions, vm-persist)
- Partitions: Dynamic super (sparse, 8 chunks), GPT across 6 LUNs
- Verified Boot: AVB 2.0 (vbmeta.img, vbmeta_system.img)
- Kernel: GKI 2.0 likely (separate boot.img + vendor_boot.img)
- Modem: NON-HLOS.bin (~260MB), BTFM.bin, dspso.bin
- Form factor: Dual-screen handheld, integrated gamepad

## Stock Firmware Partition Map
Derived from gpt_main*.bin and rawprogram*.xml files.
Document every partition: name, LUN, start sector, size, image file.
Note which partitions are in the dynamic super group.
(To be populated after firmware analysis with scripts/unpack-super.sh)

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
- Closest upstream: identify from LineageOS device list for SM8650/SM8750
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
- **Add a new gsmlg-app**: Place APK in packages/gsmlg-apps/prebuilt/, add entry in Android.mk, add to apps.mk PRODUCT_PACKAGES
- **Update blobs**: Run scripts/extract-blobs.sh with mounted stock partitions, commit vendor/ changes
- **Switch kernel**: Replace kernel/ayaneo/sm8750/Image, update BoardConfig.mk if boot header changes
- **Disable GApps for testing**: Build with `./scripts/build.sh --no-gapps` (debug only, non-standard)

## Pitfalls
- super partition is sparse AND split into 8 chunks — must concat then unsparse
- vm-bootsys and vm-persist are hypervisor partitions — do NOT overwrite
- Stock ABL and UEFI must be preserved (no custom bootloader)
- vbmeta must be flashed with --disable-verity --disable-verification
- persist.img contains calibration data — never overwrite
