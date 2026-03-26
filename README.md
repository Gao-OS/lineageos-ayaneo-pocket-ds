# LineageOS 21 for Ayaneo Pocket DS

Port of LineageOS 21 (Android 14) for the Ayaneo Pocket DS handheld gaming device.

Every build includes **LineageOS 21 + MindTheGapps + gsmlg-apps + KernelSU** by default.

## Hardware

| Component | Detail |
|---|---|
| SoC | Qualcomm TurboX C8550 (SM8750-class) |
| Form Factor | Dual-screen handheld with integrated gamepad |
| Storage | UFS |
| Stock OS | Android 13 |

## Prerequisites

- [Nix](https://nixos.org/) with [devenv](https://devenv.sh/) installed
- Ayaneo Pocket DS with unlocked bootloader
- USB cable (USB-C)
- ~200GB free disk space for AOSP source + build

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/Gao-OS/lineageos-ayaneo-pocket-ds.git
cd lineageos-ayaneo-pocket-ds

# 2. Enter dev environment (installs all build tools via Nix)
devenv shell

# 3. Initialize LineageOS source and sync
repo init -u https://github.com/LineageOS/android.git -b lineage-21.0 --git-lfs
cp local_manifests/* .repo/local_manifests/
repo sync -c -j$(nproc) --force-sync --no-tags

# 4. Build
source build/envsetup.sh
lunch lineage_pocket_ds-userdebug
mka bacon

# 5. Flash (with device in fastboot mode)
./scripts/flash.sh
```

Or use the all-in-one build script:

```bash
./scripts/build.sh --all
```

## Build Configuration

| Flag | Description |
|---|---|
| `--no-gapps` | Build without GApps (debug only, non-standard) |
| `--variant <user\|userdebug\|eng>` | Build variant |
| `--clean` | Clean build |
| `--jobs N` | Override parallelism |

## Branch Strategy

| Branch | Android | LineageOS | Status |
|---|---|---|---|
| `lineage-21` | 14 | 21 | Active |
| `lineage-22` | 15 | 22 | Planned |
| `lineage-23` | 16 | 23 | Planned |

## Device-Specific Notes

- **Dual screens**: Requires display HAL configuration and framework overlays
- **Gamepad**: Integrated gamepad needs custom keylayout files
- **Hypervisor partitions**: `vm-bootsys` and `vm-persist` must NOT be overwritten
- **Persist partition**: Contains calibration data — never flash
- **AVB**: vbmeta must be flashed with `--disable-verity --disable-verification`

## Directory Structure

```
device/ayaneo/pocket_ds/  — Device tree (BoardConfig, overlays, sepolicy)
vendor/ayaneo/pocket_ds/  — Proprietary blobs extracted from stock
kernel/ayaneo/sm8750/     — Prebuilt or source kernel
packages/gsmlg-apps/      — Prebuilt APKs with Android.mk
scripts/                  — Automation (extract, unpack, patch, build)
local_manifests/          — repo manifest fragments
stock-firmware/           — Gitignored, raw firmware dump location
```

## Credits

- [LineageOS](https://lineageos.org/)
- [KernelSU](https://kernelsu.org/)
- [MindTheGapps](https://gitlab.com/nicholaschum/mindthegapps)
- [Ayaneo](https://www.ayaneo.com/)

## License

Device tree and scripts are Apache 2.0. Proprietary blobs retain their original licenses.
