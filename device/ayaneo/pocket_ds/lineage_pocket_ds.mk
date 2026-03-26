#
# LineageOS product definition for Ayaneo Pocket DS
#

# Inherit from device
$(call inherit-product, device/ayaneo/pocket_ds/device.mk)

# Inherit vendor blobs
$(call inherit-product, vendor/ayaneo/pocket_ds/pocket_ds-vendor.mk)

# Inherit LineageOS common config
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_NAME := lineage_pocket_ds
PRODUCT_DEVICE := pocket_ds
PRODUCT_BRAND := Ayaneo
PRODUCT_MODEL := Pocket DS
PRODUCT_MANUFACTURER := Ayaneo

PRODUCT_GMS_CLIENTID_BASE := android-ayaneo

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="pocket_ds-userdebug 14 UQ1A.240205.002 eng.build.20240101.000000 dev-keys"

BUILD_FINGERPRINT := Ayaneo/pocket_ds/pocket_ds:14/UQ1A.240205.002/eng.build.20240101.000000:userdebug/dev-keys
