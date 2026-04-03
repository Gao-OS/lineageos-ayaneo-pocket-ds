#
# Copyright (C) 2024 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/ayaneo/pocket_ds

# Bringup flags — allow VINTF metadata in PRODUCT_COPY_FILES (stock blobs from vendor partition)
# TODO: Convert VINTF files to vintf_fragments modules after bringup
BUILD_BROKEN_VINTF_PRODUCT_COPY_FILES := true

# Allow duplicate install rules during bringup — vendor blobs may overlap with
# AOSP/LineageOS built modules. Remove after resolving all conflicts.
BUILD_BROKEN_DUP_RULES := true

# Allow ELF binaries in PRODUCT_COPY_FILES during bringup — vendor blobs contain
# .so/.bin ELF files that should eventually become cc_prebuilt_library_shared modules.
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# Platform (SM8750 "sun")
TARGET_BOARD_PLATFORM := sun

# Architecture — SM8750 Oryon is arm64-only (no 32-bit support on this SoC)
# Use armv8-2a: LineageOS 21 (Android 14) build system doesn't support armv9-a variant
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-2a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := kryo785

# 64-bit apps — SM8750 is a pure arm64 SoC
TARGET_SUPPORTS_64_BIT_APPS := true

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := sun
TARGET_NO_BOOTLOADER := true

# Kernel — prebuilt from stock boot.img (GKI 2.0)
# Do NOT set TARGET_KERNEL_SOURCE for a prebuilt kernel: LineageOS kernel.mk
# interprets a set TARGET_KERNEL_SOURCE as "build from source" and requires
# TARGET_KERNEL_CONFIG. Use TARGET_PREBUILT_KERNEL with a direct path instead.
KERNEL_PATH := kernel/ayaneo/sm8750
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_PREBUILT_KERNEL := $(KERNEL_PATH)/$(BOARD_KERNEL_IMAGE_NAME)

# DTB — extracted from stock vendor_boot.img (4.5 MB FDT)
BOARD_PREBUILT_DTBIMAGE_DIR := $(KERNEL_PATH)
BOARD_INCLUDE_DTB_IN_BOOTIMG := true

# DTBO — prebuilt from stock firmware (12 MB)
BOARD_PREBUILT_DTBOIMAGE := $(KERNEL_PATH)/dtbo.img

# Vendor kernel modules — 306 .ko files from stock vendor_boot ramdisk
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := \
    $(wildcard $(KERNEL_PATH)/vendor_ramdisk/lib/modules/*.ko)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := \
    $(KERNEL_PATH)/vendor_ramdisk/lib/modules/modules.load
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_BLOCKLIST_FILE := \
    $(KERNEL_PATH)/vendor_ramdisk/lib/modules/modules.blocklist

BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
# TODO: Extract actual offsets from stock boot.img header:
#   scripts/unpack-boot.sh stock-firmware/ufs/boot.img
#   Then set BOARD_KERNEL_OFFSET and BOARD_RAMDISK_OFFSET if non-standard.
# Qualcomm GKI 2.0 defaults (0x8000 / 0x1000000) are typically correct.
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x01000000

BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)

# Init boot (GKI 2.0)
BOARD_INIT_BOOT_HEADER_VERSION := 4

# Kernel command line from stock vendor_boot.img
# boot.img cmdline is empty; vendor_boot carries the actual args
BOARD_VENDOR_CMDLINE := \
    video=vfb:640x400,bpp=32,memsize=3072000 \
    qcom_geni_serial.con_enabled=0 \
    nosoftlockup \
    bootconfig

# boot.img cmdline is empty on this device (all args via vendor_boot)
BOARD_KERNEL_CMDLINE :=

# Bootconfig (from vendor_boot bootconfig section)
BOARD_BOOTCONFIG := \
    androidboot.hardware=qcom \
    androidboot.memcg=1 \
    androidboot.usbcontroller=a600000.dwc3

# GKI
BOARD_USES_GENERIC_KERNEL_IMAGE := true

# A/B — Virtual A/B with snapshot compression (confirmed by stock LP metadata flags)
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    init_boot \
    odm \
    product \
    recovery \
    system \
    system_dlkm \
    system_ext \
    vbmeta \
    vbmeta_system \
    vendor \
    vendor_boot \
    vendor_dlkm

# Ramdisk compression
BOARD_RAMDISK_USE_LZ4 := true

# Partitions — flash block size
BOARD_FLASH_BLOCK_SIZE := 262144 # 256 KB (64 * 4096 sector size)

# Partitions — fixed sizes (verified from rawprogram_unsparse4.xml, sector size = 4096)
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296        # 96 MB (24576 sectors)
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296 # 96 MB (24576 sectors)
BOARD_DTBOIMG_PARTITION_SIZE := 25165824           # 24 MB (6144 sectors) — stock is 24 MB not 12 MB
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608    # 8 MB (2048 sectors)
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600    # 100 MB (25600 sectors)

# Partitions — dynamic (super)
# Verified from stock firmware lpdump: super block device = 6,442,450,944 bytes
# Dynamic group max = 6,438,256,640 bytes, header flags = virtual_ab_device
BOARD_BUILD_SUPER_IMAGE_BY_DEFAULT := true
BOARD_SUPER_PARTITION_SIZE := 6442450944
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 6438256640
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system \
    system_dlkm \
    system_ext \
    vendor \
    vendor_dlkm \
    product \
    odm

# Partitions — filesystem types
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs

# Partitions — output paths
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/fstab.default
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
# TODO: Verify recovery density from stock device
TARGET_RECOVERY_UI_MARGIN_HEIGHT := 80

# AVB (Android Verified Boot)
# NOTE: Verification is intentionally disabled for bringup/development.
# Per project policy: vbmeta must be flashed with --disable-verity --disable-verification.
# The test key below is a development placeholder. Before any production flash, replace with
# a device-specific key and remove --flags 3 to re-enable verified boot.
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3

BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1

# SELinux
include device/qcom/sepolicy/SEPolicy.mk
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor
# TODO: Add device-specific sepolicy once policies are defined

# HIDL
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml
# TODO: Add framework compatibility matrix if needed
# DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := $(DEVICE_PATH)/framework_compatibility_matrix.xml

# Properties
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# TODO: Verify the following from actual firmware dumps:
# - Exact kernel command line arguments
# - Super partition size and layout
# - AVB key and rollback index
# - Display density and recovery UI settings
# - Wi-Fi, Bluetooth, and audio HAL configurations
