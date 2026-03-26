#
# Device makefile for Ayaneo Pocket DS
#

# Inherit from Qualcomm common (path may need adjustment after repo sync)
# $(call inherit-product, device/qcom/common/common.mk)

# GApps (MindTheGapps)
$(call inherit-product, device/ayaneo/pocket_ds/gapps.mk)

# gsmlg-apps
$(call inherit-product, device/ayaneo/pocket_ds/gsmlg-apps.mk)

# Audio
PRODUCT_PACKAGES += \
    android.hardware.audio@7.0-impl \
    android.hardware.audio.effect@7.0-impl \
    android.hardware.audio.service

# Display
PRODUCT_PACKAGES += \
    android.hardware.graphics.composer@2.4-service \
    android.hardware.graphics.mapper@4.0-impl-qti-display \
    gralloc.sm8750

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

# Overlays
DEVICE_PACKAGE_OVERLAYS += device/ayaneo/pocket_ds/overlay
