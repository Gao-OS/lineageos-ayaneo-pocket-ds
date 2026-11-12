# LineageOS 24 for Ayaneo Pocket DS

<!-- badges -->
![LineageOS 24](https://img.shields.io/badge/LineageOS-24-green)
![Android 17](https://img.shields.io/badge/Android-17-blue)
![Device](https://img.shields.io/badge/Device-Ayaneo%20Pocket%20DS-orange)
![Build Status](https://img.shields.io/badge/Build-WIP-yellow)

Port of LineageOS 24 (Android 17) for the **Ayaneo Pocket DS** handheld gaming device.

## About

This project builds a complete LineageOS 24 ROM for the Ayaneo Pocket DS with:

- **LineageOS 24** — Full Android 17 custom ROM
- **MindTheGapps** — Google Apps (Play Store, GMS, SetupWizard) baked into /system
- **gsmlg-apps** — Prebuilt APKs from the gsmlg-app GitHub org in /product
- **KernelSU** — Root solution integrated as GKI kernel module

Every build includes all four components by default. There is no "vanilla" build target.

## Hardware

| Component | Detail |
|---|---|
| SoC | Thundercomm TurboX C8550 (Qualcomm QCS8550 "kalama", SM8550 class, Adreno 740) |
| Form Factor | Dual-screen handheld with integrated gamepad |
| Storage | UFS (flash via EDL/QSaharaServer or fastboot) |
| Boot Chain | XBL → UEFI → ABL → Linux kernel (GKI 2.0) |
| Partitions | Dynamic super (sparse, 8 chunks), GPT across 6 LUNs |
| Verified Boot | AVB 2.0 (must disable for custom ROM) |
| Stock OS | Android 13 |

## Prerequisites

**Hardware:**
- Ayaneo Pocket DS with **unlocked bootloader**
- USB-C cable
- PC running Linux (x86_64)

**Software:**
- [Nix](https://nixos.org/) package manager
- [devenv](https://devenv.sh/) — automatically provides all build tools
- ~200GB free disk space (AOSP source + build output)
- ~16GB RAM minimum (32GB recommended)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/Gao-OS/lineageos-ayaneo-pocket-ds.git
cd lineageos-ayaneo-pocket-ds

# 2. Enter dev environment (Nix installs all tools automatically)
devenv shell

# 3. Init + sync LineageOS source (~100GB download)
repo init -u https://github.com/LineageOS/android.git -b lineage-24.0 --git-lfs --depth=1
mkdir -p .repo/local_manifests
cp local_manifests/* .repo/local_manifests/
repo sync -c -j$(nproc) --force-sync --no-tags

# 4. Build
source build/envsetup.sh
lunch lineage_pocket_ds-userdebug
mka bacon

# 5. Flash (device in fastboot mode)
./scripts/flash.sh
```

Or use the all-in-one script:

```bash
./scripts/build.sh --all
```

## Build Configuration

The `scripts/build.sh` script supports individual phases:

| Flag | Description |
|---|---|
| `--all` | Run all phases (default) |
| `--init` | Phase 1: repo init + sync |
| `--extract` | Phase 2: Unpack firmware + extract blobs |
| `--patch` | Phase 3: Apply KernelSU patch |
| `--build` | Phase 4: lunch + mka bacon |
| `--clean` | Clean build directory before building |
| `--jobs N` | Override build parallelism |
| `--variant <userdebug\|user\|eng>` | Build variant (default: userdebug) |
| `--no-gapps` | Build without GApps (debug only, prints warning) |

### Customizing gsmlg-apps

Add a new prebuilt app:

1. Place APK in `packages/gsmlg-apps/prebuilt/YourApp.apk`
2. Add an `android_app_import` block in `packages/gsmlg-apps/Android.bp`
3. Add package name to `packages/gsmlg-apps/apps.mk`

### Switching Kernel

Replace `kernel/ayaneo/qcs8550/Image` and the matching module directories next to it, and update `BOARD_BOOT_HEADER_VERSION` in `BoardConfig.mk` if the header format changes.

### Disabling GApps (for testing)

```bash
./scripts/build.sh --build --no-gapps
```

This is non-standard and only for debugging. The default build always includes GApps.

## Flashing

### Fastboot (standard — for LineageOS)

```bash
# Boot into fastboot
adb reboot bootloader

# Flash
./scripts/flash.sh

# With factory reset
./scripts/flash.sh --wipe

# Preview what will be flashed
./scripts/flash.sh --dry-run
```

### EDL (Emergency Download — for recovery/stock restore)

```bash
# Device must be in EDL mode (Vol- + power while connecting USB)
./scripts/flash.sh --edl --image-dir stock-firmware/ufs
```

## Branch Strategy

| Branch | Android | LineageOS | Status |
|---|---|---|---|
| `main` | 17 | 24 (`lineage-24.0`) | **Active** |

The first bringup targeted LineageOS 21; that state ends at commit `65a48d3`.

## Device-Specific Notes

### Dual Screens
The Pocket DS has two screens. This requires:
- Display HAL configuration for dual outputs
- Framework overlays for secondary display management
- Custom display policies in `device/ayaneo/pocket_ds/overlay/`

### Gamepad
Integrated gamepad mapping via keylayout files in `device/ayaneo/pocket_ds/keylayout/`.

### Partitions to Preserve
**NEVER overwrite these partitions:**
- `vm-bootsys`, `vm-persist` — Qualcomm hypervisor (bricking risk)
- `persist` — calibration data (WiFi, BT, sensors)
- `xbl`, `uefi`, `abl` — bootloader chain (use stock)

### Verified Boot
vbmeta must be flashed with verification disabled:
```bash
fastboot flash vbmeta vbmeta.img --disable-verity --disable-verification
```

## Directory Structure

```
device/ayaneo/pocket_ds/   — Device tree (BoardConfig, overlays, sepolicy, makefiles)
vendor/ayaneo/pocket_ds/   — Proprietary blobs extracted from stock firmware
kernel/ayaneo/qcs8550/     — Prebuilt stock kernel, DTB/DTBO and kernel modules
packages/gsmlg-apps/       — Prebuilt APKs with Android.bp integration
scripts/                   — Automation scripts:
  ├── build.sh             — Full build orchestration
  ├── flash.sh             — Flash via fastboot or EDL
  ├── unpack-super.sh      — Unpack split sparse super partition
  ├── unpack-boot.sh       — Unpack boot/vendor_boot/dtbo/init_boot images
  ├── extract-blobs.sh     — Dump stock partitions and extract proprietary blobs
  ├── patch-kernelsu.sh    — Patch KernelSU into boot/vendor_boot
  ├── fetch-gapps.sh       — Download MindTheGapps (fallback)
  └── fetch-gsmlg-apps.sh  — Download gsmlg-app APKs
local_manifests/           — repo manifest fragments for device/gapps/kernel repos
stock-firmware/            — Gitignored directory for raw firmware dump
```

## Contributing

1. **Adding blobs**: Populate `device/ayaneo/pocket_ds/proprietary-files.txt` with paths, run `scripts/extract-blobs.sh`
2. **Testing**: Build with `--variant eng` for full debug access
3. **SELinux**: Add policies in `device/ayaneo/pocket_ds/sepolicy/`
4. **Overlays**: Framework resource overlays go in `device/ayaneo/pocket_ds/overlay/`

## Troubleshooting

### Bootloop after flash
- Ensure vbmeta was flashed with `--disable-verity --disable-verification`
- Check that all dynamic partitions were flashed (use fastbootd mode)
- Verify stock bootloader partitions (xbl, uefi, abl) are intact

### Missing blobs at runtime
- Check logcat for `dlopen failed` or `HIDL service not found` errors
- Add missing files to `proprietary-files.txt` and re-extract
- Rebuild vendor.mk after extraction

### SafetyNet / Play Integrity failure
- Ensure KernelSU is properly integrated (Mode A preferred)
- Check build fingerprint in `lineage_pocket_ds.mk`
- Verify `ro.debuggable=0` in user builds

### Build fails with missing dependencies
- `ALLOW_MISSING_DEPENDENCIES=true` is set by devenv for bringup
- Missing AOSP tools (mkbootimg, lpunpack): build from source after repo sync

## Credits

- [LineageOS](https://lineageos.org/) — Custom Android ROM
- [KernelSU](https://kernelsu.org/) — Kernel-based root solution
- [MindTheGapps](https://gitlab.com/nicholaschum/mindthegapps) — Google Apps package
- [Ayaneo](https://www.ayaneo.com/) — Hardware manufacturer
- Qualcomm / Thundercomm — SoC and module vendor (TurboX C8550 / QCS8550)
- [LineageOS AYN Odin 2 maintainers](https://github.com/LineageOS/android_device_ayn_qcs8550-common) — the QCS8550 device trees this port is derived from

## License

Device tree and scripts: Apache License 2.0. Proprietary blobs retain their original licenses.
