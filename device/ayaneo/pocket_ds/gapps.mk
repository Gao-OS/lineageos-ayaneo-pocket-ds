#
# MindTheGapps integration
#
# Requires: local_manifests/gapps.xml synced with repo sync
#

WITH_GAPPS := true

# MindTheGapps for arm64
GAPPS_VARIANT := arm64

ifneq ($(wildcard vendor/gapps/arm64/arm64-vendor.mk),)
$(call inherit-product, vendor/gapps/arm64/arm64-vendor.mk)
else
$(warning MindTheGapps not found at vendor/gapps/arm64/arm64-vendor.mk)
$(warning Run: repo sync vendor/gapps)
endif
