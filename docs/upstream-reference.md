# Upstream LineageOS Reference for SM8750 (sun platform)

## Primary Reference: OnePlus 13 "dodge"

**Repository:** `LineageOS/android_device_oneplus_sm8750-common`
**Branch:** `lineage-23.0`
**Device codename:** `dodge` (OnePlus 13)
**SoC platform:** SM8750 "sun"

### GitHub URLs

| Repository | URL |
|------------|-----|
| Common device tree | https://github.com/LineageOS/android_device_oneplus_sm8750-common |
| Device-specific tree | https://github.com/LineageOS/android_device_oneplus_dodge |
| Vendor blobs | https://github.com/LineageOS/android_vendor_oneplus_dodge |

### Why This Is the Best Reference

1. **Same SoC platform.** The OnePlus 13 uses SM8750, identical to the Qualcomm TurboX C8550 in the Ayaneo Pocket DS. Both are on the Qualcomm "sun" platform, sharing the same kernel BSP, HAL interfaces, and Qualcomm-CAF driver tree.

2. **Closest to lineage-21.0 in the SM8750 family.** LineageOS 23.0 (Android 15) is the branch where OnePlus 13 is developed upstream; this is the nearest in-tree SM8750 reference available. The gap between lineage-21.0 (Android 14) and lineage-23.0 (Android 15) is smaller than any gap between different SoC generations.

3. **Actively maintained in LineageOS.** The `android_device_oneplus_sm8750-common` tree is maintained by the LineageOS organization, meaning it tracks upstream Qualcomm-CAF changes and LineageOS build system conventions that are directly applicable.

4. **GKI 2.0 baseline.** The dodge device tree is built around GKI 2.0 (kernel 5.15/6.1 with separate init_boot partition), the same boot image architecture confirmed in the Ayaneo Pocket DS stock firmware.

---

## Key Files to Reference

When building the `device/ayaneo/pocket_ds` tree, cross-reference these files from `android_device_oneplus_sm8750-common`:

### BoardConfig.mk
- `TARGET_BOARD_PLATFORM := sun` — platform name for SM8750
- `TARGET_BOOTLOADER_BOARD_NAME` — set to TurboX/Ayaneo value, not "dodge"
- `BOARD_KERNEL_PAGESIZE`, `BOARD_BOOT_HEADER_VERSION` — must match stock boot.img (header v4 confirmed)
- `BOARD_USES_QCOM_HARDWARE := true`
- `TARGET_USES_64_BIT_BINDER := true`
- Dynamic partition declarations (`BOARD_SUPER_PARTITION_SIZE`, `BOARD_DYNAMIC_PARTITIONS_SIZE`)
- AVB flags (`BOARD_AVB_ENABLE := true`, rollback index settings)
- `BOARD_KERNEL_SEPARATED_DTBO := true`
- GKI 2.0 flags: `BOARD_RAMDISK_USE_LZ4`, `BOARD_USES_GENERIC_KERNEL_IMAGE`

### device.mk
- `PRODUCT_SHIPPING_API_LEVEL` — set appropriately for Android 14 target
- Qualcomm HAL package lists (audio, camera, display, sensors, thermal, vibrator)
- `PRODUCT_USES_QCOM_HARDWARE` overlays
- `ro.vendor.qti.va_aosp.support` and related Qualcomm properties

### sepolicy/
- Qualcomm-CAF vendor sepolicy base — reuse the `qcom` vendor sepolicy directory structure
- Device-specific denials will differ (different peripherals), but the Qualcomm HAL contexts are identical
- Start from the sm8750-common sepolicy and add Ayaneo-specific rules on top

### overlay/
- `frameworks/base/core/res/res/xml/config_display*.xml` — display density, cutout, rotation
- These will need significant changes for the dual-screen form factor

---

## What to KEEP from the Reference

| Area | Keep As-Is | Notes |
|------|-----------|-------|
| `TARGET_BOARD_PLATFORM` | `sun` | SM8750 platform name is identical |
| Qualcomm HAL packages | Most of the list | Same SoC = same HALs |
| Audio policy config paths | `/vendor/etc/audio_policy_configuration.xml` pattern | Qualcomm audio HAL paths are stable |
| Camera provider HAL | `android.hardware.camera.provider@2.7-service_64` | Same ISP pipeline |
| Display HAL | `android.hardware.graphics.composer@2.4-service` | Same Adreno GPU |
| Thermal HAL | `android.hardware.thermal@2.0-service.qti` | Same thermal subsystem |
| Keymaster/KeyMint | `android.hardware.security.keymint-service.qti` | Same TrustZone |
| Sepolicy base | `qcom/` vendor policy tree | Shared Qualcomm platform |
| Build fingerprint format | Follow the pattern | Adjust to Ayaneo values |
| `BOARD_SUPER_PARTITION_SIZE` | 6,442,450,944 | Matches Ayaneo lpdump (6 GiB) |

---

## What to CHANGE for Ayaneo Pocket DS

| Area | Change | Reason |
|------|--------|--------|
| `TARGET_BOOTLOADER_BOARD_NAME` | `ayaneo` or `pocket_ds` | Device identity |
| Display overlays | Dual-screen configuration | Ayaneo has two displays; OnePlus 13 has one |
| Input / keylayout | Gamepad keylayout files | Integrated gamepad is unique to Ayaneo |
| `ro.product.*` properties | Ayaneo branding | Model name, manufacturer, device |
| Bluetooth SoC name | Confirm from stock blobs | May differ from OnePlus 13 config |
| Camera device IDs | Extract from stock vendor | Different camera module |
| NFC config | Absent or different | Verify Ayaneo hardware |
| Fingerprint HAL | May be absent | Ayaneo Pocket DS form factor |
| USB product ID (`idProduct`) | Ayaneo-specific | Different USB descriptor |
| `PRODUCT_MODEL` / `PRODUCT_BRAND` | `Ayaneo Pocket DS` | Branding |
| Audio path configs | Validate against stock | Speaker/headphone topology differs |

---

## Secondary References

### Other SM8750 Devices in LineageOS

At the time of writing (lineage-23.0), the OnePlus 13 "dodge" is the primary confirmed SM8750 device in the LineageOS tree. Additional SM8750 ("sun") devices may exist in the following namespaces:

- `LineageOS/android_device_oneplus_*` — other OnePlus SM8750 variants
- `LineageOS/android_device_xiaomi_*` — Xiaomi SM8750 devices (e.g., Xiaomi 15 series)
- `LineageOS/android_device_samsung_*` — Samsung SM8750 devices (Galaxy S25 series)

**Important:** Samsung and Xiaomi SM8750 devices may use different display, audio, and camera HAL configurations than OnePlus. Use them as secondary references for specific subsystem configs only, not as a BoardConfig base.

### Qualcomm CAF Common Trees

These are platform-level trees that all SM8750 devices inherit:

| Repository | URL |
|------------|-----|
| Qualcomm common device | https://github.com/LineageOS/android_device_qcom_common |
| Qualcomm hardware CAF | https://github.com/LineageOS/android_hardware_qcom_display |
| Qualcomm audio HAL | https://github.com/LineageOS/android_hardware_qcom_audio |

---

## Manifest Note

The OnePlus 13 sm8750-common tree is NOT included in `local_manifests/device.xml` as a build-time
dependency — it is a **reference only**. Files and patterns should be manually adapted into
`device/ayaneo/pocket_ds` rather than inherited at build time.

To browse the reference tree during development, clone it separately:

```bash
git clone https://github.com/LineageOS/android_device_oneplus_sm8750-common \
    -b lineage-23.0 \
    /tmp/sm8750-common-reference
```
