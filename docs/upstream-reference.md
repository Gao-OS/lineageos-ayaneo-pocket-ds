# Upstream LineageOS Reference for the Pocket DS

## Platform

The Ayaneo Pocket DS is built on the Thundercomm TurboX C8550 module, which is
a Qualcomm **QCS8550**. Its platform codename is **kalama** (SM8550 class).

It is not SM8750 "sun", which earlier revisions of this project assumed.
The evidence is in the stock firmware:

| Check | Result |
|---|---|
| `compatible` strings in the stock DTB | only `qcom,kalama*` |
| Board model in the stock DTBO | "Kalama QRD, Graph-DVT" / "Graph-PVT" |
| Kernel | 5.15.104 android13 (SM8750 ships 6.6) |
| `ro.board.platform` in stock vendor | `kalama` |

## Reference trees

The AYN Odin 2 family uses the same QCS8550 BSP and is officially supported
on `lineage-24.0`.

| Tree | Used for |
|---|---|
| [android_device_ayn_qcs8550-common](https://github.com/LineageOS/android_device_ayn_qcs8550-common) | BoardConfig, product config, init scripts, VINTF, properties, blob list layout |
| [android_device_ayn_odin2thor](https://github.com/LineageOS/android_device_ayn_odin2thor) | Dual-screen configuration (AYN Thor) |
| [android_device_ayn_odin2](https://github.com/LineageOS/android_device_ayn_odin2) | FocalTech fingerprint through the Lineage AIDL wrapper |
| [android_hardware_ayn](https://github.com/LineageOS/android_hardware_ayn) | Fingerprint SELinux rules, common overlays |

Of the 773 paths in AYN's common `proprietary-files.txt`, 762 exist at the
same path in the Pocket DS stock firmware.

The Pocket DS tree is a single tree derived from these. It does not inherit
from them at build time, because the AYN trees pull in AYN's kernel sources
and AYN-only packages.

## What differs from AYN

| Area | AYN | Pocket DS |
|---|---|---|
| Kernel | Built from source | Prebuilt stock `Image`, DTB, DTBO and modules (no sources published) |
| Gamepad | MCU that appears as an Xbox 360 pad | `vendor.aks.gamepad@1.0` HAL plus `aks-adc-joystick` kernel module |
| Fan | — | `fan_service`, `charger_fan_speed.sh`, Thundercomm `tsnv` HAL |
| Sound card | `kalama-qrd` | `kalama-qrd-dvt` on retail boards |
| Fingerprint helper | `ff_ta.elf` | `vendor.focaltech.hardware.biometrics.fingerprint@1.0-service` |
| WiFi Display | Blobs pinned from another device | Not included |
| Thermal engine | `thermal-engine-v2` blob | Not present in stock |

## Still to do on hardware

These need a running device and are not configured yet:

- **Display layout.** The Thor tree ships `display_layout_configuration.xml`,
  `device_state_configuration.xml`, `display_settings.xml` and one
  `display_id_<address>.xml` per panel. They are keyed by the physical display
  address, which has to be read with `dumpsys display` on the Pocket DS.
- **Touch to display mapping.** One `.idc` file per touchscreen with
  `touch.displayId`, as Thor does for `fts_ts` and `fts_ts_secondary`.
- **Display orientation.** Thor sets
  `ro.surface_flinger.primary_display_orientation`; the Pocket DS values are
  unknown.
- **Ayaneo keys and fan curves.** The framework side of the gamepad HAL and
  the fan control UI lived in Ayaneo's system apps.
