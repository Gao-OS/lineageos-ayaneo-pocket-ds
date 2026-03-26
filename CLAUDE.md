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
- Kernel: GKI 2.0 confirmed (init_boot.img present in stock firmware)
- Modem: NON-HLOS.bin (~260MB), BTFM.bin, dspso.bin
- Form factor: Dual-screen handheld, integrated gamepad

## Stock Firmware

**File:** `stock-firmware/AR11_FlatBuild_TurboX_C8550_xx.xx_LA1.0.D.user.20251012.065902.zip`
**Build date:** 2025-10-12 | **Android:** 13 (flat/user build)

### Flash Tools (zip root)
| File | Purpose |
|------|---------|
| `QSaharaServer` | EDL Sahara protocol host binary |
| `fh_loader` | EDL Firehose loader |
| `turbox_flat_flash.sh` | Full-device flash script |
| `Turbox_download_config_flat.xml` | fh_loader flash configuration |

### UFS Partition Images (`ufs/`)

**GPT tables — 6 LUNs (0–5)**
- `gpt_main{0-5}.bin` / `gpt_backup{0-5}.bin`

**Boot chain**
| File | Role |
|------|------|
| `xbl_s.melf` | XBL (primary bootloader) |
| `xbl_s_devprg_ns.melf` | XBL dev programmer (EDL) |
| `XblRamdump.elf` | XBL ramdump |
| `xbl_config.elf` | XBL configuration |
| `shrm.elf` | SHRM firmware |
| `uefi.elf` | UEFI (2.8 MB) |
| `uefi_sec.mbn` | UEFI secure |
| `abl.elf` | Android Bootloader (ABL) |
| `cpucp.elf` | CPU control processor |

**TrustZone / Security**
| File | Role |
|------|------|
| `tz.mbn` | TrustZone (3.9 MB) |
| `hypvm.mbn` | Qualcomm Hypervisor (1.6 MB) |
| `devcfg.mbn` | Device config |
| `aop_devcfg.mbn` | AOP device config |
| `keymint.mbn` | KeyMint (400 KB) |
| `featenabler.mbn` | Feature enabler |
| `storsec.mbn` | Storage security |
| `multi_image.mbn` / `multi_image_qti.mbn` | Multi-image signing |

**Kernel / Boot images**
| File | Size | Notes |
|------|------|-------|
| `boot.img` | 96 MB | GKI kernel + ramdisk |
| `init_boot.img` | 8 MB | Confirms **GKI 2.0** |
| `vendor_boot.img` | 96 MB | Vendor ramdisk + modules |
| `recovery.img` | 100 MB | Recovery partition |
| `dtbo.img` | 12 MB | Device Tree Blob Overlay |
| `vmlinux` | 464 MB | Uncompressed kernel ELF |

**Dynamic super (8 sparse chunks)**
- `super_1.img` through `super_8.img`
- Must concat all chunks then unsparse before analysis

**Verified Boot**
- `vbmeta.img` (8 KB) — AVB root
- `vbmeta_system.img` (4 KB) — AVB system chain

**Modem / Wireless**
| File | Size | Role |
|------|------|------|
| `NON-HLOS.bin` | 260 MB | Modem firmware (ADSP) |
| `BTFM.bin` | 1.2 MB | Bluetooth + FM |
| `dspso.bin` | 64 MB | DSP firmware |

**Hypervisor partitions (do NOT overwrite)**
- `vm-bootsys_1.img` through `vm-bootsys_9.img`
- `vm-persist_1.img`

**Other partitions**
| File | Notes |
|------|-------|
| `persist.img` | 32 MB — calibration data, never overwrite |
| `metadata_{1-5}.img` | Dynamic partition metadata |
| `userdata_{1-10}.img` | Userdata (formatted) |
| `dummy_frp.bin` | Factory Reset Protection placeholder |
| `logfs_ufs_8mb.bin` | Log filesystem |
| `zeros_5sectors.bin` | Padding / GPT alignment |

**UEFI / firmware volumes**
- `tools.fv` (384 KB) — UEFI tools firmware volume
- `imagefv.elf` — UEFI image firmware volume
- `qupv3fw.elf` — QUP v3 peripheral firmware

**Flash program/patch XMLs** (for fh_loader)
- `rawprogram{0-5}.xml` — sparse program scripts per LUN
- `rawprogram_unsparse{0,4}.xml` — unsparse program scripts
- `patch{0-5}.xml` — patch scripts per LUN

## Stock Firmware Partition Map

Derived from rawprogram*.xml and lpdump analysis. Sector size = 4096 bytes on all LUNs.

### LUN 0 — `rawprogram_unsparse0.xml`
Main data LUN. Contains super (dynamic partitions), metadata, userdata, rawdump.

| Partition | Image | Size |
|-----------|-------|------|
| persist | `persist.img` | 32 MB |
| super (8 chunks) | `super_{1-8}.img` | ~5.6 GB (raw, not sparse) |
| vbmeta_system_a/b | `vbmeta_system.img` | 64 KB |
| metadata (5 chunks) | `metadata_{1-5}.img` | ~10 MB |
| rawdump | — | ~12.2 GB |
| userdata (10 chunks) | `userdata_{1-10}.img` | extends to end of disk |

### LUN 1 — `rawprogram1.xml` (XBL slot A)
| Partition | Image | Size |
|-----------|-------|------|
| xbl_a | `xbl_s.melf` | 3.5 MB |
| xbl_config_a | `xbl_config.elf` | 300 KB |
| multiimgqti_a | `multi_image_qti.mbn` | 32 KB |
| multiimgoem_a | `multi_image.mbn` | 32 KB |

### LUN 2 — `rawprogram2.xml` (XBL slot B, empty at factory)

### LUN 3 — `rawprogram3.xml` (DDR training)
| Partition | Size |
|-----------|------|
| cdt | 128 KB |
| ddr | 1 MB |

### LUN 4 — `rawprogram_unsparse4.xml` (main firmware, A/B)

**Slot A (flashed at factory)**
| Partition | Image | Size |
|-----------|-------|------|
| uefi_a | `uefi.elf` | 5 MB |
| aop_a | `aop.mbn` | 512 KB |
| tz_a | `tz.mbn` | 4 MB |
| hyp_a | `hypvm.mbn` | 8 MB |
| modem_a | `NON-HLOS.bin` | 320 MB |
| bluetooth_a | `BTFM.bin` | 6 MB |
| abl_a | `abl.elf` | 1 MB |
| dsp_a | `dspso.bin` | 64 MB |
| keymaster_a | `keymint.mbn` | 512 KB |
| boot_a | `boot.img` | 96 MB |
| vbmeta_a | `vbmeta.img` | 64 KB |
| dtbo_a | `dtbo.img` | 24 MB |
| vm-bootsys_a | `vm-bootsys_{1-9}.img` | ~490 MB total |
| cpucp_a | `cpucp.elf` | 1 MB |
| vendor_boot_a | `vendor_boot.img` | 96 MB |
| recovery_a | `recovery.img` | 100 MB |
| init_boot_a | `init_boot.img` | 8 MB (confirms GKI 2.0) |

**Slot-independent (LUN 4)**
| Partition | Image | Size |
|-----------|-------|------|
| splash | — | ~33 MB |
| toolsfv | `tools.fv` | 1 MB |
| logfs | `logfs_ufs_8mb.bin` | 8 MB |
| logdump | — | 512 MB |
| storsec | `storsec.mbn` | 128 KB |
| vm-persist | `vm-persist_1.img` | ~119 MB |

### LUN 5 — `rawprogram5.xml` (modem NV, never overwrite)
| Partition | Size |
|-----------|------|
| modemst1 | 3 MB |
| modemst2 | 3 MB |
| fsg | 3 MB |
| fsc | 128 KB |

### Dynamic Super Partition (lpdump)
- **Total super size**: 6,442,450,944 bytes (6 GiB)
- **Dynamic group max**: 6,438,256,640 bytes
- **Header flags**: virtual_ab_device
- **A/B slots**: Only slot A populated at factory

| Logical Partition | Sectors | Size |
|-------------------|---------|------|
| system_ext_a | 4,445,592 | 2.2 GB |
| vendor_a | 3,014,464 | 1.5 GB |
| system_a | 2,323,616 | 1.2 GB |
| product_a | 1,613,984 | 789 MB |
| vendor_dlkm_a | 248,208 | 121 MB |
| odm_a | 2,584 | 1.3 MB |
| system_dlkm_a | 856 | 428 KB |

### Partitions to NEVER Overwrite
- `persist` (LUN 0) — NV calibration data
- `modemst1`, `modemst2`, `fsg`, `fsc` (LUN 5) — modem RF calibration
- `vm-bootsys_a/b`, `vm-persist`, `vm-data` (LUN 4) — Qualcomm hypervisor
- `storsec` (LUN 4) — storage security fuses

## Boot Chain
XBL (xbl_s.melf) → UEFI (uefi.elf) → ABL (abl.elf) → kernel (boot.img)
- Hypervisor: hypvm.mbn loads before kernel
- TrustZone: tz.mbn
- Verified Boot: AVB 2.0, vbmeta must be disabled or re-signed

## Kernel Details (from stock firmware analysis)
- **Version**: 5.15.104-g59fb11f14619 (android13, SMP preempt aarch64)
- **GKI 2.0**: confirmed (init_boot.img = 8 MB separate partition, boot.img ramdisk = 0)
- **Boot header version**: 4
- **Image format**: PE/COFF (arm64 Image, 45 MB)
- **Vendor modules**: 306 .ko files in vendor_boot ramdisk (lz4 compressed)
- **DTB**: 4.5 MB FDT in vendor_boot.img
- **Prebuilt**: extracted to kernel/ayaneo/sm8750/Image
- **Vendor cmdline**: `video=vfb:640x400,bpp=32,memsize=3072000 qcom_geni_serial.con_enabled=0 nosoftlockup bootconfig`
- **Bootconfig**: `androidboot.hardware=qcom androidboot.memcg=1 androidboot.usbcontroller=a600000.dwc3`
- **OS version**: Android 13.0.0, patch level 2023-06

## Kernel Strategy
- Stock kernel is GKI 2.0 (confirmed by init_boot.img in stock firmware)
- Start with prebuilt kernel extracted from stock boot.img
- KernelSU as GKI kernel module (not patched into source)
- vendor_boot.img contains vendor ramdisk + 306 vendor kernel modules
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
