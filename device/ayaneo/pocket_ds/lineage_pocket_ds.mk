#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base.mk)

# Inherit from the device.
$(call inherit-product, device/ayaneo/pocket_ds/device.mk)

# Inherit some common Lineage stuff (Wi-Fi only handheld, no telephony).
$(call inherit-product, vendor/lineage/config/common_full_tablet_wifionly.mk)

PRODUCT_NAME := lineage_pocket_ds
PRODUCT_DEVICE := pocket_ds
PRODUCT_MANUFACTURER := AYANEO
PRODUCT_BRAND := AYANEO
PRODUCT_MODEL := Pocket DS

PRODUCT_SYSTEM_DEVICE := PocketDS
PRODUCT_SYSTEM_NAME := AYANEO_PocketDS

PRODUCT_GMS_CLIENTID_BASE := android-ayaneo

PRODUCT_BUILD_PROP_OVERRIDES += \
    SystemDevice=PocketDS \
    SystemName=AYANEO_PocketDS \
    DeviceProduct=pocket_ds
