#
# Device makefile for Ayaneo Pocket DS
#

# Inherit from Qualcomm common (path may need adjustment after repo sync)
# $(call inherit-product, device/qcom/common/common.mk)

# GApps (MindTheGapps)
$(call inherit-product, device/ayaneo/pocket_ds/gapps.mk)

# gsmlg-apps
$(call inherit-product, device/ayaneo/pocket_ds/gsmlg-apps.mk)

# Audio — SM8750 uses AIDL audio HAL (libaudiocorehal.qti).
# The QTI audio service binary ships as a vendor blob; no PRODUCT_PACKAGES
# entry needed here (extracted via extract-blobs.sh into vendor makefile).
# NOTE: Previously listed android.hardware.audio@7.0-impl (HIDL) — removed;
#       SM8750 does not use HIDL audio.

# Display — SM8750 uses Composer3 (AIDL) via QTI display CAF.
# The gralloc/composer binaries ship as vendor blobs.
# Only the mapper is a framework-built impl that must be declared here.
PRODUCT_PACKAGES += \
    android.hardware.graphics.mapper@4.0-impl-qti-display

# Thermal — AIDL thermal HAL. Service binary name is well-defined in QTI tree.
PRODUCT_PACKAGES += \
    android.hardware.thermal-service.qti

# Device properties
PRODUCT_PROPERTY_OVERRIDES += \
    ro.sf.lcd_density=320 \
    persist.sys.usb.config=mtp,adb

# Shipping API level
PRODUCT_SHIPPING_API_LEVEL := 33

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    device/ayaneo/pocket_ds \
    packages/gsmlg-apps

# Keylayout — integrated gamepad
# NOTE: filename must match the HID device name; rename after first boot.
PRODUCT_COPY_FILES += \
    device/ayaneo/pocket_ds/keylayout/Ayaneo_Pocket_DS_Gamepad.kl:$(TARGET_COPY_OUT_SYSTEM)/usr/keylayout/Ayaneo_Pocket_DS_Gamepad.kl

# Overlays — enforce runtime resource overlays
DEVICE_PACKAGE_OVERLAYS += device/ayaneo/pocket_ds/overlay
PRODUCT_ENFORCE_RRO_TARGETS := *

# Hardware features
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.host.xml \
    frameworks/native/data/etc/android.hardware.gamepad.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.gamepad.xml

# Fstab — install to vendor ramdisk for first-stage init mount
PRODUCT_COPY_FILES += \
    device/ayaneo/pocket_ds/rootdir/fstab.default:$(TARGET_COPY_OUT_VENDOR_RAMDISK)/first_stage_ramdisk/fstab.qcom \
    device/ayaneo/pocket_ds/rootdir/fstab.default:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.qcom

# Dynamic partitions — build system control (board-level config is in BoardConfig.mk)
PRODUCT_USE_DYNAMIC_PARTITIONS := true

# Virtual A/B (confirmed by lpdump: virtual_ab_device flag set)
# Required for OTA update engine to include snapshot merge service (snapuserd)
PRODUCT_VIRTUAL_AB_OTA := true

# A/B OTA packages
PRODUCT_PACKAGES += \
    update_engine \
    update_engine_sideload \
    update_verifier

# Boot control HAL
PRODUCT_PACKAGES += \
    android.hardware.boot@1.2-impl-qcom \
    android.hardware.boot@1.2-service

# Fastbootd
PRODUCT_PACKAGES += \
    fastbootd
